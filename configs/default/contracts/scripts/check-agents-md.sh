#!/bin/sh
# CON-AGENT-002: Verify AGENTS.md is root-owned and read-only (0444).
# Linux permissions are the integrity contract — no hashing needed.
# Exit 0 = all OK, exit 1 = drift detected.
set -e

AGENTS_BASE="/srv/con/agents"
FAIL=0

for agent_dir in "$AGENTS_BASE"/*/; do
    [ -d "$agent_dir" ] || continue
    name=$(basename "$agent_dir")
    deployed="/home/a-$name/AGENTS.md"

    [ -f "$deployed" ] || continue

    owner=$(stat -c '%U' "$deployed" 2>/dev/null)
    group=$(stat -c '%G' "$deployed" 2>/dev/null)
    perms=$(stat -c '%a' "$deployed" 2>/dev/null)

    if [ "$owner" != "root" ] || [ "$group" != "root" ]; then
        echo "DRIFT: $name AGENTS.md owned by $owner:$group (expected root:root)"
        FAIL=1
    fi

    if [ "$perms" != "444" ]; then
        echo "DRIFT: $name AGENTS.md mode $perms (expected 444)"
        FAIL=1
    fi
done

exit $FAIL
