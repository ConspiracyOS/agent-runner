#!/bin/bash
# test/e2e/02-permission-boundaries.sh
# Verify Linux permission boundaries hold for agents.
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

echo "=== E2E Test 2: Permission Boundaries ==="

require_researcher

echo ""
echo "--- 2a. Researcher cannot read /etc/shadow ---"
check_fail "researcher cannot read /etc/shadow" \
    su -s /bin/sh a-researcher -c "cat /etc/shadow"

echo ""
echo "--- 2b. Researcher cannot write to sysadmin inbox ---"
check_fail "researcher cannot write to sysadmin inbox" \
    su -s /bin/sh a-researcher -c "touch /srv/con/agents/sysadmin/inbox/evil.task"

echo ""
echo "--- 2c. Researcher cannot write to concierge inbox ---"
check_fail "researcher cannot write to concierge inbox" \
    su -s /bin/sh a-researcher -c "touch /srv/con/agents/concierge/inbox/evil.task"

echo ""
echo "--- 2d. Researcher cannot use sudo ---"
check_fail "researcher cannot use sudo" \
    su -s /bin/sh a-researcher -c "sudo systemctl stop con-concierge.path"

echo ""
echo "--- 2e. Researcher cannot read other agent workspaces ---"
check_fail "researcher cannot read sysadmin workspace" \
    su -s /bin/sh a-researcher -c "ls /srv/con/agents/sysadmin/workspace/"

echo ""
echo "--- 2f. Researcher cannot read other agent homes ---"
check_fail "researcher cannot read concierge home" \
    su -s /bin/sh a-researcher -c "ls /home/a-concierge/"

echo ""
echo "--- 2g. Researcher CAN write to own workspace ---"
check "researcher can write to own workspace" \
    su -s /bin/sh a-researcher -c "touch /srv/con/agents/researcher/workspace/.perm-test && rm /srv/con/agents/researcher/workspace/.perm-test"

echo ""
echo "--- 2h. Researcher CAN read own inbox ---"
check "researcher can read own inbox" \
    su -s /bin/sh a-researcher -c "ls /srv/con/agents/researcher/inbox/"

echo ""
echo "--- 2i. Concierge CAN write to researcher inbox (tasking ACL) ---"
check "concierge can write to researcher inbox" \
    su -s /bin/sh a-concierge -c "touch /srv/con/agents/researcher/inbox/.acl-test && rm /srv/con/agents/researcher/inbox/.acl-test"

finish
