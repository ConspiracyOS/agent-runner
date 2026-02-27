package config

// Config is the top-level ConspiracyOS configuration.
type Config struct {
	System    SystemConfig           `toml:"system"`
	Infra     InfraConfig            `toml:"infra"`
	Defaults  map[string]TierDefault `toml:"defaults"`
	Network   NetworkConfig          `toml:"network"`
	Contracts ContractsConfig        `toml:"contracts"`
	Dashboard DashboardConfig        `toml:"dashboard"`
	Agents    []AgentConfig          `toml:"agents"`
}

type SystemConfig struct {
	Name string `toml:"name"`
}

type InfraConfig struct {
	TailscaleHostname    string   `toml:"tailscale_hostname"`
	TailscaleLoginServer string   `toml:"tailscale_login_server"`
	SSHAuthorizedKeys    []string `toml:"ssh_authorized_keys"`
	SSHPort              int      `toml:"ssh_port"`
}

type TierDefault struct {
	CLI   string `toml:"cli"`
	Model string `toml:"model"`
}

type NetworkConfig struct {
	OutboundFilter string `toml:"outbound_filter"`
}

type ContractsConfig struct {
	System SystemContracts `toml:"system"`
}

type SystemContracts struct {
	DiskMinFreePct      int     `toml:"disk_min_free_pct"`
	MemMinFreePct       int     `toml:"mem_min_free_pct"`
	MaxLoadFactor       float64 `toml:"max_load_factor"`
	MaxSessionMin       int     `toml:"max_session_min"`
	HealthcheckInterval string  `toml:"healthcheck_interval"`
}

type DashboardConfig struct {
	Enabled bool   `toml:"enabled"`
	Port    int    `toml:"port"`
	Bind    string `toml:"bind"`
}

type AgentConfig struct {
	Name         string   `toml:"name"`
	Tier         string   `toml:"tier"`
	Roles        []string `toml:"roles"`
	Groups       []string `toml:"groups"`
	Scopes       []string `toml:"scopes"`
	Mode         string   `toml:"mode"`
	Cron         string   `toml:"cron"`
	CLI          string   `toml:"cli"`
	CLIArgs      []string `toml:"cli_args"`
	Model        string   `toml:"model"`
	MaxSessions  int      `toml:"max_sessions"`
	Instructions string   `toml:"instructions"`
}

// ResolvedAgent returns an AgentConfig with tier defaults applied.
// Agent-level values take precedence over tier defaults.
func (c *Config) ResolvedAgent(name string) AgentConfig {
	for _, a := range c.Agents {
		if a.Name == name {
			resolved := a
			if defaults, ok := c.Defaults[a.Tier]; ok {
				if resolved.CLI == "" {
					resolved.CLI = defaults.CLI
				}
				if resolved.Model == "" {
					resolved.Model = defaults.Model
				}
			}
			// Global defaults
			if resolved.CLI == "" {
				resolved.CLI = "picoclaw"
			}
			if resolved.MaxSessions == 0 {
				resolved.MaxSessions = 1
			}
			if resolved.Mode == "" {
				resolved.Mode = "on-demand"
			}
			return resolved
		}
	}
	return AgentConfig{}
}
