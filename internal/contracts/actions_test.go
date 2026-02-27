package contracts

import (
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestDispatchAction_HaltAgents(t *testing.T) {
	exec := &MockExecutor{ExitCode: 0}
	action := FailAction{Action: "halt_agents", Message: "test"}

	cmds, err := DispatchAction(context.Background(), action, "system", exec)
	if err != nil {
		t.Fatal(err)
	}
	if len(cmds) != 1 {
		t.Fatalf("cmds = %d, want 1", len(cmds))
	}
	if !strings.Contains(cmds[0], "systemctl stop") {
		t.Errorf("expected systemctl stop, got: %s", cmds[0])
	}
}

func TestDispatchAction_HaltWorkers(t *testing.T) {
	exec := &MockExecutor{ExitCode: 0}
	action := FailAction{Action: "halt_workers", Message: "test"}

	cmds, err := DispatchAction(context.Background(), action, "system", exec)
	if err != nil {
		t.Fatal(err)
	}
	// v1: halt_workers = halt_agents
	if len(cmds) != 1 {
		t.Fatalf("cmds = %d, want 1", len(cmds))
	}
}

func TestDispatchAction_KillSession(t *testing.T) {
	exec := &MockExecutor{ExitCode: 0}
	action := FailAction{Action: "kill_session", Message: "session too long"}

	cmds, err := DispatchAction(context.Background(), action, "agent:researcher", exec)
	if err != nil {
		t.Fatal(err)
	}
	if len(cmds) != 1 {
		t.Fatalf("cmds = %d, want 1", len(cmds))
	}
	if !strings.Contains(cmds[0], "pkill -u a-researcher picoclaw") {
		t.Errorf("expected pkill for researcher, got: %s", cmds[0])
	}
}

func TestDispatchAction_KillSession_NoAgent(t *testing.T) {
	exec := &MockExecutor{ExitCode: 0}
	action := FailAction{Action: "kill_session", Message: "test"}

	_, err := DispatchAction(context.Background(), action, "system", exec)
	if err == nil {
		t.Error("expected error for kill_session without agent scope")
	}
}

func TestDispatchAction_Quarantine(t *testing.T) {
	exec := &MockExecutor{ExitCode: 0}
	action := FailAction{Action: "quarantine", Message: "compromised"}

	cmds, err := DispatchAction(context.Background(), action, "agent:badagent", exec)
	if err != nil {
		t.Fatal(err)
	}
	if len(cmds) != 2 {
		t.Fatalf("cmds = %d, want 2", len(cmds))
	}
	if !strings.Contains(cmds[0], "systemctl stop con-badagent") {
		t.Errorf("first cmd should stop service, got: %s", cmds[0])
	}
	if !strings.Contains(cmds[1], "setfacl -b") {
		t.Errorf("second cmd should revoke ACLs, got: %s", cmds[1])
	}
}

func TestDispatchAction_Alert(t *testing.T) {
	exec := &MockExecutor{ExitCode: 0}
	action := FailAction{Action: "alert", Message: "info only"}

	cmds, err := DispatchAction(context.Background(), action, "system", exec)
	if err != nil {
		t.Fatal(err)
	}
	if len(cmds) != 0 {
		t.Errorf("alert should execute no commands, got %d", len(cmds))
	}
	if len(exec.Calls) != 0 {
		t.Errorf("alert should not call executor, got %d calls", len(exec.Calls))
	}
}

func TestEscalate(t *testing.T) {
	// Use a temp dir to simulate the inbox
	dir := t.TempDir()
	inbox := filepath.Join(dir, "inbox")
	os.MkdirAll(inbox, 0755)

	// Monkey-patch: test the Escalate function by writing to a known path
	// Since Escalate uses a hardcoded path, we test parseAgentFromScope instead
	// and test the file writing separately

	agent := parseAgentFromScope("agent:sysadmin")
	if agent != "sysadmin" {
		t.Errorf("parseAgentFromScope(agent:sysadmin) = %q, want sysadmin", agent)
	}

	agent = parseAgentFromScope("system")
	if agent != "" {
		t.Errorf("parseAgentFromScope(system) = %q, want empty", agent)
	}
}

func TestDispatchAction_UnknownAction(t *testing.T) {
	exec := &MockExecutor{ExitCode: 0}
	action := FailAction{Action: "destroy_everything", Message: "bad"}

	_, err := DispatchAction(context.Background(), action, "system", exec)
	if err == nil {
		t.Error("expected error for unknown action")
	}
}
