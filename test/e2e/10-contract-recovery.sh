#!/bin/bash
# test/e2e/10-contract-recovery.sh
# Verify that contract failures escalate to sysadmin and can be remediated.
# This test temporarily breaks a contract, verifies escalation, then restores it.
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

echo "=== E2E Test 10: Contract Recovery ==="

CONTRACT_FILE="/srv/con/contracts/CON-SYS-005.yaml"
BACKUP="/tmp/CON-SYS-005.yaml.bak"

# Safety: backup the original contract
cp "$CONTRACT_FILE" "$BACKUP"

echo ""
echo "--- 10a. Break the audit_log_writable contract ---"
# Change the check to test a nonexistent path (guaranteed fail)
cat > "$CONTRACT_FILE" << 'YAML'
id: CON-SYS-005
description: Audit log directory is writable
type: detective
scope: system
checks:
  - name: audit_log_writable
    command:
      run: "test -w /srv/con/logs/audit/NONEXISTENT_DIR_FOR_TEST"
      test: exit_code_zero
    on_fail: escalate
YAML

echo ""
echo "--- 10b. Run healthcheck and verify failure ---"
# Run healthcheck (expect exit 1 due to failure)
con healthcheck 2>/dev/null || true

# Check that the failure was logged
check "contract failure logged" grep -q "CON-SYS-005.*FAIL" /srv/con/logs/audit/contracts.log

echo ""
echo "--- 10c. Verify escalation task was created ---"
# Escalation creates a task in sysadmin's inbox
sleep 2
ESCALATION_EXISTS=false
for f in /srv/con/agents/sysadmin/inbox/*.task; do
    [ -f "$f" ] || continue
    if grep -q "CON-SYS-005" "$f" 2>/dev/null; then
        ESCALATION_EXISTS=true
        break
    fi
done
check "escalation task in sysadmin inbox" $ESCALATION_EXISTS

echo ""
echo "--- 10d. Restore the contract ---"
cp "$BACKUP" "$CONTRACT_FILE"
rm -f "$BACKUP"

echo ""
echo "--- 10e. Verify contract passes after restoration ---"
con healthcheck 2>/dev/null
check "contract passes after restore" con healthcheck 2>/dev/null

finish
