#!/bin/bash
# test/e2e/04-escalation-loop.sh
# Verify healthcheck failure → sysadmin escalation → sysadmin processes the alert.
# Requires real LLM call (sysadmin must process the escalation task).
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

echo "=== E2E Test 4: Escalation Loop ==="

CONTRACTS_DIR="/srv/con/contracts"
ORIGINAL=$(cat "$CONTRACTS_DIR/CON-SYS-001.yaml")

echo ""
echo "--- 4a. Trigger healthcheck failure ---"
cat > "$CONTRACTS_DIR/CON-SYS-001.yaml" << 'EOF'
id: CON-SYS-001
description: Disk free space must remain above threshold (TEST - impossible)
type: detective
frequency: 60s
scope: system
checks:
  - name: disk_free_percentage
    command:
      run: "df /srv/con --output=pcent | tail -1 | tr -d ' %' | xargs -I{} expr 100 - {}"
      test: "[ $RESULT -ge 101 ]"
    on_fail:
      action: alert
      escalate: sysadmin
      message: "CON-SYS-001 FAILED: disk free below 101% - impossible threshold (E2E TEST - escalation loop test). Acknowledge this alert and report what you observe."
EOF
echo "  Contract overwritten (action: alert, escalate: sysadmin)"

# Use alert instead of halt_agents so we don't stop services mid-test
con healthcheck 2>/dev/null || true

echo ""
echo "--- 4b. Verify escalation task landed in sysadmin inbox ---"
check "escalation task in sysadmin inbox" \
    ls /srv/con/agents/sysadmin/inbox/*healthcheck*.task 2>/dev/null

echo ""
echo "--- 4c. Wait for sysadmin to process escalation (up to 90s) ---"
# Find the escalation task ID
ESCALATION_TASK=$(ls /srv/con/agents/sysadmin/inbox/*healthcheck*.task 2>/dev/null | head -1 | xargs basename | sed 's/.task$//')
if [ -n "$ESCALATION_TASK" ]; then
    echo "  Waiting for sysadmin to process: ${ESCALATION_TASK}.task"
    if wait_for_processed sysadmin "$ESCALATION_TASK" 90; then
        echo "  PASS: sysadmin processed the escalation task"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: sysadmin did not process escalation within 90s"
        FAIL=$((FAIL + 1))
    fi
else
    echo "  FAIL: no escalation task found"
    FAIL=$((FAIL + 1))
fi

echo ""
echo "--- 4d. Check sysadmin response ---"
if [ -n "$ESCALATION_TASK" ]; then
    RESPONSE=$(read_response sysadmin "$ESCALATION_TASK")
    if [ -n "$RESPONSE" ]; then
        echo "  PASS: sysadmin produced a response"
        PASS=$((PASS + 1))
        echo "  Response (first 200 chars):"
        echo "  ${RESPONSE:0:200}"
    else
        echo "  FAIL: no response file for escalation task"
        FAIL=$((FAIL + 1))
    fi
fi

echo ""
echo "--- 4e. Restore original contract ---"
printf '%s' "$ORIGINAL" > "$CONTRACTS_DIR/CON-SYS-001.yaml"
echo "  Contract restored"
check "healthcheck passes after restore" con healthcheck

finish
