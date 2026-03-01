# Writing Contracts

A contract is a programmatic enforcement or audit of a policy. If it has a
CON-ID, it has a check. If it has no check, it is not a contract.

## Two types

| Type | When | How | Example |
|------|------|-----|---------|
| **Preventive** | Blocks violation before it occurs | OS enforcement | nftables, ACLs, sudoers |
| **Detective** | Detects violation after the fact | Heartbeat check | Cron script, healthcheck |

**Prefer preventive.** If you can make a violation physically impossible,
do that instead of detecting it after the fact.

## Least-privilege principle

Every capability is an explicit grant. Never use generic permissions.

**Wrong:** Agent gets full network access, instruction says "only use api.example.com"
**Right:** nftables rule allows api.example.com:443 only, drops everything else

**Wrong:** Agent gets read/write to all agent inboxes
**Right:** ACL grants write to specific target inboxes only

**Wrong:** One agent handles read + process + send
**Right:** Three agents, each with one capability, connected by inboxes

## Decomposing workflows into isolated roles

When a workflow touches sensitive data or untrusted input, decompose it:

1. List every capability the workflow needs (read X, write Y, reach Z)
2. Group capabilities by trust boundary — can any single compromise cause harm?
3. If yes: split into separate agents where each has only its piece
4. Connect them via inboxes (the only inter-agent channel)

### Worked example: email support monitoring

**Requirement:** Watch an email inbox for support tickets, draft replies,
send approved replies.

**Naive (dangerous):** One agent with IMAP read + SMTP send + all context.
A malicious email can trick it into exfiltrating data via SMTP.

**Decomposed:**

```
email-watcher (Worker)
  ├── Can: read IMAP inbox (imap.provider.com:993)
  ├── Cannot: send email, reach any other host
  ├── Output: writes parsed tickets to own outbox
  └── nftables: allow imap.provider.com:993, drop all else

reply-drafter (Worker)
  ├── Can: read email-watcher's outbox
  ├── Cannot: read raw inbox, send email, reach network
  ├── Output: writes draft replies to review queue
  └── nftables: deny all outbound

reply-sender (Worker)
  ├── Can: read approved-replies queue, send via SMTP
  ├── Cannot: read inbox, read drafts, reach any other host
  ├── Output: sends email, logs to own outbox
  └── nftables: allow smtp.provider.com:587, drop all else
```

A compromised email-watcher cannot send emails.
A compromised reply-sender cannot read the inbox.
No single agent compromise leaks data AND exfiltrates it.

## Writing a preventive contract

1. Identify the capability restriction
2. Choose the enforcement mechanism:
   - **Filesystem access** → ACLs (`setfacl`)
   - **Network egress** → nftables (`meta skuid`)
   - **Command execution** → sudoers allow-list
   - **Tool access** → PicoClaw/MCP tool config
   - **Inbox tasking** → ACLs on inbox directories
3. Apply the enforcement:
   ```bash
   # CON-<NNN>: <agent> may only reach <host>
   nft add rule inet filter output meta skuid a-<agent> \
     ip daddr != { <allowed-hosts> } drop
   ```
4. Register in `/srv/con/contracts/`:
   ```yaml
   id: CON-<NNN>
   description: <agent> may only reach <host>
   type: preventive
   mechanism: nftables
   agent: <agent>
   enforcement: |
     nft add rule inet filter output meta skuid a-<agent> \
       ip daddr != { <host> } drop
   ```

## Writing a detective contract

1. Define what "correct" looks like (the invariant)
2. Write a check that returns exit 0 (pass) or exit 1 (fail)
3. Define the failure action and escalation target
4. Create the YAML in `/srv/con/contracts/`:
   ```yaml
   id: CON-<NNN>
   description: <what the check verifies>
   type: detective
   frequency: 60s
   scope: agent:<name>
   checks:
     - name: <check name>
       command:
         run: "<shell command>"
         test: "[ $RESULT <condition> ]"
       on_fail:
         action: quarantine    # halt_agents | quarantine | kill_session | alert
         message: "CON-<NNN> FAILED: <description>"
   ```
5. For complex checks, use a script:
   ```yaml
   checks:
     - name: <check name>
       script:
         path: scripts/CON-<NNN>-<name>.sh
         timeout: 30s
   ```
   Scripts: exit 0 = PASS, exit 1 = FAIL. Stdout is the failure message.

## Common anti-patterns

| Anti-pattern | Why it's wrong | Fix |
|-------------|---------------|-----|
| `permission:*` | No restriction at all | List exact permissions |
| "Don't do X" in AGENTS.md | Soft contract, prompt injection bypasses it | Preventive contract |
| One agent does everything | Single compromise = full access | Decompose into roles |
| Network: allow all, block bad | Allowlist is always wrong — too many bad things | Default deny, allow specific hosts |
| Detect-only for preventable violations | Why detect what you can prevent? | Use preventive first |
| No CON-ID | Not a contract, just a wish | Every contract gets an ID |
