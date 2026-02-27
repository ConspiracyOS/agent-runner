package runtime

import (
	"context"
	"fmt"

	"github.com/ConspiracyOS/agent-runner/internal/config"
)

// Runtime executes an agent prompt and returns the response.
type Runtime interface {
	Invoke(ctx context.Context, prompt, sessionKey string) (string, error)
}

// New returns the appropriate runtime for an agent based on its CLI config.
// "picoclaw" (the default) uses the in-process PicoClaw library.
// Any other value uses the exec runtime with that value as the command.
func New(agent config.AgentConfig) Runtime {
	switch agent.CLI {
	case "picoclaw", "":
		return &PicoClaw{Agent: agent}
	default:
		return &Exec{
			Cmd:       agent.CLI,
			Args:      agent.CLIArgs,
			Workspace: fmt.Sprintf("/srv/con/agents/%s/workspace", agent.Name),
		}
	}
}
