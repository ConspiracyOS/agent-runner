package runner

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestPickOldestTask(t *testing.T) {
	inbox := t.TempDir()

	// Create task files (numbered for ordering)
	os.WriteFile(filepath.Join(inbox, "002-second.task"), []byte("second task"), 0644)
	os.WriteFile(filepath.Join(inbox, "001-first.task"), []byte("first task"), 0644)
	os.WriteFile(filepath.Join(inbox, "003-third.task"), []byte("third task"), 0644)

	task, err := PickOldestTask(inbox)
	if err != nil {
		t.Fatalf("PickOldestTask failed: %v", err)
	}
	if filepath.Base(task.Path) != "001-first.task" {
		t.Errorf("expected 001-first.task, got %s", filepath.Base(task.Path))
	}
	if task.Content != "first task" {
		t.Errorf("unexpected content: %q", task.Content)
	}
}

func TestPickOldestTaskEmptyInbox(t *testing.T) {
	inbox := t.TempDir()

	_, err := PickOldestTask(inbox)
	if err == nil {
		t.Error("expected error for empty inbox")
	}
}

func TestRouteOutput(t *testing.T) {
	agentDir := t.TempDir()
	outbox := filepath.Join(agentDir, "outbox")
	processed := filepath.Join(agentDir, "processed")
	os.MkdirAll(outbox, 0755)
	os.MkdirAll(processed, 0755)

	task := Task{
		Path:    filepath.Join(agentDir, "inbox", "001-test.task"),
		Content: "original task",
	}
	os.MkdirAll(filepath.Dir(task.Path), 0755)
	os.WriteFile(task.Path, []byte(task.Content), 0644)

	output := "Task completed successfully"
	err := RouteOutput(task, output, outbox, processed)
	if err != nil {
		t.Fatalf("RouteOutput failed: %v", err)
	}

	// Check outbox has the response
	files, _ := os.ReadDir(outbox)
	if len(files) == 0 {
		t.Error("expected output file in outbox")
	}

	// Check task was moved to processed
	_, err = os.Stat(task.Path)
	if !os.IsNotExist(err) {
		t.Error("expected task to be moved from inbox")
	}

	processedFiles, _ := os.ReadDir(processed)
	if len(processedFiles) == 0 {
		t.Error("expected task in processed dir")
	}
}

func TestMoveOuterInboxTasks(t *testing.T) {
	// Patch the outer inbox and concierge inbox to temp dirs using env vars
	// Since MoveOuterInboxTasks uses hardcoded paths, we test it via a wrapper
	// by temporarily monkey-patching via a helper that accepts paths.
	outerInbox := t.TempDir()
	conciergeInbox := t.TempDir()

	// Create a task in the outer inbox
	os.WriteFile(filepath.Join(outerInbox, "001-test.task"), []byte("task content"), 0644)
	// Create a non-task file (should be ignored)
	os.WriteFile(filepath.Join(outerInbox, "README.txt"), []byte("not a task"), 0644)

	err := moveOuterInboxTasksTo(outerInbox, conciergeInbox)
	if err != nil {
		t.Fatalf("moveOuterInboxTasksTo failed: %v", err)
	}

	// Task should be in concierge inbox
	_, err = os.Stat(filepath.Join(conciergeInbox, "001-test.task"))
	if os.IsNotExist(err) {
		t.Error("expected task to be moved to concierge inbox")
	}

	// Task should be gone from outer inbox
	_, err = os.Stat(filepath.Join(outerInbox, "001-test.task"))
	if !os.IsNotExist(err) {
		t.Error("expected task to be removed from outer inbox")
	}

	// Non-task file should remain
	_, err = os.Stat(filepath.Join(outerInbox, "README.txt"))
	if os.IsNotExist(err) {
		t.Error("expected non-task file to remain in outer inbox")
	}
}

func TestPickOldestTaskTrust(t *testing.T) {
	inbox := t.TempDir()
	os.WriteFile(filepath.Join(inbox, "001-test.task"), []byte("test content"), 0644)

	task, err := PickOldestTask(inbox)
	if err != nil {
		t.Fatalf("PickOldestTask failed: %v", err)
	}

	// Files created by test process (non-root) should be unverified
	if task.Trust != TrustUnverified {
		t.Errorf("expected TrustUnverified for non-root file, got %s", task.Trust)
	}
}

func TestTrustLevelString(t *testing.T) {
	if TrustVerified.String() != "verified" {
		t.Errorf("TrustVerified.String() = %q, want %q", TrustVerified.String(), "verified")
	}
	if TrustUnverified.String() != "unverified" {
		t.Errorf("TrustUnverified.String() = %q, want %q", TrustUnverified.String(), "unverified")
	}
}

func TestFrameTaskPrompt_Verified(t *testing.T) {
	task := Task{Content: "do something", Trust: TrustVerified}
	prompt := FrameTaskPrompt(task)

	if !strings.Contains(prompt, "Task from verified source") {
		t.Error("verified task prompt should contain 'Task from verified source'")
	}
	if !strings.Contains(prompt, "do something") {
		t.Error("prompt should contain task content")
	}
}

func TestFrameTaskPrompt_Unverified(t *testing.T) {
	task := Task{Content: "do something", Trust: TrustUnverified}
	prompt := FrameTaskPrompt(task)

	if !strings.Contains(prompt, "unverified source") {
		t.Error("unverified task prompt should contain 'unverified source'")
	}
	if !strings.Contains(prompt, "do NOT take consequential actions") {
		t.Error("unverified prompt should warn against consequential actions")
	}
	if !strings.Contains(prompt, "do something") {
		t.Error("prompt should contain task content")
	}
}
