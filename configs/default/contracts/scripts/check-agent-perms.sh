#!/bin/sh
# CON-AGENT-001: Verify agent directory permissions and ownership.
# Exit 0 = all OK, exit 1 = violations found.
set -e

AGENTS_BASE="/srv/con/agents"
ERRORS=0

for agent_dir in "$AGENTS_BASE"/*/; do
    [ -d "$agent_dir" ] || continue
    name=$(basename "$agent_dir")
    user="a-$name"

    # Check agent user exists
    if ! id "$user" >/dev/null 2>&1; then
        echo "ERROR: user $user does not exist for agent $name"
        ERRORS=$((ERRORS + 1))
        continue
    fi

    # Check base dir: no group read/write, no other access.
    # ACLs may add execute (traverse) for named users, making stat show 710,
    # which is fine — only read (4) or write (2) in group/other is a violation.
    raw_mode=$(stat -c '%04a' "$agent_dir" 2>/dev/null)
    octal_mode=$((0$raw_mode))
    group_rw=$(( (octal_mode >> 3) & 6 ))  # bits 4+2 of group
    other_rw=$(( octal_mode & 6 ))          # bits 4+2 of other
    if [ "$group_rw" -ne 0 ] || [ "$other_rw" -ne 0 ]; then
        echo "ERROR: $agent_dir has mode $raw_mode (group/other has read or write access)"
        ERRORS=$((ERRORS + 1))
    fi

    # Check base dir ownership
    owner=$(stat -c '%U' "$agent_dir" 2>/dev/null)
    if [ "$owner" != "$user" ]; then
        echo "ERROR: $agent_dir owned by $owner (expected $user)"
        ERRORS=$((ERRORS + 1))
    fi

    # Check subdirs exist and have correct ownership
    for subdir in inbox outbox workspace processed; do
        sub="$agent_dir$subdir"
        if [ ! -d "$sub" ]; then
            echo "ERROR: $sub missing"
            ERRORS=$((ERRORS + 1))
            continue
        fi
        sub_owner=$(stat -c '%U' "$sub" 2>/dev/null)
        if [ "$sub_owner" != "$user" ]; then
            echo "ERROR: $sub owned by $sub_owner (expected $user)"
            ERRORS=$((ERRORS + 1))
        fi
    done

    # Check AGENTS.md exists in home dir
    home="/home/$user"
    if [ ! -f "$home/AGENTS.md" ]; then
        echo "ERROR: $home/AGENTS.md missing"
        ERRORS=$((ERRORS + 1))
    fi

    # Check path watcher is enabled
    if ! systemctl is-enabled "con-${name}.path" >/dev/null 2>&1; then
        echo "ERROR: con-${name}.path not enabled"
        ERRORS=$((ERRORS + 1))
    fi
done

# Check outer inbox watcher is enabled
if ! systemctl is-enabled "con-outer-inbox.path" >/dev/null 2>&1; then
    echo "ERROR: con-outer-inbox.path not enabled"
    ERRORS=$((ERRORS + 1))
fi

# Check outer inbox permissions (root:agents, 0770 — no sticky bit)
mode=$(stat -c '%a' /srv/con/inbox 2>/dev/null)
owner_group=$(stat -c '%U:%G' /srv/con/inbox 2>/dev/null)
if [ "$mode" != "770" ]; then
    echo "ERROR: /srv/con/inbox has mode $mode (expected 770)"
    ERRORS=$((ERRORS + 1))
fi
if [ "$owner_group" != "root:agents" ]; then
    echo "ERROR: /srv/con/inbox owned by $owner_group (expected root:agents)"
    ERRORS=$((ERRORS + 1))
fi

if [ "$ERRORS" -gt 0 ]; then
    echo "CON-AGENT-001: $ERRORS violation(s) found"
    exit 1
fi

exit 0
