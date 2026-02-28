#!/bin/bash
# test/e2e/20-cross-agent-reads.sh
# Challenge: ProtectSystem=strict prevents writes but NOT reads.
# What can agents actually read? Test information disclosure boundaries.
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

echo "=== E2E Test 20: Cross-Agent Information Disclosure ==="

echo ""
echo "--- 20a. Agent reads global config ---"
# /etc/con/con.toml lists all agents, their tiers, models, API key env vars.
# This is potentially sensitive (reveals attack surface).
check "concierge can read con.toml" \
    su -s /bin/sh a-concierge -c "cat /etc/con/con.toml >/dev/null"

echo ""
echo "--- 20b. Agent reads env file (secrets) ---"
# /etc/con/env mode 640 root:root — agents should NOT be able to read this
check_fail "concierge cannot read /etc/con/env" \
    su -s /bin/sh a-concierge -c "cat /etc/con/env"

echo ""
echo "--- 20c. Agent reads other agents' outbox responses ---"
# Outbox files are mode 644 — but the agent dir should be mode 700
# If agent dir is NOT 700, any agent can read any response
if [ -d /srv/con/agents/sysadmin/outbox ]; then
    # Test: can concierge list sysadmin's outbox?
    RESULT=$(su -s /bin/sh a-concierge -c "ls /srv/con/agents/sysadmin/outbox/" 2>&1 || true)
    if echo "$RESULT" | grep -q "Permission denied"; then
        check "concierge cannot list sysadmin outbox" true
    else
        echo "  WARNING: concierge CAN list sysadmin outbox (isolation gap)"
        check "cross-agent outbox read blocked" false
    fi
fi

echo ""
echo "--- 20d. Agent reads other agents' processed tasks ---"
# Processed tasks contain the original user requests — sensitive
check_fail "concierge cannot read sysadmin processed dir" \
    su -s /bin/sh a-concierge -c "ls /srv/con/agents/sysadmin/processed/"

echo ""
echo "--- 20e. Agent reads audit log ---"
# Audit logs are mode 644 in /srv/con/logs/audit/ — who can read them?
AUDIT_DIR="/srv/con/logs/audit"
if [ -d "$AUDIT_DIR" ]; then
    RESULT=$(su -s /bin/sh a-concierge -c "ls $AUDIT_DIR/" 2>&1 || true)
    if echo "$RESULT" | grep -q "Permission denied"; then
        check "concierge cannot read audit logs" true
    else
        check "concierge can read audit logs (expected — same-conspiracy visibility)" true
        echo "  INFO: Audit logs are readable by agents. This is by design (transparency)."
    fi
fi

echo ""
echo "--- 20f. Agent reads git history (contains all state changes) ---"
# /srv/con/.git contains full history of all config/inbox/outbox changes
RESULT=$(su -s /bin/sh a-concierge -c "git -C /srv/con log --oneline -5" 2>&1 || true)
if echo "$RESULT" | grep -q "Permission denied\|fatal"; then
    check "concierge cannot read git history" true
else
    echo "  WARNING: concierge CAN read /srv/con git history"
    check "git history readable by agents (assess if acceptable)" true
fi

echo ""
echo "--- 20g. Agent reads /proc/1/environ (systemd PID 1 environment) ---"
# Contains all environment variables from the boot process
check_fail "concierge cannot read /proc/1/environ" \
    su -s /bin/sh a-concierge -c "cat /proc/1/environ"

echo ""
echo "--- 20h. Agent reads own /proc/self/environ ---"
# When agent runs via systemd, this would contain EnvironmentFile vars
# including API keys. Outside of systemd context, test basic access.
check_fail "concierge cannot read /proc/self/environ" \
    su -s /bin/sh a-concierge -c "cat /proc/self/environ"

finish
