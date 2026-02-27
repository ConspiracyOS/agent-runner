# Commissioning a new agent

Prerequisites: you must have received a commissioning request that is within standing policy.

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
   sudo chmod 700 /home/a-<name>
   ```
   Tier groups: `officers` for officer tier, `operators` for operator tier, `workers` for worker tier.
   The `chmod 700` ensures no other agent can read the home directory.

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

5. Write the systemd service unit (runs the agent when inbox changes):
   ```
   sudo tee /etc/systemd/system/con-<name>.service << 'EOF'
   [Unit]
   Description=ConspiracyOS agent: <name>
   After=network.target

   [Service]
   Type=oneshot
   User=a-<name>
   Group=agents
   ExecStart=/usr/local/bin/con run <name>
   WorkingDirectory=/srv/con/agents/<name>/workspace
   Environment=HOME=/home/a-<name>
   EnvironmentFile=-/etc/con/env

   [Install]
   WantedBy=multi-user.target
   EOF
   ```

6. Write the systemd path unit (watches inbox for new tasks):
   ```
   sudo tee /etc/systemd/system/con-<name>.path << 'EOF'
   [Unit]
   Description=ConspiracyOS inbox watcher: <name>

   [Path]
   PathChanged=/srv/con/agents/<name>/inbox
   MakeDirectory=yes

   [Install]
   WantedBy=multi-user.target
   EOF
   ```

7. Reload systemd and enable the path watcher:
   ```
   sudo systemctl daemon-reload
   sudo systemctl enable --now con-<name>.path
   ```

8. Write agent config to inner config:
   ```
   Write to /srv/con/config/agents/<name>.toml with the agent's configuration
   (name, tier, mode, roles, instructions, etc.)
   ```

9. Assemble the agent's AGENTS.md:
   ```
   con bootstrap
   ```
   Bootstrap assembles AGENTS.md from multiple layers (base + groups + roles +
   agent + inline instructions) and writes it to `/home/a-<name>/AGENTS.md` with
   correct ownership. Do NOT manually copy a single AGENTS.md file — the assembled
   file includes the base orientation, role layers, and inline config that a raw
   copy would miss.

   Verify: `ls -la /home/a-<name>/AGENTS.md` — should be owned by `a-<name>:agents`.

10. Log the commissioning to the audit log at `/srv/con/logs/audit/`

11. Post-commission verification — confirm the agent is correctly set up:
    ```
    id a-<name>                                              # user exists
    systemctl is-enabled con-<name>.path                     # watcher enabled
    ls -la /srv/con/agents/<name>/inbox/                     # inbox exists with correct ownership
    getfacl /srv/con/agents/<name>/inbox/ | grep concierge   # concierge ACL set
    ```
    If any verification fails, the agent is not fully commissioned — investigate before declaring success.
