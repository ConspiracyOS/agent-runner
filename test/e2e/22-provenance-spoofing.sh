#!/bin/bash
# test/e2e/22-provenance-spoofing.sh
# Challenge: Trust is determined by stat() on the task file.
# Can an agent spoof provenance via symlinks, hardlinks, or rename tricks?
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

echo "=== E2E Test 22: Task Provenance Spoofing ==="

echo ""
echo "--- 22a. Symlink in inbox pointing to root-owned file ---"
# If an agent creates a symlink in its inbox pointing to a root-owned file,
# os.Stat() follows the symlink and sees root ownership → TrustVerified.
# This could allow an agent to self-send "verified" tasks.

# Create a root-owned task file outside the inbox
ROOT_TASK="/tmp/root-owned-task.task"
echo "This task should be treated as verified" > "$ROOT_TASK"
chmod 644 "$ROOT_TASK"
# /tmp file is root-owned since we're running as root

# Can the concierge user create a symlink in its own inbox?
RESULT=$(su -s /bin/sh a-concierge -c "ln -s $ROOT_TASK /srv/con/agents/concierge/inbox/symlink-spoof.task" 2>&1 || true)
if [ -f /srv/con/agents/concierge/inbox/symlink-spoof.task ]; then
    echo "  WARNING: Agent CAN create symlinks in own inbox"

    # Check: does stat() follow the symlink?
    LINK_OWNER=$(stat -c %U /srv/con/agents/concierge/inbox/symlink-spoof.task 2>/dev/null || echo "unknown")
    LINK_OWNER_L=$(stat -Lc %U /srv/con/agents/concierge/inbox/symlink-spoof.task 2>/dev/null || echo "unknown")
    echo "  stat() owner (follows link): $LINK_OWNER"
    echo "  lstat() owner (link itself): $LINK_OWNER_L"

    # stat() should show root (follows link), but the LINK itself is agent-owned
    # Runner uses os.Stat (not Lstat), so it would see root ownership = TrustVerified
    if [ "$LINK_OWNER" = "root" ]; then
        check "symlink spoofs provenance to root (known gap — needs Lstat)" false
    else
        check "provenance check resistant to symlinks" true
    fi

    rm -f /srv/con/agents/concierge/inbox/symlink-spoof.task
else
    check "agent cannot create symlinks in inbox (good)" true
fi
rm -f "$ROOT_TASK"

echo ""
echo "--- 22b. Hardlink to root-owned file ---"
# Hardlinks preserve inode ownership. Agent would need write access to inbox
# and the ability to create hardlinks to files owned by other users.
ROOT_TASK2="/srv/con/inbox/root-task-for-hardlink.task"
echo "Hardlink test task" > "$ROOT_TASK2"

RESULT2=$(su -s /bin/sh a-concierge -c "ln $ROOT_TASK2 /srv/con/agents/concierge/inbox/hardlink-spoof.task" 2>&1 || true)
if [ -f /srv/con/agents/concierge/inbox/hardlink-spoof.task ]; then
    echo "  WARNING: Agent CAN create hardlinks to root-owned files"
    check "hardlink spoofs provenance (gap)" false
    rm -f /srv/con/agents/concierge/inbox/hardlink-spoof.task
else
    check "agent cannot create hardlinks to root-owned files (good)" true
fi
rm -f "$ROOT_TASK2"

echo ""
echo "--- 22c. Agent self-tasks (writes to own inbox) ---"
# Can an agent drop a task into its own inbox? This creates a feedback loop.
RESULT3=$(su -s /bin/sh a-concierge -c "echo 'self-task loop' > /srv/con/agents/concierge/inbox/self-task.task" 2>&1 || true)
if [ -f /srv/con/agents/concierge/inbox/self-task.task ]; then
    echo "  INFO: Agent CAN write to own inbox (self-tasking possible)"
    SELF_OWNER=$(stat -c %U /srv/con/agents/concierge/inbox/self-task.task)
    check "self-task owned by agent (correctly unverified)" [ "$SELF_OWNER" = "a-concierge" ]
    rm -f /srv/con/agents/concierge/inbox/self-task.task
else
    check "agent cannot self-task (restricted inbox)" true
fi

echo ""
echo "--- 22d. rename() preserves ownership across directories ---"
# The design relies on rename() preserving file ownership for provenance.
# Verify this works as expected on the same filesystem.
TEST_TASK="/srv/con/inbox/rename-test-$(date +%s).task"
echo "rename provenance test" > "$TEST_TASK"
ORIGINAL_OWNER=$(stat -c %u "$TEST_TASK")

mv "$TEST_TASK" /srv/con/agents/concierge/inbox/ 2>/dev/null
MOVED_TASK="/srv/con/agents/concierge/inbox/$(basename $TEST_TASK)"
if [ -f "$MOVED_TASK" ]; then
    MOVED_OWNER=$(stat -c %u "$MOVED_TASK")
    check "rename preserves original owner UID" [ "$ORIGINAL_OWNER" = "$MOVED_OWNER" ]
    rm -f "$MOVED_TASK"
fi

finish
