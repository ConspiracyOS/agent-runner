# Commissioning a new agent

Prerequisites: you must have received a commissioning request that is within standing policy.

## Choosing a Tier

The tier determines the agent's cost budget (which model runs) and its systemd hardening
level. Pick the lowest tier that can do the job:

| Tier | Model class | Hardening | Use when |
|------|------------|-----------|----------|
| `worker` | Haiku (cheap, fast) | Strictest: write only to own workspace, NoNewPrivileges, no cross-agent inbox write | Well-scoped tasks: code, fetch, transform. No delegation needed. |
| `operator` | Sonnet (balanced) | Write to own workspace + agent inboxes, artifacts, audit, policy, ledger | Needs to route work to other agents or produce shared artifacts. |
| `officer` | Opus (expensive, deep reasoning) | Same as operator | Ambiguous decisions, strategy, policy authoring. Use sparingly. |

**The `sysadmin` role is special** — agents with this role get broad write access
(config, systemd, sudoers) regardless of tier. Only one sysadmin should exist.

Tier does NOT grant authority — authority comes from roles and ACLs. A worker with
the right ACLs can write to an inbox; an officer without them cannot. Tier controls
cost and default filesystem isolation.

When in doubt, choose `worker`. The agent can be upgraded later by editing con.toml
and re-running `con bootstrap`.

## Steps

0. Pre-flight: verify you have the capabilities needed to commission:
   ```
   test -w /srv/con/contracts/ && echo "contracts: ok" || echo "contracts: FAIL"
   sudo -n useradd -D >/dev/null 2>&1 && echo "useradd: ok" || echo "useradd: FAIL"
   sudo -n install -d /srv/con/agents/.preflight-test >/dev/null 2>&1 \
     && echo "install: ok" || echo "install: FAIL"
   sudo rm -rf /srv/con/agents/.preflight-test 2>/dev/null
   ```
   If any pre-flight check fails, STOP and escalate — do not attempt partial commissioning.

1. Verify the agent name is unique: `id a-<name>` should fail

2. Create the Linux user:
   ```
   sudo useradd -r -m -d /home/a-<name> -s /bin/bash -g agents -G <tier-group> a-<name>
   ```
   Tier groups: `officers` for officer tier, `operators` for operator tier, `workers` for worker tier.

   NOTE: Do NOT create or chmod the home directory manually. Your service runs with
   ProtectHome=tmpfs — directories created under /home/ will vanish when your service
   exits. The `con bootstrap` step below handles home directory creation in a persistent
   context.

3. Create directories (each with correct ownership):
   ```
   sudo install -d -o a-<name> -g agents -m 700 /srv/con/agents/<name>
   sudo install -d -o a-<name> -g agents -m 700 /srv/con/agents/<name>/inbox
   sudo install -d -o a-<name> -g agents -m 700 /srv/con/agents/<name>/outbox
   sudo install -d -o a-<name> -g agents -m 700 /srv/con/agents/<name>/workspace
   sudo install -d -o a-<name> -g agents -m 700 /srv/con/agents/<name>/workspace/sessions
   sudo install -d -o a-<name> -g agents -m 700 /srv/con/agents/<name>/workspace/skills
   sudo install -d -o a-<name> -g agents -m 700 /srv/con/agents/<name>/sessions
   sudo install -d -o a-<name> -g agents -m 700 /srv/con/agents/<name>/processed
   ```

4. Set ACLs — concierge must be able to task the new agent:
   ```
   sudo setfacl -m u:a-concierge:x /srv/con/agents/<name>/
   sudo setfacl -m u:a-concierge:rwx /srv/con/agents/<name>/inbox/
   ```
   The traverse ACL (`:x`) on the base dir lets concierge reach the inbox through the 700 parent.
   Add other tasking ACLs as specified in the commissioning request.

5. Network isolation (if the agent needs restricted network access):
   ```
   sudo tee /etc/nftables.d/con-<name>.nft << 'EOF'
   table inet filter_<name> {
       chain output_<name> {
           type filter hook output priority 0; policy accept;
           meta skuid != a-<name> accept
           # Minimum viable: DNS + loopback
           oif "lo" accept
           udp dport 53 accept
           tcp dport 53 accept
           # Service-specific HTTPS (add destinations as needed)
           tcp dport 443 accept
           # Drop everything else for this user
           drop
       }
   }
   EOF
   sudo nft -f /etc/nftables.d/con-<name>.nft
   ```

   MINIMUM REQUIREMENTS — never omit these:
   - `oif "lo" accept` — loopback (agent talks to local services)
   - `udp dport 53 accept` + `tcp dport 53 accept` — DNS resolution
   - `tcp dport 443 accept` — HTTPS (needed for LLM API calls and most services)

   For tighter lockdown, replace `tcp dport 443 accept` with specific IP ranges.
   But ALWAYS keep DNS rules — without them, no hostname resolves and all network
   operations fail silently.

6. Update the outer config (`/etc/con/con.toml`) — append the agent entry:
   ```
   cat >> /etc/con/con.toml << EOF

   [[agents]]
   name = "<name>"
   tier = "<tier>"
   mode = "on-demand"
   roles = [<roles>]
   instructions = "<one-line purpose>"
   EOF
   ```
   This is required — `con run` resolves agents from this file. Without it, the
   agent's path watcher will trigger but the run will fail with "agent not found".

7. Write agent config to inner config:
   ```
   Write to /srv/con/config/agents/<name>.toml with the agent's configuration
   (name, tier, mode, roles, instructions, etc.)
   ```

8. Run bootstrap to generate hardened systemd units and assemble AGENTS.md:
   ```
   con bootstrap
   ```
   Bootstrap reads `/etc/con/con.toml`, generates service+path units with
   tier-appropriate hardening (ProtectHome, PrivateTmp, UMask, ReadWritePaths),
   and assembles AGENTS.md from layers. Do NOT write units manually — bootstrap
   is the single source of truth for systemd units.

   Verify:
   ```
   cat /etc/systemd/system/con-<name>.service | grep ProtectHome  # should show tmpfs
   ls -la /home/a-<name>/AGENTS.md                                # should exist
   ```

9. Reload systemd and enable the path watcher:
   ```
   sudo systemctl daemon-reload
   sudo systemctl enable --now con-<name>.path
   ```

10. Log the commissioning to the audit log at `/srv/con/logs/audit/`

11. Post-commission verification — confirm the agent is correctly set up:
    ```
    id a-<name>                                              # user exists
    systemctl is-enabled con-<name>.path                     # watcher enabled
    ls -la /srv/con/agents/<name>/inbox/                     # inbox exists with correct ownership
    getfacl /srv/con/agents/<name>/inbox/ | grep concierge   # concierge ACL set
    cat /etc/con/con.toml | grep <name>                      # agent in outer config
    ls -la /home/a-<name>/AGENTS.md                          # AGENTS.md assembled
    ```
    If any verification fails, the agent is not fully commissioned — investigate before declaring success.
