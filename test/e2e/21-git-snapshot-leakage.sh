#!/bin/bash
# test/e2e/21-git-snapshot-leakage.sh
# Challenge: git add -A captures everything not in .gitignore.
# Can secrets leak into git history? Can agents read that history?
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

echo "=== E2E Test 21: Git Snapshot Secret Leakage ==="

echo ""
echo "--- 21a. Verify .gitignore covers sensitive paths ---"
GITIGNORE="/srv/con/.gitignore"
check ".gitignore exists" test -f "$GITIGNORE"

if [ -f "$GITIGNORE" ]; then
    check "workspaces excluded" grep -q "agents/\*/workspace/" "$GITIGNORE"
fi

echo ""
echo "--- 21b. Check what IS tracked by git ---"
# List all tracked files to see if anything sensitive is captured
TRACKED=$(git -C /srv/con ls-files 2>/dev/null || echo "")
if [ -n "$TRACKED" ]; then
    # Should NOT contain env files, private keys, or API keys
    check "no .env files tracked" \
        sh -c "! echo '$TRACKED' | grep -qE '\.env$'"
    check "no .pem files tracked" \
        sh -c "! echo '$TRACKED' | grep -qE '\.pem$'"
    check "no key files tracked" \
        sh -c "! echo '$TRACKED' | grep -qE 'private.*key|secret|credential'"
fi

echo ""
echo "--- 21c. Simulate secret written to tracked path ---"
# Write a fake secret to artifacts (tracked path)
SECRET_FILE="/srv/con/artifacts/test-secret.txt"
echo "FAKE_API_KEY=sk-test-12345-leakage-check" > "$SECRET_FILE"

# Trigger a git commit (simulates what happens after agent run)
git -C /srv/con add -A 2>/dev/null
git -C /srv/con commit -m "test: secret leakage check" --allow-empty 2>/dev/null || true

# Check if secret is in the commit
LEAKED=$(git -C /srv/con show HEAD -- artifacts/test-secret.txt 2>/dev/null || echo "")
if echo "$LEAKED" | grep -q "sk-test-12345"; then
    echo "  WARNING: Secret leaked into git history"
    check "secret leaked to git history (known gap — .gitignore incomplete)" false
else
    check "secret not in git history" true
fi

# Clean up
rm -f "$SECRET_FILE"
git -C /srv/con add -A 2>/dev/null
git -C /srv/con commit -m "test: cleanup secret leakage check" 2>/dev/null || true

echo ""
echo "--- 21d. Verify task content is NOT in git commits ---"
# Task files live in inbox (processed/) which SHOULD be tracked
# This means task content ends up in git history — assess if acceptable
INBOX_TRACKED=$(git -C /srv/con ls-files agents/*/processed/ 2>/dev/null | head -5)
if [ -n "$INBOX_TRACKED" ]; then
    echo "  INFO: Processed task files ARE tracked in git history"
    echo "  INFO: Task content (user requests) persists in git log forever"
fi
# Outbox responses
OUTBOX_TRACKED=$(git -C /srv/con ls-files agents/*/outbox/ 2>/dev/null | head -5)
if [ -n "$OUTBOX_TRACKED" ]; then
    echo "  INFO: Outbox response files ARE tracked in git history"
    echo "  INFO: Agent responses persist in git log forever"
fi

finish
