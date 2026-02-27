package runtime

import (
	"testing"

	"github.com/ConspiracyOS/agent-runner/internal/config"
)

func TestBuildPicoConfig(t *testing.T) {
	agent := config.AgentConfig{
		Name:  "concierge",
		Tier:  "operator",
		CLI:   "picoclaw",
		Model: "google/gemini-2.0-flash-001",
	}

	t.Setenv("CON_OPENROUTER_API_KEY", "sk-or-test-key")

	pcfg := BuildPicoConfig(agent)

	if pcfg.Providers.OpenRouter.APIKey != "sk-or-test-key" {
		t.Errorf("expected OpenRouter key, got %q", pcfg.Providers.OpenRouter.APIKey)
	}
	if pcfg.Agents.Defaults.Model != "google/gemini-2.0-flash-001" {
		t.Errorf("expected model, got %q", pcfg.Agents.Defaults.Model)
	}
	expected := "/srv/con/agents/concierge/workspace"
	if pcfg.Agents.Defaults.Workspace != expected {
		t.Errorf("expected workspace %q, got %q", expected, pcfg.Agents.Defaults.Workspace)
	}
	if pcfg.Agents.Defaults.RestrictToWorkspace {
		t.Error("expected RestrictToWorkspace=false")
	}
	if pcfg.Agents.Defaults.MaxToolIterations != 200 {
		t.Errorf("expected MaxToolIterations=200, got %d", pcfg.Agents.Defaults.MaxToolIterations)
	}
}

func TestBuildPicoConfigDefaultModel(t *testing.T) {
	agent := config.AgentConfig{Name: "sysadmin"}
	pcfg := BuildPicoConfig(agent)
	if pcfg.Agents.Defaults.Model != "anthropic/claude-sonnet-4.6" {
		t.Errorf("expected default model, got %q", pcfg.Agents.Defaults.Model)
	}
}

func TestBuildPicoConfigProviderPriority(t *testing.T) {
	agent := config.AgentConfig{Name: "test"}

	t.Setenv("CON_OPENROUTER_API_KEY", "")
	t.Setenv("CON_AUTH_ANTHROPIC", "")
	t.Setenv("CON_AUTH_OPENAI", "")

	pcfg := BuildPicoConfig(agent)
	if pcfg.Providers.OpenRouter.APIKey != "" {
		t.Error("expected no OpenRouter key")
	}

	t.Setenv("CON_AUTH_ANTHROPIC", "sk-ant-key")
	t.Setenv("CON_AUTH_OPENAI", "sk-oai-key")

	pcfg = BuildPicoConfig(agent)
	if pcfg.Providers.Anthropic.APIKey != "sk-ant-key" {
		t.Errorf("expected Anthropic key, got %q", pcfg.Providers.Anthropic.APIKey)
	}
}
