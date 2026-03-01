#!/bin/bash
# test/e2e/07-git-snapshot.sh
# Verify that agent runs produce git commits in /srv/con/.
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

echo "=== E2E Test 7: Git Snapshots ==="

# Record current commit count
BEFORE=$(git -C /srv/con rev-list --count HEAD 2>/dev/null || echo 0)

echo ""
echo "--- 7a. Drop task and wait for processing ---"
TASK_ID=$(drop_task concierge "Respond with: snapshot test complete")
wait_for_response concierge "$TASK_ID" 60
check "concierge produced response" read_response concierge "$TASK_ID"

echo ""
echo "--- 7b. Verify git commit was created ---"
AFTER=$(git -C /srv/con rev-list --count HEAD)
check "new git commit exists" [ "$AFTER" -gt "$BEFORE" ]

echo ""
echo "--- 7c. Verify commit message format ---"
LATEST_MSG=$(git -C /srv/con log -1 --format=%s)
check "commit message contains agent name" sh -c "echo '$LATEST_MSG' | grep -q 'concierge'"
check "commit message contains trust level" sh -c "echo '$LATEST_MSG' | grep -qE '\[(verified|unverified)\]'"

echo ""
echo "--- 7d. Verify git identity ---"
AUTHOR=$(git -C /srv/con log -1 --format=%an)
check "commit author is con" [ "$AUTHOR" = "con" ]

finish
