package bootstrap

import (
	"fmt"

	"github.com/ConspiracyOS/agent-runner/internal/config"
)

// GenerateHealthcheckUnits returns systemd units for the contract healthcheck timer.
func GenerateHealthcheckUnits(interval string) map[string]string {
	units := make(map[string]string)

	svc := `[Unit]
Description=ConspiracyOS contract healthcheck
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/con healthcheck
ExecStartPost=-/usr/local/bin/con-status-page
`
	units["con-healthcheck.service"] = svc

	timer := fmt.Sprintf(`[Unit]
Description=ConspiracyOS healthcheck timer

[Timer]
OnBootSec=30s
OnUnitActiveSec=%s
AccuracySec=1s

[Install]
WantedBy=timers.target
`, interval)
	units["con-healthcheck.timer"] = timer

	return units
}

// hasSudo returns true if the agent has a role that grants sudoers access.
// These agents cannot use NoNewPrivileges or ProtectSystem=strict.
func hasSudo(agent config.AgentConfig) bool {
	for _, r := range agent.Roles {
		if r == "sysadmin" {
			return true
		}
	}
	return false
}

// serviceHardening returns systemd hardening directives for an agent.
// Agents with sudo get a reduced set (no NoNewPrivileges, no ProtectSystem=strict).
func serviceHardening(agent config.AgentConfig) string {
	user := "a-" + agent.Name
	base := fmt.Sprintf(`PrivateTmp=yes
PrivateDevices=yes
ProtectKernelTunables=yes
ProtectControlGroups=yes
ProtectHome=tmpfs
BindPaths=/home/%s
BindPaths=/srv/con/agents/%s
BindReadOnlyPaths=/srv/con/agents
UMask=0077
`, user, agent.Name)

	if !hasSudo(agent) {
		base += `NoNewPrivileges=yes
ProtectSystem=strict
`
	} else {
		// Sudo agents (sysadmin) need write access to commissioning paths.
		// Without ProtectSystem=strict, the filesystem is rw by default,
		// but we still bind-mount /srv/con/agents read-only above.
		// Override with explicit ReadWritePaths for paths sysadmin must modify.
		base += fmt.Sprintf(`ReadWritePaths=/srv/con/agents
ReadWritePaths=/srv/con/config
ReadWritePaths=/srv/con/contracts
ReadWritePaths=/srv/con/logs
ReadWritePaths=/etc/con
ReadWritePaths=/etc/sudoers.d
ReadWritePaths=/etc/systemd/system
`)
	}
	return base
}

// GenerateUnits returns a map of filename → unit file content for a given agent.
func GenerateUnits(agent config.AgentConfig) map[string]string {
	units := make(map[string]string)
	user := "a-" + agent.Name
	svcName := "con-" + agent.Name
	hardening := serviceHardening(agent)

	// Service unit (always generated)
	// EnvironmentFile loads API keys from /etc/con/env (written at container start)
	svc := fmt.Sprintf(`[Unit]
Description=ConspiracyOS agent: %s
After=network.target

[Service]
Type=oneshot
User=%s
Group=agents
ExecStart=/usr/local/bin/con run %s
WorkingDirectory=/srv/con/agents/%s/workspace
Environment=HOME=/home/%s
EnvironmentFile=-/etc/con/env
%s
[Install]
WantedBy=multi-user.target
`, agent.Name, user, agent.Name, agent.Name, user, hardening)

	units[svcName+".service"] = svc

	switch agent.Mode {
	case "on-demand":
		// Path unit watches inbox
		path := fmt.Sprintf(`[Unit]
Description=ConspiracyOS inbox watcher: %s

[Path]
PathChanged=/srv/con/agents/%s/inbox
MakeDirectory=yes

[Install]
WantedBy=multi-user.target
`, agent.Name, agent.Name)
		units[svcName+".path"] = path

	case "continuous":
		// Override service to be long-running
		svc = fmt.Sprintf(`[Unit]
Description=ConspiracyOS agent: %s
After=network.target

[Service]
Type=simple
User=%s
Group=agents
ExecStart=/usr/local/bin/con run %s --continuous
WorkingDirectory=/srv/con/agents/%s/workspace
Environment=HOME=/home/%s
EnvironmentFile=-/etc/con/env
Restart=on-failure
RestartSec=5
%s
[Install]
WantedBy=multi-user.target
`, agent.Name, user, agent.Name, agent.Name, user, hardening)
		units[svcName+".service"] = svc

	case "cron":
		timer := fmt.Sprintf(`[Unit]
Description=ConspiracyOS timer: %s

[Timer]
OnCalendar=%s
Persistent=true

[Install]
WantedBy=timers.target
`, agent.Name, agent.Cron)
		units[svcName+".timer"] = timer
	}

	return units
}
