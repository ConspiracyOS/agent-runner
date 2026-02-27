#!/bin/bash
# test/e2e/06-concurrent-tasks.sh
# Verify agent handles multiple tasks in inbox without corruption.
# Drops two tasks simultaneously, waits for both to be processed.
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

echo "=== E2E Test 6: Concurrent Tasks ==="

# Use concierge for this test (always available)
AGENT="concierge"

echo ""
echo "--- 6a. Stop path watcher to batch-load tasks ---"
systemctl stop con-concierge.path 2>/dev/null || true

echo ""
echo "--- 6b. Drop two tasks into inbox ---"
TASK_A="e2e-concurrent-a"
TASK_B="e2e-concurrent-b"

drop_task "$AGENT" "Reply with exactly: RESPONSE_A" "$TASK_A"
drop_task "$AGENT" "Reply with exactly: RESPONSE_B" "$TASK_B"

check "task A in inbox" test -f "/srv/con/agents/$AGENT/inbox/${TASK_A}.task"
check "task B in inbox" test -f "/srv/con/agents/$AGENT/inbox/${TASK_B}.task"

echo ""
echo "--- 6c. Re-enable path watcher and trigger ---"
systemctl start con-concierge.path

# Touch inbox to trigger the watcher
touch "/srv/con/agents/$AGENT/inbox/"

echo ""
echo "--- 6d. Wait for first task to process (up to 60s) ---"
# The runner picks the oldest (lexicographically first) task per invocation.
# After processing one, the path watcher must fire again for the second.
if wait_for_processed "$AGENT" "$TASK_A" 60; then
    echo "  PASS: task A processed"
    PASS=$((PASS + 1))
else
    echo "  FAIL: task A not processed within 60s"
    FAIL=$((FAIL + 1))
fi

echo ""
echo "--- 6e. Trigger second run ---"
# Path watcher may not re-trigger automatically after first run.
# Touch inbox to ensure it fires.
sleep 2
touch "/srv/con/agents/$AGENT/inbox/"

echo ""
echo "--- 6f. Wait for second task to process (up to 60s) ---"
if wait_for_processed "$AGENT" "$TASK_B" 60; then
    echo "  PASS: task B processed"
    PASS=$((PASS + 1))
else
    echo "  FAIL: task B not processed within 60s"
    FAIL=$((FAIL + 1))
fi

echo ""
echo "--- 6g. Verify both responses exist ---"
check "response A exists" ls "/srv/con/agents/$AGENT/outbox/"*"${TASK_A}"*.response 2>/dev/null
check "response B exists" ls "/srv/con/agents/$AGENT/outbox/"*"${TASK_B}"*.response 2>/dev/null

echo ""
echo "--- 6h. Verify responses are distinct ---"
RESP_A=$(read_response "$AGENT" "$TASK_A")
RESP_B=$(read_response "$AGENT" "$TASK_B")

if [ -n "$RESP_A" ] && [ -n "$RESP_B" ]; then
    echo "  Response A (first 100 chars): ${RESP_A:0:100}"
    echo "  Response B (first 100 chars): ${RESP_B:0:100}"
    if [ "$RESP_A" != "$RESP_B" ]; then
        echo "  PASS: responses are distinct"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: responses are identical (possible corruption)"
        FAIL=$((FAIL + 1))
    fi
else
    echo "  FAIL: one or both responses missing"
    FAIL=$((FAIL + 1))
fi

finish
