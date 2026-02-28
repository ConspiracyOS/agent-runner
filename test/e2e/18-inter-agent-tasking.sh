#!/bin/bash
# test/e2e/18-inter-agent-tasking.sh
# Verify the full inter-agent communication pipeline:
# user → outer inbox → concierge routes → sysadmin processes → response chain.
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

echo "=== E2E Test 18: Inter-Agent Tasking Pipeline ==="

echo ""
echo "--- 18a. Route through outer inbox to concierge ---"
TASK_ID="e2e-18-$(date +%s)"
drop_outer_task "Check how much disk space is available on this system and report back." "$TASK_ID"

# Wait for concierge to pick it up from outer inbox
echo "Waiting for concierge to pick up outer inbox task..."
sleep 5

check "task removed from outer inbox" \
    test ! -f "/srv/con/inbox/${TASK_ID}.task"

# Wait for concierge response
wait_for_response concierge "$TASK_ID" 120

RESPONSE=$(read_response concierge "$TASK_ID")
check "concierge produced a response" test -n "$RESPONSE"

if [ -n "$RESPONSE" ]; then
    # Concierge might answer directly (simple system question it can handle)
    # or route to sysadmin. Either is acceptable.
    HAS_ANSWER=$(echo "$RESPONSE" | grep -ciE "disk|space|free|available|GB|MB|%" || true)
    HAS_ROUTING=$(echo "$RESPONSE" | grep -ciE "routed.*sysadmin|sysadmin" || true)
    check "concierge answered or routed" test "$((HAS_ANSWER + HAS_ROUTING))" -gt 0
fi

echo ""
echo "--- 18b. Verify task provenance through pipeline ---"
# Outer inbox tasks are owned by root (dropped by con task command or tests)
# After concierge routes to sysadmin, the task in sysadmin inbox should be
# owned by a-concierge (agent-routed = unverified)
if ls /srv/con/agents/sysadmin/inbox/*.task 2>/dev/null | head -1 >/dev/null; then
    SYSADMIN_TASK=$(ls -t /srv/con/agents/sysadmin/inbox/*.task 2>/dev/null | head -1)
    if [ -n "$SYSADMIN_TASK" ]; then
        OWNER=$(stat -c %U "$SYSADMIN_TASK")
        check "sysadmin task owned by concierge user" [ "$OWNER" = "a-concierge" ]
    fi
else
    echo "  SKIP: no task in sysadmin inbox (concierge may have answered directly)"
fi

echo ""
echo "--- 18c. Concurrent outer inbox tasks ---"
# Drop two tasks at once, verify both are processed
TASK_A="e2e-18a-$(date +%s)"
TASK_B="e2e-18b-$(($(date +%s) + 1))"
drop_outer_task "What is the current system load average?" "$TASK_A"
drop_outer_task "How many agents are currently commissioned?" "$TASK_B"

echo "Waiting for both tasks to be processed..."
wait_for_response concierge "$TASK_A" 120
wait_for_response concierge "$TASK_B" 120

RESP_A=$(read_response concierge "$TASK_A")
RESP_B=$(read_response concierge "$TASK_B")
check "first concurrent task got response" test -n "$RESP_A"
check "second concurrent task got response" test -n "$RESP_B"

finish
