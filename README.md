# ConspiracyOS

A Linux-based agent operating system. Coordinates a fleet of AI agents — a *conspiracy* — using native Linux primitives: users, groups, filesystem permissions, systemd, and ACLs.

No application-level sandboxing. The OS **is** the sandbox.

## How It Works

Each agent is a Linux user. They communicate through filesystem inboxes. All enforcement is OS-level — permissions, ACLs, nftables, sudoers. Contracts (YAML) define system health checks that run on a timer.

```
Human drops .task file into /srv/con/inbox/
  → Concierge picks up, routes to target agent
  → Agent runs PicoClaw tool loop (LLM + shell/filesystem tools)
  → Response appears in agent's outbox
```

**Minimal install:** Concierge (routes tasks) + Sysadmin (operates the system). The sysadmin can commission new agents at runtime — creating Linux users, directories, ACLs, and systemd units.

## Quick Start

Requires [Apple Container CLI](https://developer.apple.com/documentation/virtualization) (macOS) or any OCI-compatible runtime.

```bash
# 1. Configure
cp .env.example .env
# Edit .env — set CON_OPENROUTER_API_KEY (or CON_AUTH_ANTHROPIC / CON_AUTH_OPENAI)

# 2. Build and run
make image    # Builds Ubuntu 24.04 image with systemd PID 1
make run      # Starts the container

# 3. Drop a task
make task MSG="What agents are running in this conspiracy?"
```

## Architecture

```
/srv/con/
├── inbox/              Outer inbox (human → concierge)
├── agents/
│   ├── concierge/
│   │   ├── inbox/      Tasks from human or other agents
│   │   ├── outbox/     Responses
│   │   ├── processed/  Completed tasks
│   │   ├── workspace/  Agent working directory
│   │   │   ├── skills/ Injected skill files (.md)
│   │   │   └── sessions/ PicoClaw session history
│   │   └── sessions/
│   └── sysadmin/
│       └── ...
├── contracts/          System health contracts (YAML)
├── logs/audit/         Contract audit logs
└── config/             Runtime config overlay
```

**Agents** are Linux users (`a-concierge`, `a-sysadmin`). Each has:
- Home directory (`/home/a-<name>`) with `AGENTS.md` instructions
- Agent directory (`/srv/con/agents/<name>/`) with mode 700
- Cross-agent access via POSIX ACLs (traverse + inbox write)
- Systemd path unit watching their inbox for new `.task` files

**Contracts** are YAML files evaluated by a systemd timer every 60 seconds:
- `CON-SYS-001` through `005`: disk, memory, load, session duration, audit log
- `CON-AGENT-001`: agent directory permissions and ownership
- Failures trigger actions: `alert`, `kill_session`, `quarantine`, `halt_agents`

## Commands

```bash
make image           # Build container image (Apple Silicon arm64)
make image PROFILE=minimal  # Build with minimal profile (concierge only)
make run             # Start the conspiracy
make stop            # Stop the conspiracy
make task MSG="..."  # Drop a task into the outer inbox
make test            # Run Go tests
make deploy          # Rebuild + restart (destroy and recreate)
```

Inside the container:

```bash
con bootstrap        # Provision users, dirs, ACLs, systemd units
con run <agent>      # Execute one agent run (pick task → LLM → route output)
con route-inbox      # Move outer inbox tasks to concierge
con healthcheck      # Evaluate all contracts, log results
```

## Project Structure

```
cmd/conctl/              CLI binary ("con")
internal/
  assembler/             AGENTS.md 5-layer composition
  bootstrap/             Linux provisioning, systemd unit generation
  config/                TOML parser, config types
  contracts/             YAML contract parser, evaluator, actions
  runner/                Agent lifecycle, PicoClaw in-process bridge
configs/
  default/               Full profile (concierge + sysadmin)
    agents/              Per-agent AGENTS.md instructions
    contracts/           System contract YAML files
    roles/sysadmin/skills/  Sysadmin skill files
  minimal/               Concierge-only profile
scripts/                 Bootstrap and env export scripts
test/
  smoke/                 Post-bootstrap smoke tests
  e2e/                   End-to-end test suite (6 scenarios)
```

## Configuration

`configs/<profile>/con.toml`:

```toml
[system]
name = "conspiracyos"

[defaults.operator]
cli   = "picoclaw"
model = "anthropic/claude-sonnet-4.6"

[defaults.worker]
cli   = "picoclaw"
model = "google/gemini-2.0-flash-001"

[[agents]]
name  = "concierge"
tier  = "operator"
roles = ["concierge"]
mode  = "on-demand"

[[agents]]
name  = "sysadmin"
tier  = "operator"
roles = ["sysadmin"]
mode  = "on-demand"
```

## Security Model

Three pillars:

1. **Linux-enforced contracts** — Agent directories are mode 700. Cross-agent access is explicit (ACLs). Sudoers whitelist specific commands.
2. **Assume breach** — No agent can read another's workspace. The sysadmin can operate on agent directories but only through whitelisted commands.
3. **Self-healing heartbeat** — Contracts run every 60s. Violations trigger automated responses (kill sessions, halt agents, escalate).

PicoClaw runs with `restrict_to_workspace: false` and `safety_guard: false` — Linux permissions ARE the sandbox.

## License

MIT
