package contracts

import "time"

// Contract represents a single YAML contract file.
type Contract struct {
	ID          string  `yaml:"id"`
	Description string  `yaml:"description"`
	Type        string  `yaml:"type"`      // "detective" | "preventive"
	Frequency   string  `yaml:"frequency"` // e.g. "60s"
	Scope       string  `yaml:"scope"`     // "system" | "agent:<name>"
	Checks      []Check `yaml:"checks"`

	// Preventive-only fields (for registry/auditability)
	Mechanism   string `yaml:"mechanism,omitempty"`
	Agent       string `yaml:"agent,omitempty"`
	Enforcement string `yaml:"enforcement,omitempty"`
}

// Check is a single check within a detective contract.
type Check struct {
	Name    string       `yaml:"name"`
	Command *CmdCheck    `yaml:"command,omitempty"`
	Script  *ScriptCheck `yaml:"script,omitempty"`
	OnFail  FailAction   `yaml:"on_fail"`
}

// CmdCheck: inline shell command + test expression.
type CmdCheck struct {
	Run  string `yaml:"run"`  // shell command that produces $RESULT
	Test string `yaml:"test"` // test expression using $RESULT
}

// ScriptCheck: external script.
type ScriptCheck struct {
	Path    string `yaml:"path"`
	Timeout string `yaml:"timeout"`
}

// FailAction defines what happens when a check fails.
type FailAction struct {
	Action   string `yaml:"action"`   // halt_agents | halt_workers | kill_session | quarantine | alert
	Escalate string `yaml:"escalate"` // agent name to receive escalation task
	Message  string `yaml:"message"`
}

// CheckResult captures the outcome of one check execution.
type CheckResult struct {
	ContractID string
	CheckName  string
	Passed     bool
	Output     string
	Error      error
	Duration   time.Duration
}

// RunResult captures the outcome of a full healthcheck run.
type RunResult struct {
	Timestamp time.Time
	Results   []CheckResult
	Passed    int
	Failed    int
	Skipped   int // preventive contracts
}

// Valid failure actions.
var validActions = map[string]bool{
	"halt_agents":  true,
	"halt_workers": true,
	"kill_session": true,
	"quarantine":   true,
	"alert":        true,
}
