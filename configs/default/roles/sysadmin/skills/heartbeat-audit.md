# Heartbeat Audit

The heartbeat is the system's self-healing mechanism. It runs detective
contracts on a systemd timer and verifies that the system matches its
intended state. When it detects drift, it escalates and remediates.

The human operator trusts the system because the heartbeat is always running.

## How it works

`con-healthcheck` runs as a systemd timer (default: every 60 seconds).
It iterates all YAML files in `/srv/con/contracts/`, parses checks,
executes them, and applies failure actions. No LLM involved — pure
structured evaluation.

```
systemd timer fires
  → con-healthcheck reads /srv/con/contracts/*.yaml
  → for each detective contract:
      run check command/script
      if PASS → log, continue
      if FAIL → apply on_fail action, escalate, log
  → write summary to /srv/con/logs/audit/contracts.log
```

## Verifying the heartbeat is running

```bash
# Check timer status
systemctl status con-healthcheck.timer

# See recent runs
journalctl -u con-healthcheck.service --since "1 hour ago"

# Check contract results
tail -20 /srv/con/logs/audit/contracts.log
```

If the heartbeat itself stops, systemd's watchdog detects it. A stopped
heartbeat is the most critical failure — the system cannot self-heal.

## Adding a new detective contract

1. Create a YAML file in `/srv/con/contracts/`:
   ```yaml
   id: CON-<NNN>
   description: <what the check verifies>
   type: detective
   frequency: 60s
   scope: system           # or agent:<name> or scope:<name>
   checks:
     - name: <check name>
       command:
         run: "<shell command that produces a value>"
         test: "[ $RESULT <condition> ]"
       on_fail:
         action: <action>
         escalate: <agent>
         message: "CON-<NNN> FAILED: <description>"
   ```

2. Test the check manually:
   ```bash
   # Run the check command
   RESULT=$(<shell command>)
   # Verify the test condition
   [ $RESULT <condition> ] && echo PASS || echo FAIL
   ```

3. The next heartbeat cycle picks it up automatically — no restart needed.

## Adding a new preventive contract to the registry

Preventive contracts are OS-enforced (the agent physically cannot violate
them), but they should still be registered for auditability:

```yaml
id: CON-<NNN>
description: <what is prevented>
type: preventive
mechanism: nftables          # or acl, sudoers, mcp-tools
agent: <agent>
enforcement: |
  <the exact command that enforces this>
```

This makes the full contract set queryable via `ls /srv/con/contracts/`.

## Failure actions

| Action | What happens |
|--------|-------------|
| `halt_agents` | Stop all agent systemd units |
| `halt_workers` | Stop worker-tier units only |
| `kill_session` | Kill the specific agent's active session |
| `quarantine` | Stop the agent, revoke inbox write ACLs, log |
| `alert` | Log and escalate only, no automated action |

Choose the least disruptive action that contains the problem.

## System contracts (always present)

These ship with every ConspiracyOS instance:

| ID | Check | Frequency | Action |
|----|-------|-----------|--------|
| `CON-SYS-001` | Disk free >= threshold | 60s | halt_agents → sysadmin |
| `CON-SYS-002` | Memory free >= threshold | 60s | halt_agents → sysadmin |
| `CON-SYS-003` | Load average <= factor × cores | 60s | halt_workers → sysadmin |
| `CON-SYS-004` | Agent session duration <= max | 60s | kill_session → log |
| `CON-SYS-005` | Audit log writable | 60s | halt_all → sysadmin |

Thresholds are defined in `[contracts.system]` in the outer config.

## Responding to a heartbeat escalation

When the heartbeat escalates to you:

1. Read the failure message — it includes the CON-ID and details
2. Check the contract YAML to understand what failed
3. Investigate the root cause (logs, filesystem state, network)
4. Remediate the issue
5. Verify the next heartbeat cycle passes
6. If the contract needs updating (false positive, threshold change),
   update the YAML — do NOT disable the contract without CSO approval
