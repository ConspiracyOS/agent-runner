#!/bin/bash
# test/e2e/11-vague-request-clarification.sh
# Verify concierge asks for clarification on vague/ambiguous requests
# instead of blindly routing or hallucinating a target agent.
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

echo "=== E2E Test 11: Vague Request Clarification ==="

echo ""
echo "--- 11a. Vague request with no clear target ---"
TASK_ID=$(drop_task concierge "Can you help me with something?")
wait_for_response concierge "$TASK_ID" 90

RESPONSE=$(read_response concierge "$TASK_ID")
check "concierge responded" test -n "$RESPONSE"

# Concierge should ask for clarification, NOT route to sysadmin or make assumptions
if [ -n "$RESPONSE" ]; then
    check "response asks for clarification" \
        echo "$RESPONSE" | grep -qiE "clarif|what.*would|more.*detail|could you.*describe|what.*help|can you.*tell"
    # Should NOT have routed to anyone
    check "did not route blindly" \
        sh -c "! echo '$RESPONSE' | grep -qi 'routed to'"
fi

echo ""
echo "--- 11b. Ambiguous request between multiple agents ---"
TASK_ID2=$(drop_task concierge "I need to set up monitoring for something important")
wait_for_response concierge "$TASK_ID2" 90

RESPONSE2=$(read_response concierge "$TASK_ID2")
check "concierge responded to ambiguous request" test -n "$RESPONSE2"

# Should ask what to monitor, what systems, etc.
if [ -n "$RESPONSE2" ]; then
    check "asks about monitoring specifics" \
        echo "$RESPONSE2" | grep -qiE "what.*monitor|which.*system|what.*service|what.*important|describe"
fi

finish
