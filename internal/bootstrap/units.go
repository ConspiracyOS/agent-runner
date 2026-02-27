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

// GenerateUnits returns a map of filename → unit file content for a given agent.
func GenerateUnits(agent config.AgentConfig) map[string]string {
	units := make(map[string]string)
	user := "a-" + agent.Name
	svcName := "con-" + agent.Name

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

[Install]
WantedBy=multi-user.target
`, agent.Name, user, agent.Name, agent.Name, user)

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

[Install]
WantedBy=multi-user.target
`, agent.Name, user, agent.Name, agent.Name, user)
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
