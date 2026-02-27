# Smoke Test

End-to-end Phase 1 validation. Run inside the ConspiracyOS VM after bootstrap completes.

## Run inside the VM

```bash
bash /test/smoke/smoke_test.sh
```

## Run from host (Apple Container with virtiofs)

```bash
# 1. Build the con binary for Linux
cd /path/to/ConspiracyOS
make linux          # amd64
# make linux-arm64  # Apple Silicon

# 2. Build the container image
podman build -t conspiracyos -f Containerfile .

# 3. Run with config and API key
apple-container run \
  --volume ./configs:/etc/con:ro \
  --env CON_OPENROUTER_API_KEY=sk-or-your-key \
  conspiracyos

# 4. SSH in and run smoke test
ssh root@<vm-ip> bash /test/smoke/smoke_test.sh
```

## What it tests

| Section | Checks |
|---------|--------|
| 1. Bootstrap | `con` and `picoclaw` binaries, `.bootstrapped` marker, users, groups |
| 2. Directory structure | Outer inbox, agent inboxes, workspaces, audit log dir |
| 3. Permissions | Sticky bit on outer inbox, private home dirs, ACL cross-agent write |
| 4. Systemd units | Path units enabled for concierge and sysadmin |
| 5. AGENTS.md | Assembled files present and contain base content |
| 6. End-to-end routing | Drop a `.task` → concierge picks up → produces `.response` |
| 7. Audit trail | Audit log file has entries for today |
