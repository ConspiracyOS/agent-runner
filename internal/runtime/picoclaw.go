package runtime

import (
	"context"
	"fmt"
	"os"

	pcagent "github.com/sipeed/picoclaw/pkg/agent"
	"github.com/sipeed/picoclaw/pkg/bus"
	pcconfig "github.com/sipeed/picoclaw/pkg/config"
	"github.com/sipeed/picoclaw/pkg/providers"

	conconfig "github.com/ConspiracyOS/agent-runner/internal/config"
)

// PicoClaw runs agents using the in-process PicoClaw library.
type PicoClaw struct {
	Agent conconfig.AgentConfig
}

func (p *PicoClaw) Invoke(ctx context.Context, prompt, sessionKey string) (string, error) {
	cfg := BuildPicoConfig(p.Agent)

	provider, err := providers.CreateProvider(cfg)
	if err != nil {
		return "", fmt.Errorf("creating LLM provider: %w", err)
	}

	msgBus := bus.NewMessageBus()
	defer msgBus.Close()

	loop := pcagent.NewAgentLoop(cfg, msgBus, provider)

	return loop.ProcessDirect(ctx, prompt, sessionKey)
}

// BuildPicoConfig creates a PicoClaw config from a ConspiracyOS agent config.
func BuildPicoConfig(agent conconfig.AgentConfig) *pcconfig.Config {
	model := agent.Model
	if model == "" {
		model = "anthropic/claude-sonnet-4.6"
	}

	workspace := "/srv/con/agents/" + agent.Name + "/workspace"

	cfg := pcconfig.DefaultConfig()
	cfg.Agents.Defaults.Workspace = workspace
	cfg.Agents.Defaults.RestrictToWorkspace = false
	cfg.Agents.Defaults.Model = model
	cfg.Agents.Defaults.MaxTokens = 8192
	cfg.Agents.Defaults.MaxToolIterations = 50

	if key := os.Getenv("CON_OPENROUTER_API_KEY"); key != "" {
		cfg.Providers.OpenRouter = pcconfig.ProviderConfig{
			APIKey: key,
		}
	} else if key := os.Getenv("CON_AUTH_ANTHROPIC"); key != "" {
		cfg.Providers.Anthropic = pcconfig.ProviderConfig{
			APIKey: key,
		}
	} else if key := os.Getenv("CON_AUTH_OPENAI"); key != "" {
		cfg.Providers.OpenAI = pcconfig.ProviderConfig{
			APIKey: key,
		}
	}

	return cfg
}
