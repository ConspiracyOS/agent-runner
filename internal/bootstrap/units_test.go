package bootstrap

import (
	"strings"
	"testing"

	"github.com/ConspiracyOS/agent-runner/internal/config"
)

func TestGenerateOnDemandUnits(t *testing.T) {
	agent := config.AgentConfig{
		Name: "concierge",
		Tier: "operator",
		Mode: "on-demand",
	}

	units := GenerateUnits(agent)

	// Should produce a .path unit
	pathUnit, ok := units["con-concierge.path"]
	if !ok {
		t.Fatal("expected con-concierge.path unit")
	}
	if !strings.Contains(pathUnit, "PathChanged=/srv/con/agents/concierge/inbox") {
		t.Error("path unit should watch agent inbox")
	}

	// Should produce a .service unit
	svcUnit, ok := units["con-concierge.service"]
	if !ok {
		t.Fatal("expected con-concierge.service unit")
	}
	if !strings.Contains(svcUnit, "User=a-concierge") {
		t.Error("service should run as a-concierge")
	}
	if !strings.Contains(svcUnit, "ExecStart=/usr/local/bin/con run concierge") {
		t.Error("service should exec con run")
	}
}

func TestGenerateCronUnits(t *testing.T) {
	agent := config.AgentConfig{
		Name: "reporter",
		Tier: "worker",
		Mode: "cron",
		Cron: "*-*-* 09:00:00",
	}

	units := GenerateUnits(agent)

	timerUnit, ok := units["con-reporter.timer"]
	if !ok {
		t.Fatal("expected con-reporter.timer unit")
	}
	if !strings.Contains(timerUnit, "OnCalendar=*-*-* 09:00:00") {
		t.Error("timer should use cron expression")
	}
}
