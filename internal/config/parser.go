package config

import (
	"fmt"
	"os"
	"strings"

	"github.com/BurntSushi/toml"
)

func Parse(path string) (*Config, error) {
	var cfg Config
	if _, err := toml.DecodeFile(path, &cfg); err != nil {
		return nil, fmt.Errorf("parsing %s: %w", path, err)
	}

	applyENVOverrides(&cfg)
	applyDefaults(&cfg)

	if err := validate(&cfg); err != nil {
		return nil, err
	}

	return &cfg, nil
}

func applyENVOverrides(cfg *Config) {
	if v := os.Getenv("CON_SYSTEM_NAME"); v != "" {
		cfg.System.Name = v
	}
	if v := os.Getenv("CON_INFRA_TAILSCALE_HOSTNAME"); v != "" {
		cfg.Infra.TailscaleHostname = v
	}
	if v := os.Getenv("CON_INFRA_TAILSCALE_LOGIN_SERVER"); v != "" {
		cfg.Infra.TailscaleLoginServer = v
	}
	if v := os.Getenv("CON_SSH_AUTHORIZED_KEYS"); v != "" {
		cfg.Infra.SSHAuthorizedKeys = strings.Split(v, "\n")
	}
}

func applyDefaults(cfg *Config) {
	if cfg.System.Name == "" {
		cfg.System.Name = "conspiracy"
	}
	if cfg.Network.OutboundFilter == "" {
		cfg.Network.OutboundFilter = "strict"
	}
	if cfg.Infra.SSHPort == 0 {
		cfg.Infra.SSHPort = 22
	}
	if cfg.Contracts.System.DiskMinFreePct == 0 {
		cfg.Contracts.System.DiskMinFreePct = 15
	}
	if cfg.Contracts.System.MemMinFreePct == 0 {
		cfg.Contracts.System.MemMinFreePct = 10
	}
	if cfg.Contracts.System.MaxLoadFactor == 0 {
		cfg.Contracts.System.MaxLoadFactor = 2.0
	}
	if cfg.Contracts.System.MaxSessionMin == 0 {
		cfg.Contracts.System.MaxSessionMin = 30
	}
	if cfg.Contracts.System.HealthcheckInterval == "" {
		cfg.Contracts.System.HealthcheckInterval = "60s"
	}
	if cfg.Dashboard.Port == 0 {
		cfg.Dashboard.Port = 8080
	}
	if cfg.Dashboard.Bind == "" {
		cfg.Dashboard.Bind = "0.0.0.0"
	}
}

func validate(cfg *Config) error {
	validTiers := map[string]bool{"officer": true, "operator": true, "worker": true}
	validModes := map[string]bool{"on-demand": true, "continuous": true, "cron": true}

	for i, a := range cfg.Agents {
		if a.Name == "" {
			return fmt.Errorf("agent[%d]: name is required", i)
		}
		if a.Tier != "" && !validTiers[a.Tier] {
			return fmt.Errorf("agent %q: invalid tier %q (must be officer/operator/worker)", a.Name, a.Tier)
		}
		if a.Mode != "" && !validModes[a.Mode] {
			return fmt.Errorf("agent %q: invalid mode %q (must be on-demand/continuous/cron)", a.Name, a.Mode)
		}
		if a.Mode == "cron" && a.Cron == "" {
			return fmt.Errorf("agent %q: cron mode requires a cron expression", a.Name)
		}
	}
	return nil
}
