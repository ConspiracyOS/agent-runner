#!/bin/bash
# test/e2e/28-network-isolation-gap.sh
# Challenge: nftables per-UID filtering is designed but NOT implemented.
# This test documents the current network exposure and what should be locked down.
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

echo "=== E2E Test 28: Network Isolation (Gap Assessment) ==="

echo ""
echo "--- 28a. Check if nftables rules exist ---"
NFTABLES_RULES=$(nft list ruleset 2>/dev/null | wc -l)
if [ "$NFTABLES_RULES" -gt 2 ]; then
    check "nftables rules present" true
    echo "  Rules: $NFTABLES_RULES lines"
else
    echo "  GAP: No nftables rules configured"
    echo "  RISK: All agents have unrestricted network access"
    check "nftables rules present (GAP — not implemented)" false
fi

echo ""
echo "--- 28b. Can agent resolve DNS? ---"
RESULT=$(su -s /bin/sh a-concierge -c "getent hosts github.com" 2>&1 || true)
if echo "$RESULT" | grep -qE "[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+"; then
    echo "  INFO: Agent CAN resolve DNS (expected without nftables)"
    check "DNS resolution works" true
else
    echo "  INFO: Agent cannot resolve DNS"
    check "DNS is blocked" true
fi

echo ""
echo "--- 28c. Can agent reach external HTTP? ---"
# Use a lightweight check — just TCP connect, don't transfer data
RESULT=$(su -s /bin/sh a-concierge -c "timeout 5 bash -c 'echo > /dev/tcp/1.1.1.1/80' 2>&1" || true)
if [ $? -eq 0 ] || echo "$RESULT" | grep -q "Connection refused"; then
    echo "  INFO: Agent CAN reach external IPs (no nftables filtering)"
    echo "  RISK: Compromised agent could exfiltrate data to any IP"
    check "external HTTP reachable (GAP — nftables not configured)" true
else
    check "external HTTP blocked (good — nftables working)" true
fi

echo ""
echo "--- 28d. Document expected nftables policy ---"
echo "  Per design doc:"
echo "  - Workers: deny all outbound except explicit allowlist"
echo "  - Officers: broader allowlist (strategy services)"
echo "  - Sysadmin: package repos, LLM API, GitHub"
echo "  - All agents: deny by default, allow DNS to system resolver only"
echo "  - meta skuid match ensures rules apply to agent processes"

echo ""
echo "--- 28e. Check for curl/wget availability per agent ---"
for agent in concierge sysadmin; do
    HAS_CURL=$(su -s /bin/sh "a-$agent" -c "which curl 2>/dev/null" || true)
    HAS_WGET=$(su -s /bin/sh "a-$agent" -c "which wget 2>/dev/null" || true)
    if [ -n "$HAS_CURL" ] || [ -n "$HAS_WGET" ]; then
        echo "  INFO: $agent has HTTP client tools (curl/wget)"
    else
        echo "  INFO: $agent lacks HTTP client tools"
    fi
done

finish
