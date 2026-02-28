#!/bin/bash
# test/e2e/27-contract-timing-gap.sh
# Challenge: Detective contracts run every 60s. What happens in the gap?
# A broken invariant can exist for up to 59 seconds undetected.
# This test measures how long it takes for contracts to detect a violation.
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

echo "=== E2E Test 27: Contract Timing Gap ==="

echo ""
echo "--- 27a. Measure healthcheck interval ---"
# Parse the timer interval from the systemd timer
INTERVAL=$(systemctl show con-healthcheck.timer --property=TimersCalendar 2>/dev/null | head -1 || echo "unknown")
echo "  Timer config: $INTERVAL"

# Or check the config
if [ -f /etc/con/con.toml ]; then
    CONFIG_INTERVAL=$(grep -i "healthcheck_interval" /etc/con/con.toml | head -1 || echo "not set")
    echo "  Config interval: $CONFIG_INTERVAL"
fi

echo ""
echo "--- 27b. Break a contract and time detection ---"
# Save original contract
CONTRACT_FILE="/srv/con/contracts/CON-SYS-005.yaml"
BACKUP="/tmp/CON-SYS-005.yaml.bak"
cp "$CONTRACT_FILE" "$BACKUP"

# Break the contract (impossible check)
cat > "$CONTRACT_FILE" << 'YAML'
id: CON-SYS-005
description: Audit log directory is writable
type: detective
scope: system
checks:
  - name: audit_log_writable
    command:
      run: "test -w /nonexistent/path/that/will/never/exist"
      test: exit_code_zero
    on_fail: escalate
YAML

BREAK_TIME=$(date +%s)
echo "  Contract broken at: $(date -d @$BREAK_TIME '+%H:%M:%S' 2>/dev/null || date -r $BREAK_TIME '+%H:%M:%S')"

echo ""
echo "--- 27c. Wait for next healthcheck cycle ---"
# Run healthcheck manually to verify detection works
con healthcheck 2>/dev/null || true
DETECT_TIME=$(date +%s)

# Check contracts.log for the failure
DETECTED=false
if grep -q "CON-SYS-005.*FAIL" /srv/con/logs/audit/contracts.log 2>/dev/null; then
    DETECTED=true
fi

ELAPSED=$((DETECT_TIME - BREAK_TIME))
echo "  Detection after manual healthcheck: ${ELAPSED}s"
check "broken contract detected" $DETECTED

echo ""
echo "--- 27d. Restore and verify recovery ---"
cp "$BACKUP" "$CONTRACT_FILE"
rm -f "$BACKUP"

con healthcheck 2>/dev/null
check "contract passes after restoration" con healthcheck 2>/dev/null

echo ""
echo "--- 27e. Document the gap ---"
echo "  NOTE: Between healthcheck cycles (up to 60s), broken invariants are undetected."
echo "  NOTE: This is by design (detective, not preventive). The question is:"
echo "  NOTE: What damage can occur in 60s that a preventive control would have stopped?"
echo "  NOTE: Answer: only things NOT enforced by Linux permissions/ACLs/sudoers."

finish
