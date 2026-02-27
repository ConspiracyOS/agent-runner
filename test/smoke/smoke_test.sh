#!/bin/bash
# test/smoke/smoke_test.sh
# End-to-end smoke test for ConspiracyOS Phase 1.
# Run this INSIDE the VM after bootstrap completes.
set -euo pipefail

PASS=0
FAIL=0

check() {
    local desc="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        echo "  PASS: $desc"
        ((PASS++))
    else
        echo "  FAIL: $desc"
        ((FAIL++))
    fi
}

echo "=== ConspiracyOS Phase 1 Smoke Test ==="

echo ""
echo "--- 1. Bootstrap verification ---"
check "con binary exists" test -x /usr/local/bin/con
check "bootstrapped marker exists" test -f /srv/con/.bootstrapped
check "user a-concierge exists" id a-concierge
check "user a-sysadmin exists" id a-sysadmin
check "group agents exists" getent group agents
check "group operators exists" getent group operators

echo ""
echo "--- 2. Directory structure ---"
check "outer inbox exists" test -d /srv/con/inbox
check "concierge inbox exists" test -d /srv/con/agents/concierge/inbox
check "sysadmin inbox exists" test -d /srv/con/agents/sysadmin/inbox
check "concierge workspace exists" test -d /srv/con/agents/concierge/workspace
check "audit log dir exists" test -d /srv/con/logs/audit

echo ""
echo "--- 3. Permissions ---"
check "outer inbox is sticky" [ "$(stat -c %a /srv/con/inbox)" = "1777" ]
check "concierge home is private" [ "$(stat -c %a /home/a-concierge)" = "700" ]
check "concierge can write to sysadmin inbox" \
    su -s /bin/sh a-concierge -c "touch /srv/con/agents/sysadmin/inbox/.acl-test && rm /srv/con/agents/sysadmin/inbox/.acl-test"

echo ""
echo "--- 4. Systemd units ---"
check "concierge path unit enabled" systemctl is-enabled con-concierge.path
check "sysadmin path unit enabled" systemctl is-enabled con-sysadmin.path

echo ""
echo "--- 5. AGENTS.md assembled ---"
check "concierge AGENTS.md exists" test -f /home/a-concierge/AGENTS.md
check "sysadmin AGENTS.md exists" test -f /home/a-sysadmin/AGENTS.md
check "base content in concierge AGENTS.md" grep -q "ConspiracyOS" /home/a-concierge/AGENTS.md

echo ""
echo "--- 6. End-to-end task routing ---"
echo "Dropping task into outer inbox..."
echo "What agents are currently running in this conspiracy?" > /srv/con/inbox/001-smoke-test.task
echo "Waiting for concierge to process (up to 30s)..."

WAITED=0
while [ $WAITED -lt 30 ]; do
    if [ -f /srv/con/agents/concierge/processed/001-smoke-test.task ] 2>/dev/null || \
       ls /srv/con/agents/concierge/outbox/*.response 2>/dev/null | head -1 >/dev/null; then
        break
    fi
    sleep 2
    ((WAITED+=2))
done

check "task was picked up from outer inbox" test ! -f /srv/con/inbox/001-smoke-test.task
check "concierge produced output" ls /srv/con/agents/concierge/outbox/*.response 2>/dev/null

echo ""
echo "--- 7. Audit trail ---"
check "audit log has entries" test -s "/srv/con/logs/audit/$(date +%Y-%m-%d).log"

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ $FAIL -eq 0 ] && echo "ALL TESTS PASSED" || echo "SOME TESTS FAILED"
exit $FAIL
