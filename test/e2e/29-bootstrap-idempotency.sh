#!/bin/bash
# test/e2e/29-bootstrap-idempotency.sh
# Challenge: Bootstrap is supposed to be idempotent — running it twice
# should produce the same state. Verify this actually holds.
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

echo "=== E2E Test 29: Bootstrap Idempotency ==="

echo ""
echo "--- 29a. Snapshot state before second bootstrap ---"
# Capture key state
USERS_BEFORE=$(getent passwd | grep "^a-" | sort)
GROUPS_BEFORE=$(getent group | grep -E "^(agents|operators|trusted)" | sort)
UNITS_BEFORE=$(systemctl list-unit-files "con-*" --no-pager 2>/dev/null | sort)
AGENTS_MD_HASH=$(md5sum /home/a-concierge/AGENTS.md 2>/dev/null | awk '{print $1}')
PERMS_INBOX=$(stat -c %a /srv/con/inbox)
PERMS_CONCIERGE_HOME=$(stat -c %a /home/a-concierge)

echo ""
echo "--- 29b. Run bootstrap again ---"
con bootstrap 2>/dev/null

echo ""
echo "--- 29c. Verify state is identical ---"
USERS_AFTER=$(getent passwd | grep "^a-" | sort)
GROUPS_AFTER=$(getent group | grep -E "^(agents|operators|trusted)" | sort)
UNITS_AFTER=$(systemctl list-unit-files "con-*" --no-pager 2>/dev/null | sort)
AGENTS_MD_HASH_AFTER=$(md5sum /home/a-concierge/AGENTS.md 2>/dev/null | awk '{print $1}')
PERMS_INBOX_AFTER=$(stat -c %a /srv/con/inbox)
PERMS_CONCIERGE_HOME_AFTER=$(stat -c %a /home/a-concierge)

check "users unchanged" [ "$USERS_BEFORE" = "$USERS_AFTER" ]
check "groups unchanged" [ "$GROUPS_BEFORE" = "$GROUPS_AFTER" ]
check "systemd units unchanged" [ "$UNITS_BEFORE" = "$UNITS_AFTER" ]
check "AGENTS.md hash unchanged" [ "$AGENTS_MD_HASH" = "$AGENTS_MD_HASH_AFTER" ]
check "inbox permissions unchanged" [ "$PERMS_INBOX" = "$PERMS_INBOX_AFTER" ]
check "home permissions unchanged" [ "$PERMS_CONCIERGE_HOME" = "$PERMS_CONCIERGE_HOME_AFTER" ]

echo ""
echo "--- 29d. Verify services still running after double bootstrap ---"
check "concierge watcher still active" systemctl is-active con-concierge.path
check "sysadmin watcher still active" systemctl is-active con-sysadmin.path
check "healthcheck timer still active" systemctl is-active con-healthcheck.timer

echo ""
echo "--- 29e. Verify skills survived double bootstrap ---"
SKILL_COUNT=$(ls /srv/con/agents/sysadmin/workspace/skills/*.md 2>/dev/null | wc -l)
check "sysadmin still has skills" [ "$SKILL_COUNT" -gt 0 ]

echo ""
echo "--- 29f. Verify git repo survived double bootstrap ---"
check "git repo still valid" git -C /srv/con status
GIT_CLEAN=$(git -C /srv/con status --porcelain | wc -l)
# Bootstrap may create new commits, but repo should be clean after
echo "  Uncommitted changes: $GIT_CLEAN"

finish
