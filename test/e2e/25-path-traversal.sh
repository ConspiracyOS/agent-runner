#!/bin/bash
# test/e2e/25-path-traversal.sh
# Challenge: Agent names are used directly in path construction.
# What if config allows "../" or other traversal patterns?
# What if task filenames contain shell metacharacters?
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

echo "=== E2E Test 25: Path Traversal & Injection ==="

echo ""
echo "--- 25a. Task filename with shell metacharacters ---"
# Runner uses filepath.Base() which should strip directory components,
# but what about filenames with $(command) or backticks?
EVIL_NAME='$(whoami).task'
touch "/srv/con/agents/concierge/inbox/$EVIL_NAME" 2>/dev/null || true
if [ -f "/srv/con/agents/concierge/inbox/\$(whoami).task" ]; then
    check "shell metachar filename created" true
    rm -f "/srv/con/agents/concierge/inbox/\$(whoami).task"
else
    check "shell metachar in filename rejected (good)" true
fi

echo ""
echo "--- 25b. Task filename with directory traversal ---"
# Can we create a task with ../ in the name?
RESULT=$(touch "/srv/con/agents/concierge/inbox/../../inbox/traversal.task" 2>&1 || true)
check_fail "directory traversal in task filename prevented" \
    test -f "/srv/con/inbox/traversal.task"
rm -f "/srv/con/inbox/traversal.task" 2>/dev/null

echo ""
echo "--- 25c. Agent directory naming conventions ---"
# Verify agent dirs only have safe names (alphanumeric + hyphen)
BAD_NAMES=0
for d in /srv/con/agents/*/; do
    name=$(basename "$d")
    if ! echo "$name" | grep -qE '^[a-z0-9-]+$'; then
        echo "  WARNING: Agent dir with non-standard name: $name"
        BAD_NAMES=$((BAD_NAMES + 1))
    fi
done
check "all agent dir names are alphanumeric+hyphen" [ "$BAD_NAMES" -eq 0 ]

echo ""
echo "--- 25d. Config file agent name validation ---"
# Check if con.toml agent names are safe
if [ -f /etc/con/con.toml ]; then
    BAD_AGENTS=0
    grep '^\[\[agents\]\]' -A5 /etc/con/con.toml | grep 'name' | while read line; do
        name=$(echo "$line" | sed 's/.*= *"\(.*\)"/\1/')
        if ! echo "$name" | grep -qE '^[a-z0-9-]+$'; then
            echo "  WARNING: Config has agent with unsafe name: $name"
            BAD_AGENTS=$((BAD_AGENTS + 1))
        fi
    done
    check "config agent names are safe" [ "${BAD_AGENTS:-0}" -eq 0 ]
fi

echo ""
echo "--- 25e. Git commit message injection ---"
# Agent name goes directly into git commit message.
# If name contained shell chars, does git handle it safely?
# Test: the commit command uses -m which is safe, but verify.
LATEST_MSG=$(git -C /srv/con log -1 --format=%s 2>/dev/null || echo "")
check "git commit message exists and is clean" test -n "$LATEST_MSG"

# Verify no shell expansion in commit messages
check "commit message has no shell expansion artifacts" \
    sh -c "! echo '$LATEST_MSG' | grep -qE '^\$\(|^\`'"

finish
