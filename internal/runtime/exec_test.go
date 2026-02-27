package runtime

import (
	"context"
	"testing"

	"github.com/ConspiracyOS/agent-runner/internal/config"
)

func TestExecRuntime_Echo(t *testing.T) {
	// Use "cat" as the simplest exec runtime — echoes stdin to stdout
	rt := &Exec{
		Cmd:       "cat",
		Workspace: t.TempDir(),
	}

	output, err := rt.Invoke(context.Background(), "hello from prompt", "test-session")
	if err != nil {
		t.Fatalf("Exec.Invoke failed: %v", err)
	}
	if output != "hello from prompt" {
		t.Errorf("expected prompt echoed back, got %q", output)
	}
}

func TestExecRuntime_WithArgs(t *testing.T) {
	// Use "tr" to transform input — proves args are passed
	rt := &Exec{
		Cmd:       "tr",
		Args:      []string{"a-z", "A-Z"},
		Workspace: t.TempDir(),
	}

	output, err := rt.Invoke(context.Background(), "hello", "test-session")
	if err != nil {
		t.Fatalf("Exec.Invoke failed: %v", err)
	}
	if output != "HELLO" {
		t.Errorf("expected %q, got %q", "HELLO", output)
	}
}

func TestExecRuntime_BadCommand(t *testing.T) {
	rt := &Exec{
		Cmd:       "nonexistent-binary-xyz",
		Workspace: t.TempDir(),
	}

	_, err := rt.Invoke(context.Background(), "test", "test-session")
	if err == nil {
		t.Error("expected error for nonexistent command")
	}
}

func TestNew_PicoClaw(t *testing.T) {
	agent := config.AgentConfig{Name: "test", CLI: "picoclaw"}
	rt := New(agent)
	if _, ok := rt.(*PicoClaw); !ok {
		t.Error("expected PicoClaw runtime for cli=picoclaw")
	}
}

func TestNew_Default(t *testing.T) {
	agent := config.AgentConfig{Name: "test"}
	rt := New(agent)
	if _, ok := rt.(*PicoClaw); !ok {
		t.Error("expected PicoClaw runtime for empty cli")
	}
}

func TestNew_Exec(t *testing.T) {
	agent := config.AgentConfig{Name: "test", CLI: "claude-code", CLIArgs: []string{"--print"}}
	rt := New(agent)
	e, ok := rt.(*Exec)
	if !ok {
		t.Fatal("expected Exec runtime for cli=claude-code")
	}
	if e.Cmd != "claude-code" {
		t.Errorf("expected cmd=claude-code, got %q", e.Cmd)
	}
	if len(e.Args) != 1 || e.Args[0] != "--print" {
		t.Errorf("expected args=[--print], got %v", e.Args)
	}
	if e.Workspace != "/srv/con/agents/test/workspace" {
		t.Errorf("expected workspace path, got %q", e.Workspace)
	}
}
