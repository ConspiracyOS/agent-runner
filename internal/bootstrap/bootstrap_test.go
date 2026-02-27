package bootstrap

import (
	"strings"
	"testing"

	"github.com/ConspiracyOS/agent-runner/internal/config"
)

func TestProvisionCommands(t *testing.T) {
	cfg := &config.Config{
		System: config.SystemConfig{Name: "test"},
		Agents: []config.AgentConfig{
			{Name: "concierge", Tier: "operator", Mode: "on-demand"},
			{Name: "sysadmin", Tier: "operator", Mode: "on-demand"},
		},
	}

	cmds := PlanProvision(cfg)

	// Should create agents group
	found := false
	for _, c := range cmds {
		if strings.Contains(c, "groupadd") && strings.Contains(c, "agents") {
			found = true
			break
		}
	}
	if !found {
		t.Error("expected groupadd agents command")
	}

	// Should create user a-concierge
	found = false
	for _, c := range cmds {
		if strings.Contains(c, "useradd") && strings.Contains(c, "a-concierge") {
			found = true
			break
		}
	}
	if !found {
		t.Error("expected useradd a-concierge command")
	}

	// Should create /srv/con/agents/concierge/inbox/
	found = false
	for _, c := range cmds {
		if strings.Contains(c, "/srv/con/agents/concierge/inbox") {
			found = true
			break
		}
	}
	if !found {
		t.Error("expected inbox directory creation for concierge")
	}
}

func TestProvisionACLs(t *testing.T) {
	cfg := &config.Config{
		System: config.SystemConfig{Name: "test"},
		Agents: []config.AgentConfig{
			{Name: "concierge", Tier: "operator", Mode: "on-demand"},
			{Name: "sysadmin", Tier: "operator", Mode: "on-demand"},
		},
	}

	cmds := PlanProvision(cfg)

	// Concierge should be able to write to sysadmin's inbox
	found := false
	for _, c := range cmds {
		if strings.Contains(c, "setfacl") && strings.Contains(c, "a-concierge") && strings.Contains(c, "sysadmin/inbox") {
			found = true
			break
		}
	}
	if !found {
		t.Error("expected ACL granting concierge write to sysadmin inbox")
	}
}

func TestProvisionContractInstallation(t *testing.T) {
	cfg := &config.Config{
		System: config.SystemConfig{Name: "test"},
		Agents: []config.AgentConfig{
			{Name: "concierge", Tier: "operator", Mode: "on-demand"},
		},
	}

	cmds := PlanProvision(cfg)

	found := false
	for _, c := range cmds {
		if strings.Contains(c, "cp /etc/con/contracts/*.yaml /srv/con/contracts/") {
			found = true
			break
		}
	}
	if !found {
		t.Error("expected contract file installation command")
	}
}

func TestGenerateHealthcheckUnits(t *testing.T) {
	units := GenerateHealthcheckUnits("60s")

	svc, ok := units["con-healthcheck.service"]
	if !ok {
		t.Fatal("missing con-healthcheck.service")
	}
	if !strings.Contains(svc, "con healthcheck") {
		t.Error("service should run 'con healthcheck'")
	}
	if !strings.Contains(svc, "Type=oneshot") {
		t.Error("service should be oneshot")
	}
	// Should NOT have a User= line (runs as root)
	if strings.Contains(svc, "User=") {
		t.Error("healthcheck service should not have User= (runs as root)")
	}

	timer, ok := units["con-healthcheck.timer"]
	if !ok {
		t.Fatal("missing con-healthcheck.timer")
	}
	if !strings.Contains(timer, "OnUnitActiveSec=60s") {
		t.Error("timer should use the provided interval")
	}
	if !strings.Contains(timer, "OnBootSec=30s") {
		t.Error("timer should have OnBootSec delay")
	}
}

func TestProvisionTrustedGroup(t *testing.T) {
	cfg := &config.Config{
		Agents: []config.AgentConfig{
			{Name: "concierge", Tier: "operator"},
		},
	}
	cmds := PlanProvision(cfg)
	found := false
	for _, c := range cmds {
		if c == "groupadd -f trusted" {
			found = true
			break
		}
	}
	if !found {
		t.Error("PlanProvision should create trusted group")
	}
}

func TestProvisionSudoersFromProfile(t *testing.T) {
	cfg := &config.Config{
		Agents: []config.AgentConfig{
			{Name: "concierge", Tier: "operator"},
			{Name: "sysadmin", Tier: "operator", Roles: []string{"sysadmin"}},
		},
	}
	cmds := PlanProvision(cfg)

	// Should copy sudoers from profile, not hardcode them
	foundCopy := false
	foundValidate := false
	for _, c := range cmds {
		if strings.Contains(c, "cp /etc/con/sudoers.d/") && strings.Contains(c, "/etc/sudoers.d/") {
			foundCopy = true
		}
		if strings.Contains(c, "visudo -c") {
			foundValidate = true
		}
	}
	if !foundCopy {
		t.Error("expected sudoers copy from /etc/con/sudoers.d/ to /etc/sudoers.d/")
	}
	if !foundValidate {
		t.Error("expected visudo -c validation after sudoers install")
	}

	// Should NOT contain hardcoded CONSPIRACY_OPS
	for _, c := range cmds {
		if strings.Contains(c, "Cmnd_Alias CONSPIRACY_OPS") {
			t.Error("sudoers should come from profile files, not be hardcoded in Go")
		}
	}
}

func TestDashboardDisabledStopsNginx(t *testing.T) {
	cfg := &config.Config{
		Dashboard: config.DashboardConfig{Enabled: false, Port: 8080, Bind: "0.0.0.0"},
		Agents: []config.AgentConfig{
			{Name: "concierge", Tier: "operator"},
		},
	}
	cmds := PlanProvision(cfg)

	foundDisable := false
	for _, c := range cmds {
		if strings.Contains(c, "systemctl disable") && strings.Contains(c, "nginx") {
			foundDisable = true
		}
	}
	if !foundDisable {
		t.Error("expected nginx disable when dashboard is disabled")
	}

	// Should NOT enable nginx
	for _, c := range cmds {
		if strings.Contains(c, "systemctl enable") && strings.Contains(c, "nginx") {
			t.Error("should not enable nginx when dashboard is disabled")
		}
	}
}

func TestOuterInboxWatcher(t *testing.T) {
	cfg := &config.Config{
		System: config.SystemConfig{Name: "test"},
		Agents: []config.AgentConfig{
			{Name: "concierge", Tier: "operator", Mode: "on-demand"},
		},
	}

	cmds := PlanProvision(cfg)

	// Should create con-outer-inbox.path unit
	foundPath := false
	for _, c := range cmds {
		if strings.Contains(c, "con-outer-inbox.path") && strings.Contains(c, "PathChanged=/srv/con/inbox") {
			foundPath = true
			break
		}
	}
	if !foundPath {
		t.Error("expected outer inbox .path unit watching /srv/con/inbox")
	}

	// Should create con-outer-inbox.service unit
	foundSvc := false
	for _, c := range cmds {
		if strings.Contains(c, "con-outer-inbox.service") && strings.Contains(c, "con route-inbox") {
			foundSvc = true
			break
		}
	}
	if !foundSvc {
		t.Error("expected outer inbox .service unit running con route-inbox")
	}
}
