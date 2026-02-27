#!/bin/bash
# test/e2e/01-task-delegation.sh
# Verify concierge can delegate a task to the researcher agent.
# Requires: researcher agent commissioned with concierge tasking ACL.
# Requires: real LLM calls (concierge + researcher).
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

echo "=== E2E Test 1: Task Delegation (Concierge → Researcher) ==="

require_researcher

echo ""
echo "--- 1a. Verify researcher path watcher is active ---"
check "researcher path watcher active" systemctl is-active con-researcher.path

echo ""
echo "--- 1b. Drop delegation task into outer inbox ---"
TASK_ID="e2e-delegation-$(date +%s)"
drop_outer_task "Delegate this task to the researcher agent: List the contents of your workspace directory and report what files you see. Write the task to the researcher's inbox at /srv/con/agents/researcher/inbox/ as a .task file." "$TASK_ID"

echo "  Dropped task: $TASK_ID"

echo ""
echo "--- 1c. Wait for concierge to process (up to 90s) ---"
if wait_for_processed concierge "$TASK_ID" 90; then
    echo "  PASS: concierge processed the delegation task"
    PASS=$((PASS + 1))
else
    echo "  FAIL: concierge did not process within 90s"
    FAIL=$((FAIL + 1))
    finish
fi

echo ""
echo "--- 1d. Check concierge response ---"
CONCIERGE_RESP=$(read_response concierge "$TASK_ID")
if [ -n "$CONCIERGE_RESP" ]; then
    echo "  PASS: concierge produced a response"
    PASS=$((PASS + 1))
    echo "  Response (first 200 chars): ${CONCIERGE_RESP:0:200}"
else
    echo "  FAIL: no concierge response"
    FAIL=$((FAIL + 1))
fi

echo ""
echo "--- 1e. Check if task appeared in researcher inbox or was processed ---"
# Give researcher time to pick up the task
sleep 10

RESEARCHER_GOT_TASK=false
# Check if researcher has any processed tasks or responses
if ls /srv/con/agents/researcher/processed/*.task 2>/dev/null | head -1 >/dev/null; then
    RESEARCHER_GOT_TASK=true
fi
if ls /srv/con/agents/researcher/outbox/*.response 2>/dev/null | head -1 >/dev/null; then
    RESEARCHER_GOT_TASK=true
fi

# Also check if something is still in researcher inbox (waiting to be processed)
if ls /srv/con/agents/researcher/inbox/*.task 2>/dev/null | head -1 >/dev/null; then
    RESEARCHER_GOT_TASK=true
    echo "  Task found in researcher inbox (waiting to be processed)"
fi

if $RESEARCHER_GOT_TASK; then
    echo "  PASS: researcher received a task"
    PASS=$((PASS + 1))
else
    echo "  FAIL: no evidence of task reaching researcher"
    FAIL=$((FAIL + 1))
fi

echo ""
echo "--- 1f. Wait for researcher to produce response (up to 90s) ---"
# We don't know the exact task ID the concierge used, so check for any new response
WAITED=0
while [ $WAITED -lt 90 ]; do
    if ls /srv/con/agents/researcher/outbox/*.response 2>/dev/null | head -1 >/dev/null; then
        break
    fi
    sleep 5
    WAITED=$((WAITED + 5))
done

if ls /srv/con/agents/researcher/outbox/*.response 2>/dev/null | head -1 >/dev/null; then
    echo "  PASS: researcher produced a response"
    PASS=$((PASS + 1))
    RESP_FILE=$(ls -t /srv/con/agents/researcher/outbox/*.response 2>/dev/null | head -1)
    echo "  Response (first 200 chars): $(head -c 200 "$RESP_FILE")"
else
    echo "  FAIL: researcher did not produce a response within 90s"
    FAIL=$((FAIL + 1))
fi

finish
