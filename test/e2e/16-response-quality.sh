#!/bin/bash
# test/e2e/16-response-quality.sh
# Verify agents produce structured, useful responses — not empty,
# not error dumps, not hallucinated nonsense.
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

echo "=== E2E Test 16: Response Quality ==="

echo ""
echo "--- 16a. Response is non-empty and substantive ---"
TASK_ID=$(drop_task concierge "List all the directories under /srv/con/ and describe what each one is for.")
wait_for_response concierge "$TASK_ID" 90

RESPONSE=$(read_response concierge "$TASK_ID")
check "response is non-empty" test -n "$RESPONSE"

if [ -n "$RESPONSE" ]; then
    # Response should be at least a few lines, not just "ok" or an error
    LINE_COUNT=$(echo "$RESPONSE" | wc -l)
    check "response has substance (>3 lines)" [ "$LINE_COUNT" -gt 3 ]

    # Should mention key directories
    check "mentions agents directory" echo "$RESPONSE" | grep -qi "agents"
    check "mentions inbox" echo "$RESPONSE" | grep -qi "inbox"

    # Should NOT contain raw error traces
    check "no panic or stack trace" \
        sh -c "! echo '$RESPONSE' | grep -qiE 'panic|goroutine|stack trace|segfault'"
fi

echo ""
echo "--- 16b. Response format matches AGENTS.md spec ---"
# Concierge AGENTS.md says: after routing, write "Routed to <agent>: <brief summary>"
TASK_ID2=$(drop_task concierge "Please ask sysadmin to check if all systemd units are healthy.")
wait_for_response concierge "$TASK_ID2" 90

RESPONSE2=$(read_response concierge "$TASK_ID2")
check "concierge responded to routing request" test -n "$RESPONSE2"

if [ -n "$RESPONSE2" ]; then
    # If it routed, response should follow the format
    if echo "$RESPONSE2" | grep -qi "routed"; then
        check "routing response follows format" \
            echo "$RESPONSE2" | grep -qiE "routed to.*sysadmin"
    fi
fi

echo ""
echo "--- 16c. Sysadmin response is actionable ---"
TASK_ID3=$(drop_task sysadmin "List all commissioned agents and their systemd unit states.")
wait_for_response sysadmin "$TASK_ID3" 120

RESPONSE3=$(read_response sysadmin "$TASK_ID3")
check "sysadmin responded" test -n "$RESPONSE3"

if [ -n "$RESPONSE3" ]; then
    LINE_COUNT3=$(echo "$RESPONSE3" | wc -l)
    check "sysadmin response has substance (>2 lines)" [ "$LINE_COUNT3" -gt 2 ]

    # Should contain actual system information, not just acknowledgment
    check "contains agent or systemd information" \
        echo "$RESPONSE3" | grep -qiE "concierge|sysadmin|systemd|active|enabled|service|unit"
fi

finish
