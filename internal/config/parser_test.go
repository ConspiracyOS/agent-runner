package config

import (
	"os"
	"path/filepath"
	"testing"
)

func TestParseMinimalConfig(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "con.toml")
	os.WriteFile(path, []byte(`
[system]
name = "test-conspiracy"

[[agents]]
name = "concierge"
tier = "operator"
mode = "on-demand"
instructions = "You are the Concierge."

[[agents]]
name = "sysadmin"
tier = "operator"
mode = "on-demand"
instructions = "You are the Sysadmin."
`), 0644)

	cfg, err := Parse(path)
	if err != nil {
		t.Fatalf("Parse failed: %v", err)
	}
	if cfg.System.Name != "test-conspiracy" {
		t.Errorf("expected name 'test-conspiracy', got %q", cfg.System.Name)
	}
	if len(cfg.Agents) != 2 {
		t.Fatalf("expected 2 agents, got %d", len(cfg.Agents))
	}
	if cfg.Agents[0].Name != "concierge" {
		t.Errorf("expected first agent 'concierge', got %q", cfg.Agents[0].Name)
	}
	if cfg.Agents[0].Tier != "operator" {
		t.Errorf("expected tier 'operator', got %q", cfg.Agents[0].Tier)
	}
}

func TestParseDefaultValues(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "con.toml")
	os.WriteFile(path, []byte(`
[system]
name = "defaults-test"

[defaults.operator]
cli   = "picoclaw"
model = "anthropic/claude-sonnet-4-6"

[[agents]]
name = "concierge"
tier = "operator"
mode = "on-demand"
`), 0644)

	cfg, err := Parse(path)
	if err != nil {
		t.Fatalf("Parse failed: %v", err)
	}

	agent := cfg.ResolvedAgent("concierge")
	if agent.CLI != "picoclaw" {
		t.Errorf("expected cli 'picoclaw', got %q", agent.CLI)
	}
	if agent.Model != "anthropic/claude-sonnet-4-6" {
		t.Errorf("expected model from defaults, got %q", agent.Model)
	}
}

func TestParseValidation(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "con.toml")

	// Missing agent name
	os.WriteFile(path, []byte(`
[system]
name = "bad"

[[agents]]
tier = "operator"
mode = "on-demand"
`), 0644)

	_, err := Parse(path)
	if err == nil {
		t.Error("expected validation error for agent without name")
	}
}

func TestENVOverridesConfig(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "con.toml")
	os.WriteFile(path, []byte(`
[system]
name = "from-config"
`), 0644)

	t.Setenv("CON_SYSTEM_NAME", "from-env")

	cfg, err := Parse(path)
	if err != nil {
		t.Fatalf("Parse failed: %v", err)
	}
	if cfg.System.Name != "from-env" {
		t.Errorf("expected env override 'from-env', got %q", cfg.System.Name)
	}
}
