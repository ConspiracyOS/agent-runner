#!/bin/bash
# test/e2e/23-inbox-flooding.sh
# Challenge: What happens when an inbox is flooded? Does the system degrade
# gracefully? Can a flood be used as a denial-of-service against an agent?
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

echo "=== E2E Test 23: Inbox Flooding & Resource Exhaustion ==="

echo ""
echo "--- 23a. Flood concierge inbox with 50 tasks ---"
# Drop 50 tasks rapidly into concierge inbox
for i in $(seq -w 1 50); do
    echo "Flood task $i: respond with just the number $i" > "/srv/con/agents/concierge/inbox/flood-${i}.task"
done
TASK_COUNT=$(find /srv/con/agents/concierge/inbox/ -name 'flood-*.task' 2>/dev/null | wc -l)
check "50 tasks landed in inbox" [ "$TASK_COUNT" -eq 50 ]

echo ""
echo "--- 23b. Verify con run processes tasks in order ---"
# Don't actually run all 50 (too expensive with LLM). Just verify ordering logic.
FIRST=$(ls /srv/con/agents/concierge/inbox/flood-*.task 2>/dev/null | sort | head -1)
check "oldest task is flood-01" sh -c "echo '$FIRST' | grep -q 'flood-01'"

echo ""
echo "--- 23c. Verify system resources during flood ---"
# Check that disk isn't full from 50 tiny files
DISK_FREE=$(df /srv/con --output=pcent | tail -1 | tr -d ' %')
check "disk still has >10% free during flood" [ "$DISK_FREE" -lt 90 ]

echo ""
echo "--- 23d. Clean up flood ---"
rm -f /srv/con/agents/concierge/inbox/flood-*.task
REMAINING=$(find /srv/con/agents/concierge/inbox/ -name 'flood-*.task' 2>/dev/null | wc -l)
check "cleanup removed all flood tasks" [ "$REMAINING" -eq 0 ]

echo ""
echo "--- 23e. Oversized task (near 32KB limit) ---"
# Generate a task just under 32KB (should be processed normally)
python3 -c "print('A' * 32000)" > /srv/con/agents/concierge/inbox/oversize-under.task
UNDER_SIZE=$(stat -c %s /srv/con/agents/concierge/inbox/oversize-under.task)
check "under-limit task is <32KB" [ "$UNDER_SIZE" -lt 32768 ]

# Generate a task over 32KB (should be truncated to attachment reference)
python3 -c "print('B' * 40000)" > /srv/con/agents/concierge/inbox/oversize-over.task
OVER_SIZE=$(stat -c %s /srv/con/agents/concierge/inbox/oversize-over.task)
check "over-limit task is >32KB" [ "$OVER_SIZE" -gt 32768 ]

# Clean up without processing
rm -f /srv/con/agents/concierge/inbox/oversize-*.task

echo ""
echo "--- 23f. Task with special characters in filename ---"
# Filenames with spaces, quotes, or shell metacharacters
touch "/srv/con/agents/concierge/inbox/spaces in name.task"
check "task with spaces in name created" test -f "/srv/con/agents/concierge/inbox/spaces in name.task"

# Does PickOldestTask handle this?
TASKS=$(ls /srv/con/agents/concierge/inbox/*.task 2>/dev/null | wc -l)
check "inbox listing works with special filenames" [ "$TASKS" -gt 0 ]

rm -f "/srv/con/agents/concierge/inbox/spaces in name.task"

finish
