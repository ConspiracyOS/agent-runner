#!/bin/bash
# test/e2e/09-skill-injection.sh
# Verify that skills are injected into agent prompts and influence behavior.
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

echo "=== E2E Test 9: Skill Injection ==="

echo ""
echo "--- 9a. Verify sysadmin has skills in workspace ---"
SKILLS_DIR="/srv/con/agents/sysadmin/workspace/skills"
check "sysadmin skills dir exists" test -d "$SKILLS_DIR"
SKILL_COUNT=$(ls "$SKILLS_DIR"/*.md 2>/dev/null | wc -l)
check "sysadmin has at least one skill" [ "$SKILL_COUNT" -gt 0 ]

echo ""
echo "--- 9b. Verify skills contain actionable content ---"
# Skills should have structured instructions, not just prose
if ls "$SKILLS_DIR"/*.md >/dev/null 2>&1; then
    check "skills contain step markers" grep -rlq -E "(Step [0-9]|## )" "$SKILLS_DIR"/*.md
fi

echo ""
echo "--- 9c. Verify concierge AGENTS.md has base content ---"
check "AGENTS.md references ConspiracyOS" grep -q "ConspiracyOS" /home/a-concierge/AGENTS.md
check "AGENTS.md references agent role" grep -q "concierge" /home/a-concierge/AGENTS.md

echo ""
echo "--- 9d. Task referencing skill knowledge ---"
# Ask sysadmin about its own capabilities — answer should reflect injected skills
TASK_ID=$(drop_task sysadmin "List the skill files you have available. Just list their filenames, nothing else.")
wait_for_response sysadmin "$TASK_ID" 90

RESPONSE=$(read_response sysadmin "$TASK_ID")
check "sysadmin responded" test -n "$RESPONSE"

# The response should mention at least one .md skill file
if [ -n "$RESPONSE" ]; then
    check "response mentions skill files" sh -c "echo '$RESPONSE' | grep -qiE '\.md|commission|create'"
fi

finish
