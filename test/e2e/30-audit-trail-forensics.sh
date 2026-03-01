#!/bin/bash
# test/e2e/30-audit-trail-forensics.sh
# Challenge: If something goes wrong, can we reconstruct what happened?
# Test that the audit trail, ledger, git history, and outbox provide
# enough forensic evidence to understand agent behavior.
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

echo "=== E2E Test 30: Audit Trail Forensics ==="

echo ""
echo "--- 30a. Drop a known task and verify full audit chain ---"
TASK_ID="forensic-$(date +%s)"
drop_task concierge "Respond with exactly: forensic test marker 42" "$TASK_ID"
wait_for_response concierge "$TASK_ID" 90

RESPONSE=$(read_response concierge "$TASK_ID")
check "concierge produced response" test -n "$RESPONSE"

echo ""
echo "--- 30b. Verify audit log records the run ---"
TODAY=$(date +%Y-%m-%d)
AUDIT_FILE="/srv/con/logs/audit/${TODAY}.log"
if [ -f "$AUDIT_FILE" ]; then
    check "audit log entry for task" grep -q "$TASK_ID" "$AUDIT_FILE"
    check "audit log shows trust level" sh -c "grep '$TASK_ID' '$AUDIT_FILE' | grep -q 'trust:'"
    check "audit log shows agent name" sh -c "grep '$TASK_ID' '$AUDIT_FILE' | grep -q 'concierge'"
else
    echo "  GAP: No audit log for concierge — ACL on /srv/con/logs/audit/ only allows a-sysadmin"
    echo "  FIX: Add ACL for agents group or per-agent audit write ACL"
    check "audit log file exists (GAP — ACL blocks concierge writes)" false
fi

echo ""
echo "--- 30c. Verify ledger records the run ---"
LEDGER_FILE="/srv/con/ledger/${TODAY}.tsv"
if [ -f "$LEDGER_FILE" ]; then
    check "ledger entry for task" grep -q "$TASK_ID" "$LEDGER_FILE"
    check "ledger shows model" sh -c "grep '$TASK_ID' '$LEDGER_FILE' | grep -qE 'sonnet|opus|haiku|gpt|claude|deepseek|gemini'"
    check "ledger shows timestamp" sh -c "grep '$TASK_ID' '$LEDGER_FILE' | grep -qE '^[0-9]{4}-'"
else
    echo "  INFO: No ledger file (ledger may not be enabled)"
    check "ledger file exists" false
fi

echo ""
echo "--- 30d. Verify git history captures the state change ---"
GIT_LOG=$(git -C /srv/con log --oneline -5 2>/dev/null || echo "")
if [ -n "$GIT_LOG" ]; then
    check "git log has recent entries" test -n "$GIT_LOG"
    check "git log mentions concierge" sh -c "echo '$GIT_LOG' | grep -q 'concierge'"
fi

echo ""
echo "--- 30e. Verify task is in processed directory ---"
check "task moved to processed" \
    test -f "/srv/con/agents/concierge/processed/${TASK_ID}.task"

echo ""
echo "--- 30f. Verify response file has correct metadata ---"
RESPONSE_FILE=$(ls /srv/con/agents/concierge/outbox/*"${TASK_ID}"*.response 2>/dev/null | head -1)
if [ -n "$RESPONSE_FILE" ]; then
    # File timestamp should be close to task processing time
    FILE_TIME=$(stat -c %Y "$RESPONSE_FILE")
    NOW=$(date +%s)
    AGE=$((NOW - FILE_TIME))
    check "response file is recent (<120s old)" [ "$AGE" -lt 120 ]

    # File owner should be the agent
    OWNER=$(stat -c %U "$RESPONSE_FILE")
    check "response owned by agent" [ "$OWNER" = "a-concierge" ]
else
    check "response file found" false
fi

echo ""
echo "--- 30g. Reconstruct timeline from available evidence ---"
echo "  Task ID: $TASK_ID"
echo "  Task file: /srv/con/agents/concierge/processed/${TASK_ID}.task"
echo "  Response: $RESPONSE_FILE"

if [ -f "$AUDIT_FILE" ]; then
    echo "  Audit entry: $(grep "$TASK_ID" "$AUDIT_FILE" | tail -1)"
fi
if [ -f "$LEDGER_FILE" ]; then
    echo "  Ledger entry: $(grep "$TASK_ID" "$LEDGER_FILE" | tail -1)"
fi
echo "  Git log: $(git -C /srv/con log --oneline -1 2>/dev/null)"
echo ""
echo "  Assessment: Can we fully reconstruct what happened? (check above)"

echo ""
echo "--- 30h. Verify audit log is append-only (not truncatable by agents) ---"
# Audit log should be writable but not truncatable by agent users
if [ -f "$AUDIT_FILE" ]; then
    AUDIT_OWNER=$(stat -c %U "$AUDIT_FILE")
    AUDIT_PERMS=$(stat -c %a "$AUDIT_FILE")
    echo "  Audit log owner: $AUDIT_OWNER (perms: $AUDIT_PERMS)"

    # Can an agent truncate the audit log?
    RESULT=$(su -s /bin/sh a-concierge -c "echo '' > $AUDIT_FILE" 2>&1 || true)
    AUDIT_SIZE=$(stat -c %s "$AUDIT_FILE")
    if [ "$AUDIT_SIZE" -gt 10 ]; then
        check "agent cannot truncate audit log" true
    else
        echo "  WARNING: Agent CAN truncate audit log"
        check "audit log tamper-resistant (GAP)" false
    fi
fi

finish
