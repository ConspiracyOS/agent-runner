#!/bin/bash
# test/e2e/24-contract-completeness.sh
# Challenge: Detective contracts only check what they're configured to check.
# What important invariants are NOT covered by contracts?
# This test documents the gaps — future contracts should close them.
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

echo "=== E2E Test 24: Contract Completeness Audit ==="

echo ""
echo "--- 24a. Inventory existing contracts ---"
CONTRACT_COUNT=$(ls /srv/con/contracts/*.yaml 2>/dev/null | wc -l)
check "contracts exist" [ "$CONTRACT_COUNT" -gt 0 ]
echo "  Found $CONTRACT_COUNT contracts"

for f in /srv/con/contracts/*.yaml; do
    ID=$(grep "^id:" "$f" | head -1 | awk '{print $2}')
    DESC=$(grep "^description:" "$f" | head -1 | sed 's/description: //')
    echo "  $ID: $DESC"
done

echo ""
echo "--- 24b. Check: AGENTS.md integrity monitored? ---"
# A compromised agent could rewrite its AGENTS.md. Is there a contract for this?
HAS_AGENTSMD_CHECK=false
for f in /srv/con/contracts/*.yaml; do
    if grep -q "AGENTS.md\|agents.*md\|instruction.*integrit" "$f" 2>/dev/null; then
        HAS_AGENTSMD_CHECK=true
        break
    fi
done
if $HAS_AGENTSMD_CHECK; then
    check "AGENTS.md integrity contract exists" true
else
    echo "  GAP: No contract monitors AGENTS.md integrity"
    echo "  RISK: Agent can rewrite own instructions without detection"
    check "AGENTS.md integrity contract exists (GAP)" false
fi

echo ""
echo "--- 24c. Check: skill file integrity monitored? ---"
HAS_SKILLS_CHECK=false
for f in /srv/con/contracts/*.yaml; do
    if grep -q "skill\|workspace/skills" "$f" 2>/dev/null; then
        HAS_SKILLS_CHECK=true
        break
    fi
done
if $HAS_SKILLS_CHECK; then
    check "skill integrity contract exists" true
else
    echo "  GAP: No contract monitors skill file integrity"
    echo "  RISK: Agent can inject malicious skills without detection"
    check "skill integrity contract exists (GAP)" false
fi

echo ""
echo "--- 24d. Check: sudoers drift monitored? ---"
HAS_SUDOERS_CHECK=false
for f in /srv/con/contracts/*.yaml; do
    if grep -q "sudoers\|sudo" "$f" 2>/dev/null; then
        HAS_SUDOERS_CHECK=true
        break
    fi
done
if $HAS_SUDOERS_CHECK; then
    check "sudoers policy drift contract exists" true
else
    echo "  GAP: No contract monitors sudoers policy"
    echo "  RISK: Sysadmin could modify sudoers and grant self more access"
    check "sudoers policy drift contract exists (GAP)" false
fi

echo ""
echo "--- 24e. Check: ACL correctness monitored? ---"
# CON-AGENT-001 checks agent dir permissions, but does it check ACLs?
HAS_ACL_CHECK=false
for f in /srv/con/contracts/*.yaml; do
    if grep -q "getfacl\|acl\|setfacl" "$f" 2>/dev/null; then
        HAS_ACL_CHECK=true
        break
    fi
done
if $HAS_ACL_CHECK; then
    check "ACL correctness contract exists" true
else
    echo "  GAP: No contract verifies ACL correctness"
    echo "  RISK: ACL drift could silently break cross-agent tasking"
    check "ACL correctness contract exists (GAP)" false
fi

echo ""
echo "--- 24f. Check: network egress monitored? ---"
HAS_NETWORK_CHECK=false
for f in /srv/con/contracts/*.yaml; do
    if grep -q "nftables\|iptables\|network\|egress\|firewall" "$f" 2>/dev/null; then
        HAS_NETWORK_CHECK=true
        break
    fi
done
if $HAS_NETWORK_CHECK; then
    check "network egress contract exists" true
else
    echo "  GAP: No contract monitors network egress rules"
    echo "  RISK: nftables not yet implemented; all agents have unrestricted network"
    check "network egress contract exists (GAP)" false
fi

echo ""
echo "--- 24g. Check: git snapshot integrity monitored? ---"
HAS_GIT_CHECK=false
for f in /srv/con/contracts/*.yaml; do
    if grep -q "git\|snapshot\|version.*control" "$f" 2>/dev/null; then
        HAS_GIT_CHECK=true
        break
    fi
done
if $HAS_GIT_CHECK; then
    check "git snapshot integrity contract exists" true
else
    echo "  GAP: No contract monitors /srv/con/ git repo health"
    check "git snapshot integrity contract exists (GAP)" false
fi

echo ""
echo "--- Summary of contract coverage ---"
echo "  Covered: disk, memory, load, sessions, audit log, env file, agent dir perms"
echo "  Gaps: AGENTS.md integrity, skill files, sudoers drift, ACLs, network, git"

finish
