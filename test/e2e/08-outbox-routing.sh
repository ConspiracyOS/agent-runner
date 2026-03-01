#!/bin/bash
# test/e2e/08-outbox-routing.sh
# Verify that task responses land in outbox with correct ownership and format.
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

echo "=== E2E Test 8: Outbox Routing ==="

echo ""
echo "--- 8a. Drop task and wait for response ---"
TASK_ID=$(drop_task concierge "Respond with exactly: routing test ok")
wait_for_response concierge "$TASK_ID" 60
check "response file exists" read_response concierge "$TASK_ID"

echo ""
echo "--- 8b. Verify response file ownership ---"
RESPONSE_FILE=$(ls -t /srv/con/agents/concierge/outbox/*"${TASK_ID}"*.response 2>/dev/null | head -1)
check "response file found" test -n "$RESPONSE_FILE"

if [ -n "$RESPONSE_FILE" ]; then
    OWNER=$(stat -c %U "$RESPONSE_FILE")
    check "response owned by concierge user" [ "$OWNER" = "a-concierge" ]

    PERMS=$(stat -c %a "$RESPONSE_FILE")
    # UMask=0077 means agent-created files are 600 (secure default)
    check "response has secure permissions (600)" [ "$PERMS" = "600" ]
fi

echo ""
echo "--- 8c. Verify task moved to processed ---"
wait_for_processed concierge "$TASK_ID" 10
check "task in processed dir" test -f "/srv/con/agents/concierge/processed/${TASK_ID}.task"
check "task no longer in inbox" test ! -f "/srv/con/agents/concierge/inbox/${TASK_ID}.task"

echo ""
echo "--- 8d. Verify audit log entry ---"
TODAY=$(date +%Y-%m-%d)
AUDIT_FILE="/srv/con/logs/audit/${TODAY}.log"
if [ -f "$AUDIT_FILE" ]; then
    check "audit log mentions task" grep -q "$TASK_ID" "$AUDIT_FILE"
else
    echo "  INFO: No date-based audit log yet (ACL may restrict writes)"
    check "audit log for today exists (GAP)" false
fi

finish
