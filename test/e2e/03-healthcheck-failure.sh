#!/bin/bash
# test/e2e/03-healthcheck-failure.sh
# Verify healthcheck detects failures and dispatches actions.
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

echo "=== E2E Test 3: Healthcheck Failure Actions ==="

# Save original contract
CONTRACTS_DIR="/srv/con/contracts"
ORIGINAL=$(cat "$CONTRACTS_DIR/CON-SYS-001.yaml")

echo ""
echo "--- 3a. Replace CON-SYS-001 with impossible threshold ---"
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
      action: halt_agents
      escalate: sysadmin
      message: "CON-SYS-001 FAILED: disk free below 101% - impossible threshold (E2E TEST)"
EOF
echo "  Contract overwritten with 99% threshold"

echo ""
echo "--- 3b. Run healthcheck — expect failure ---"
if con healthcheck 2>/dev/null; then
    echo "  FAIL: healthcheck should have exited non-zero"
    FAIL=$((FAIL + 1))
else
    echo "  PASS: healthcheck exited non-zero"
    PASS=$((PASS + 1))
fi

echo ""
echo "--- 3c. Check that failure was logged ---"
LOGFILE="/srv/con/logs/audit/contracts.log"
check "failure logged in contracts.log" grep -q "CON-SYS-001 FAIL" "$LOGFILE"

echo ""
echo "--- 3d. Check that escalation task was written to sysadmin inbox ---"
check "escalation task exists in sysadmin inbox" \
    ls /srv/con/agents/sysadmin/inbox/*healthcheck*.task 2>/dev/null

echo ""
echo "--- 3e. Read escalation task content ---"
if ls /srv/con/agents/sysadmin/inbox/*healthcheck*.task >/dev/null 2>&1; then
    echo "  Escalation message:"
    cat /srv/con/agents/sysadmin/inbox/*healthcheck*.task
    echo ""
fi

echo ""
echo "--- 3f. Restore original contract ---"
printf '%s' "$ORIGINAL" > "$CONTRACTS_DIR/CON-SYS-001.yaml"
echo "  Contract restored"

echo ""
echo "--- 3g. Verify healthcheck passes with restored contract ---"
check "healthcheck passes after restore" con healthcheck

echo ""
echo "--- 3h. Clean up escalation tasks ---"
rm -f /srv/con/agents/sysadmin/inbox/*healthcheck*.task 2>/dev/null
echo "  Cleaned up escalation tasks from sysadmin inbox"

finish
