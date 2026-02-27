#!/bin/bash
# test/e2e/05-agent-resilience.sh
# Verify CON-SYS-004 detects long-running agent sessions.
# Simulates a hung agent by creating a fake long-running "con run" process.
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

echo "=== E2E Test 5: Agent Resilience (Session Timeout) ==="

require_researcher

echo ""
echo "--- 5a. Create a fake long-running 'con run' process as researcher ---"
# Create a wrapper script that appears as "con run researcher" in ps args
cat > /tmp/fake-con-run.sh << 'SCRIPT'
#!/bin/sh
sleep 3600
SCRIPT
chmod +x /tmp/fake-con-run.sh
su -s /bin/sh a-researcher -c "nohup /tmp/fake-con-run.sh con run researcher >/dev/null 2>&1 &"
sleep 3  # Wait for process to accumulate >1 second of runtime

# Verify the process exists
check "fake 'con run' process running as a-researcher" \
    pgrep -u a-researcher -f "con run"

echo ""
echo "--- 5b. Override CON-SYS-004 to use 1-second threshold ---"
CONTRACTS_DIR="/srv/con/contracts"
ORIGINAL_004=$(cat "$CONTRACTS_DIR/CON-SYS-004.yaml" 2>/dev/null || echo "")

cat > "$CONTRACTS_DIR/CON-SYS-004.yaml" << 'EOF'
id: CON-SYS-004
description: Agent sessions must not exceed 1 second (TEST)
type: detective
frequency: 60s
scope: system
checks:
  - name: session_duration
    command:
      run: "ps -eo user,etimes,args --no-headers | grep '[c]on run' | awk '{if ($2 > 1) print $1}' | head -1 | sed 's/^a-//'"
      test: "[ -z \"$RESULT\" ]"
    on_fail:
      action: alert
      escalate: sysadmin
      message: "CON-SYS-004 FAILED: agent session exceeds threshold (E2E TEST)"
EOF
echo "  Contract overwritten with 1s threshold"

echo ""
echo "--- 5c. Run healthcheck — expect CON-SYS-004 failure ---"
# Capture healthcheck output to check specifically for CON-SYS-004
HC_OUTPUT=$(con healthcheck 2>&1 || true)
echo "$HC_OUTPUT"

if echo "$HC_OUTPUT" | grep -q "CON-SYS-004 FAIL"; then
    echo "  PASS: CON-SYS-004 detected long-running session"
    PASS=$((PASS + 1))
else
    echo "  FAIL: CON-SYS-004 should have detected long-running session"
    FAIL=$((FAIL + 1))
fi

echo ""
echo "--- 5d. Verify failure was logged ---"
LOGFILE="/srv/con/logs/audit/contracts.log"
check "CON-SYS-004 failure logged" grep -q "CON-SYS-004 FAIL" "$LOGFILE"

echo ""
echo "--- 5e. Clean up ---"
# Kill the fake process
pkill -u a-researcher -f "con run" 2>/dev/null || true
sleep 1
check_fail "fake 'con run' process killed" pgrep -u a-researcher -f "con run"
rm -f /tmp/fake-con-run.sh

# Restore contract
if [ -n "$ORIGINAL_004" ]; then
    printf '%s' "$ORIGINAL_004" > "$CONTRACTS_DIR/CON-SYS-004.yaml"
else
    rm -f "$CONTRACTS_DIR/CON-SYS-004.yaml"
fi
echo "  Contract restored"

# Clean up escalation tasks
rm -f /srv/con/agents/sysadmin/inbox/*healthcheck*.task 2>/dev/null

# Verify CON-SYS-004 specifically passes now (other contracts may still fail)
HC_OUTPUT2=$(con healthcheck 2>&1 || true)
if echo "$HC_OUTPUT2" | grep -q "CON-SYS-004 PASS"; then
    echo "  PASS: CON-SYS-004 passes after cleanup"
    PASS=$((PASS + 1))
else
    echo "  FAIL: CON-SYS-004 should pass after cleanup"
    FAIL=$((FAIL + 1))
fi

finish
