#!/bin/bash
# test/e2e/helpers.sh
# Shared helpers for ConspiracyOS E2E tests.
# Source this from each test script.

PASS=0
FAIL=0

check() {
    local desc="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc"
        FAIL=$((FAIL + 1))
    fi
}

check_fail() {
    local desc="$1"
    shift
    if ! "$@" >/dev/null 2>&1; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (expected failure but succeeded)"
        FAIL=$((FAIL + 1))
    fi
}

# Drop a task directly into an agent's inbox.
# Usage: drop_task <agent-name> <message> [task-id]
drop_task() {
    local agent="$1"
    local msg="$2"
    local task_id="${3:-$(date +%s)-e2e}"
    local inbox="/srv/con/agents/$agent/inbox"
    printf '%s' "$msg" > "$inbox/${task_id}.task"
    echo "$task_id"
}

# Drop a task into the outer inbox (routes through concierge).
# Usage: drop_outer_task <message> [task-id]
drop_outer_task() {
    local msg="$1"
    local task_id="${2:-$(date +%s)-e2e}"
    printf '%s' "$msg" > "/srv/con/inbox/${task_id}.task"
    echo "$task_id"
}

# Wait for a response file to appear in an agent's outbox.
# Usage: wait_for_response <agent-name> <task-id> [timeout-seconds]
# Returns 0 if found, 1 if timeout.
wait_for_response() {
    local agent="$1"
    local task_id="$2"
    local timeout="${3:-60}"
    local outbox="/srv/con/agents/$agent/outbox"
    local waited=0

    while [ $waited -lt "$timeout" ]; do
        if ls "$outbox"/*"${task_id}"*.response 2>/dev/null | head -1 >/dev/null; then
            return 0
        fi
        sleep 2
        waited=$((waited + 2))
    done
    return 1
}

# Wait for a task to move to processed.
# Usage: wait_for_processed <agent-name> <task-id> [timeout-seconds]
wait_for_processed() {
    local agent="$1"
    local task_id="$2"
    local timeout="${3:-60}"
    local processed="/srv/con/agents/$agent/processed"
    local waited=0

    while [ $waited -lt "$timeout" ]; do
        if [ -f "$processed/${task_id}.task" ]; then
            return 0
        fi
        sleep 2
        waited=$((waited + 2))
    done
    return 1
}

# Read the response content for a task.
# Usage: read_response <agent-name> <task-id>
read_response() {
    local agent="$1"
    local task_id="$2"
    local outbox="/srv/con/agents/$agent/outbox"
    cat "$outbox"/*"${task_id}"*.response 2>/dev/null
}

# Print test summary and exit with failure count.
finish() {
    echo ""
    echo "=== Results: $PASS passed, $FAIL failed ==="
    [ $FAIL -eq 0 ] && echo "ALL TESTS PASSED" || echo "SOME TESTS FAILED"
    exit $FAIL
}

# Check if researcher agent exists. Skip test if not.
require_researcher() {
    if ! id a-researcher >/dev/null 2>&1; then
        echo "SKIP: researcher agent not commissioned. Run sysadmin commission first."
        exit 0
    fi
}
