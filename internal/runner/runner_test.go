package runner

import (
	"os"
	"os/user"
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
	if !strings.Contains(prompt, "exercise additional scrutiny") {
		t.Error("unverified prompt should advise scrutiny on external interactions")
	}
	if !strings.Contains(prompt, "do something") {
		t.Error("prompt should contain task content")
	}
}

func TestIsTrustedUID_Root(t *testing.T) {
	if !isTrustedUID(0) {
		t.Error("uid 0 should always be trusted")
	}
}

func TestIsTrustedUID_NonRoot(t *testing.T) {
	uid := uint32(os.Getuid())
	if uid == 0 {
		t.Skip("test must run as non-root")
	}
	if isTrustedUID(uid) {
		t.Error("non-root user without trusted group membership should not be trusted")
	}
}

func TestPickOldestTaskOrder(t *testing.T) {
	inbox := t.TempDir()

	os.WriteFile(filepath.Join(inbox, "003.task"), []byte("third"), 0644)
	os.WriteFile(filepath.Join(inbox, "001.task"), []byte("first"), 0644)
	os.WriteFile(filepath.Join(inbox, "002.task"), []byte("second"), 0644)

	task, err := PickOldestTask(inbox)
	if err != nil {
		t.Fatalf("PickOldestTask failed: %v", err)
	}
	if filepath.Base(task.Path) != "001.task" {
		t.Errorf("expected 001.task to be picked first, got %s", filepath.Base(task.Path))
	}
	if task.Content != "first" {
		t.Errorf("expected content %q, got %q", "first", task.Content)
	}
}

func TestPickOldestTaskOversize(t *testing.T) {
	inbox := t.TempDir()

	// Create a task file larger than 32KB
	bigContent := strings.Repeat("x", 33*1024)
	taskPath := filepath.Join(inbox, "001-big.task")
	os.WriteFile(taskPath, []byte(bigContent), 0644)

	task, err := PickOldestTask(inbox)
	if err != nil {
		t.Fatalf("PickOldestTask failed: %v", err)
	}
	if !strings.HasPrefix(task.Content, "[Attachment: file too large") {
		t.Errorf("expected attachment reference for oversized task, got: %q", task.Content[:80])
	}
	if !strings.Contains(task.Content, taskPath) {
		t.Errorf("attachment reference should include task path, got: %q", task.Content)
	}
}

func TestRouteOutputTimestamp(t *testing.T) {
	agentDir := t.TempDir()
	outbox := filepath.Join(agentDir, "outbox")
	processed := filepath.Join(agentDir, "processed")
	os.MkdirAll(outbox, 0755)
	os.MkdirAll(processed, 0755)

	inbox := filepath.Join(agentDir, "inbox")
	os.MkdirAll(inbox, 0755)
	taskPath := filepath.Join(inbox, "007-mytask.task")
	os.WriteFile(taskPath, []byte("task body"), 0644)

	task := Task{Path: taskPath, Content: "task body"}
	if err := RouteOutput(task, "done", outbox, processed); err != nil {
		t.Fatalf("RouteOutput failed: %v", err)
	}

	files, _ := os.ReadDir(outbox)
	if len(files) != 1 {
		t.Fatalf("expected 1 file in outbox, got %d", len(files))
	}
	name := files[0].Name()
	// Name format: <timestamp>-<taskbase>.response  e.g. 20260228-153000-007-mytask.response
	if !strings.HasSuffix(name, "-007-mytask.response") {
		t.Errorf("output filename should end with task basename (without .task): got %q", name)
	}
	// Timestamp prefix: 8 digits + '-' + 6 digits
	if len(name) < 16 || name[8] != '-' {
		t.Errorf("output filename should start with YYYYMMDD-HHMMSS timestamp: got %q", name)
	}
}

func TestRouteOutputMissingTask(t *testing.T) {
	agentDir := t.TempDir()
	outbox := filepath.Join(agentDir, "outbox")
	processed := filepath.Join(agentDir, "processed")
	os.MkdirAll(outbox, 0755)
	os.MkdirAll(processed, 0755)

	// task.Path does not exist — rename will get ENOENT, which should be tolerated
	task := Task{
		Path:    filepath.Join(agentDir, "inbox", "ghost.task"),
		Content: "never existed",
	}
	if err := RouteOutput(task, "output", outbox, processed); err != nil {
		t.Errorf("RouteOutput should tolerate missing task file (ENOENT), got: %v", err)
	}
}

