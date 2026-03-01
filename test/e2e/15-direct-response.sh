#!/bin/bash
# test/e2e/15-direct-response.sh
# Verify concierge can answer simple questions directly without
# routing to other agents — it's an intelligent agent, not a dumb router.
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

echo "=== E2E Test 15: Direct Response (Not Everything Needs Routing) ==="

echo ""
echo "--- 15a. Simple factual question ---"
TASK_ID=$(drop_task concierge "What agents are currently available in this conspiracy?")
wait_for_response concierge "$TASK_ID" 90

RESPONSE=$(read_response concierge "$TASK_ID")
check "concierge responded" test -n "$RESPONSE"

if [ -n "$RESPONSE" ]; then
    # Concierge should check ls /srv/con/agents/ and answer directly
    check "mentions concierge" sh -c "echo '$RESPONSE' | grep -qi 'concierge'"
    check "mentions sysadmin" sh -c "echo '$RESPONSE' | grep -qi 'sysadmin'"
fi

echo ""
echo "--- 15b. General knowledge question (no routing needed) ---"
TASK_ID2=$(drop_task concierge "Explain in one sentence what a detective contract is in this system.")
wait_for_response concierge "$TASK_ID2" 90

RESPONSE2=$(read_response concierge "$TASK_ID2")
check "concierge responded to knowledge question" test -n "$RESPONSE2"

if [ -n "$RESPONSE2" ]; then
    # Should answer from its own context (AGENTS.md mentions contracts)
    check "explains detective contracts" \
        sh -c "echo '$RESPONSE2' | grep -qiE 'contract|detect|monitor|check|verif|health'"
fi

echo ""
echo "--- 15c. Request that clearly routes to sysadmin ---"
TASK_ID3=$(drop_task concierge "Commission a new agent called 'researcher' with read-only access to /srv/con/artifacts/.")
wait_for_response concierge "$TASK_ID3" 120

RESPONSE3=$(read_response concierge "$TASK_ID3")
check "concierge responded to commission request" test -n "$RESPONSE3"

if [ -n "$RESPONSE3" ]; then
    # This should be routed to sysadmin — clear system operation
    check "routes to sysadmin" \
        sh -c "echo '$RESPONSE3' | grep -qiE 'sysadmin|routed|commission|provision'"
fi

# Verify a task actually landed in sysadmin inbox
sleep 5
SYSADMIN_HAS_TASK=false
for f in /srv/con/agents/sysadmin/inbox/*.task; do
    [ -f "$f" ] || continue
    if grep -qi "researcher" "$f" 2>/dev/null; then
        SYSADMIN_HAS_TASK=true
        break
    fi
done
check "sysadmin received commissioning task" $SYSADMIN_HAS_TASK

finish
