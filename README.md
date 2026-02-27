# ConspiracyOS

A Linux-based agent operating system. Coordinates a fleet of AI agents — a *conspiracy* — using native Linux primitives: users, groups, filesystem permissions, systemd, and git.

## Quick Start

```bash
# 1. Set your OpenRouter key
cp .env.example .env
# Edit .env with your key

# 2. Build and run
make image
make run
```

## Architecture

Agents map to Linux users. They communicate via filesystem inboxes. All enforcement is OS-level — permissions, ACLs, nftables, sudoers. No application-level sandboxing.

**Minimal install:** Concierge (routes tasks) + Sysadmin (operates the system). The human acts as all Officers until commissioning them.

```
Human drops .task file into /srv/con/inbox/
  → Concierge picks up, routes to target agent
  → Agent processes via PicoClaw + OpenRouter
  → Response appears in agent's outbox
```

## Commands

```bash
make image        # Build container image (Apple Silicon)
make run          # Start the conspiracy
make stop         # Stop the conspiracy
make test         # Run Go tests
make linux-arm64  # Cross-compile for Linux arm64
make linux        # Cross-compile for Linux amd64
```

## Inside the VM

```bash
container exec <id> bash

# Drop a task
echo "List all agents" > /srv/con/inbox/001-test.task

# Check output
ls /srv/con/agents/concierge/outbox/

# Logs
journalctl -u con-concierge -u con-outer-inbox -f
```

## Project Structure

```
cmd/conctl/        CLI binary (con bootstrap, con run)
internal/config/   TOML parser, config types
internal/assembler AGENTS.md 5-layer composition
internal/bootstrap Linux provisioning, systemd units
internal/runner/   Agent lifecycle, PicoClaw bridge
configs/           Base instructions, agent skills
```

## Design

See [docs/plans/2026-02-26-conspiracyos-design.md](docs/plans/2026-02-26-conspiracyos-design.md).