func TestMoveOuterInboxCrossDevice(t *testing.T) {
	outerInbox := t.TempDir()
	conciergeInbox := t.TempDir()

	// Write multiple tasks and a non-task file
	os.WriteFile(filepath.Join(outerInbox, "002.task"), []byte("b"), 0644)
	os.WriteFile(filepath.Join(outerInbox, "001.task"), []byte("a"), 0644)
	os.WriteFile(filepath.Join(outerInbox, "readme.txt"), []byte("ignore me"), 0644)

	if err := moveOuterInboxTasksTo(outerInbox, conciergeInbox); err != nil {
		t.Fatalf("moveOuterInboxTasksTo failed: %v", err)
	}

	// Both task files should appear in concierge inbox
	for _, name := range []string{"001.task", "002.task"} {
		if _, err := os.Stat(filepath.Join(conciergeInbox, name)); os.IsNotExist(err) {
			t.Errorf("expected %s in concierge inbox", name)
		}
		if _, err := os.Stat(filepath.Join(outerInbox, name)); !os.IsNotExist(err) {
			t.Errorf("expected %s to be removed from outer inbox", name)
		}
	}

	// Non-task file should remain untouched in outer inbox
	if _, err := os.Stat(filepath.Join(outerInbox, "readme.txt")); os.IsNotExist(err) {
		t.Error("expected readme.txt to remain in outer inbox")
	}
}

func TestReadSkills(t *testing.T) {
	skillsDir := t.TempDir()

	os.WriteFile(filepath.Join(skillsDir, "alpha.md"), []byte("alpha content"), 0644)
	os.WriteFile(filepath.Join(skillsDir, "beta.md"), []byte("beta content"), 0644)
	os.WriteFile(filepath.Join(skillsDir, "notes.txt"), []byte("should be ignored"), 0644)
	os.MkdirAll(filepath.Join(skillsDir, "subdir"), 0755)
	os.WriteFile(filepath.Join(skillsDir, "subdir", "nested.md"), []byte("should be ignored"), 0644)

	result := ReadSkills(skillsDir)

	if !strings.Contains(result, "## Skill: alpha") {
		t.Error("expected alpha skill section in output")
	}
	if !strings.Contains(result, "alpha content") {
		t.Error("expected alpha skill content in output")
	}
	if !strings.Contains(result, "## Skill: beta") {
		t.Error("expected beta skill section in output")
	}
	if !strings.Contains(result, "beta content") {
		t.Error("expected beta skill content in output")
	}
	if strings.Contains(result, "should be ignored") {
		t.Error("non-.md files and subdirectory files should not appear in skill output")
	}
}

func TestReadSkillsEmpty(t *testing.T) {
	// Directory exists but has no .md files
	skillsDir := t.TempDir()
	os.WriteFile(filepath.Join(skillsDir, "notes.txt"), []byte("not a skill"), 0644)

	if result := ReadSkills(skillsDir); result != "" {
		t.Errorf("expected empty string for dir with no .md files, got: %q", result)
	}
}

func TestReadSkillsMissingDir(t *testing.T) {
	result := ReadSkills("/nonexistent/path/to/skills")
	if result != "" {
		t.Errorf("expected empty string for missing dir, got: %q", result)
	}
}

func TestIsTrustedUID_WithGroupOverride(t *testing.T) {
	uid := uint32(os.Getuid())
	if uid == 0 {
		t.Skip("test must run as non-root")
	}

	u, err := user.Current()
	if err != nil {
		t.Fatalf("looking up current user: %v", err)
	}
	gids, err := u.GroupIds()
	if err != nil || len(gids) == 0 {
		t.Skip("cannot determine user groups")
	}
	g, err := user.LookupGroupId(gids[0])
	if err != nil {
		t.Skip("cannot look up group name")
	}

	old := TrustedGroupName
	TrustedGroupName = g.Name
	defer func() { TrustedGroupName = old }()

	if !isTrustedUID(uid) {
		t.Errorf("user in group %q should be trusted when TrustedGroupName=%q", g.Name, g.Name)
	}
}
