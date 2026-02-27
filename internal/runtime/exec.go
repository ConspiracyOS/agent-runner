package runtime

import (
	"bytes"
	"context"
	"fmt"
	"os/exec"
	"strings"
)

// Exec runs an agent using an external CLI binary.
// The prompt is passed via stdin. The response is read from stdout.
type Exec struct {
	Cmd       string
	Args      []string
	Workspace string
}

// Invoke runs the configured CLI, passing prompt via stdin and capturing stdout.
// sessionKey is accepted for interface compatibility but not forwarded — external
// CLIs manage their own session state.
func (e *Exec) Invoke(ctx context.Context, prompt, sessionKey string) (string, error) {
	cmd := exec.CommandContext(ctx, e.Cmd, e.Args...)
	cmd.Stdin = strings.NewReader(prompt)
	cmd.Dir = e.Workspace

	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	output, err := cmd.Output()
	if err != nil {
		if stderr.Len() > 0 {
			return "", fmt.Errorf("exec runtime %s: %w\nstderr: %s", e.Cmd, err, stderr.String())
		}
		return "", fmt.Errorf("exec runtime %s: %w", e.Cmd, err)
	}
	return string(output), nil
}
