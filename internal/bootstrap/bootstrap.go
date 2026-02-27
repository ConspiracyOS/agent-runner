package bootstrap

import (
	"fmt"

	"github.com/ConspiracyOS/agent-runner/internal/config"
)

// PlanProvision returns the shell commands needed to provision the conspiracy.
// This is a "dry run" — no commands are executed. Use Execute() to run them.
func PlanProvision(cfg *config.Config) []string {
	var cmds []string

	// 1. Create groups
	cmds = append(cmds, "groupadd -f agents")
	cmds = append(cmds, "groupadd -f officers")
	cmds = append(cmds, "groupadd -f operators")
	cmds = append(cmds, "groupadd -f workers")

	// Can-task groups (who can write to whose inbox)
	for _, a := range cfg.Agents {
		cmds = append(cmds, fmt.Sprintf("groupadd -f can-task-%s", a.Name))
	}

	// 2. Create users
	for _, a := range cfg.Agents {
		user := "a-" + a.Name
		groups := "agents"
		switch a.Tier {
		case "officer":
			groups += ",officers"
		case "operator":
			groups += ",operators"
		}
		cmds = append(cmds, fmt.Sprintf(
			"useradd -r -m -d /home/%s -s /bin/bash -g agents -G %s %s || true",
			user, groups, user,
		))
		cmds = append(cmds, fmt.Sprintf("chmod 700 /home/%s", user))
	}

	// 3. Create directory structure
	// Top-level dirs
	cmds = append(cmds, "install -d -m 755 /etc/con")
	cmds = append(cmds, "install -d -m 755 /etc/con/base")
	cmds = append(cmds, "install -d -m 755 /etc/con/roles")
	cmds = append(cmds, "install -d -m 755 /etc/con/groups")
	cmds = append(cmds, "install -d -m 755 /etc/con/scopes")
	cmds = append(cmds, "install -d -m 755 /etc/con/agents")

	// /srv/con/
	cmds = append(cmds, "install -d -m 755 /srv/con")
	cmds = append(cmds, "install -d -m 1777 /srv/con/inbox")  // sticky, world-writable
	cmds = append(cmds, "install -d -m 775 /srv/con/artifacts")
	cmds = append(cmds, "install -d -m 755 /srv/con/config")
	cmds = append(cmds, "install -d -m 755 /srv/con/config/agents")
	cmds = append(cmds, "install -d -m 755 /srv/con/contracts")
	cmds = append(cmds, "install -d -m 755 /srv/con/logs")
	cmds = append(cmds, "install -d -m 755 /srv/con/logs/audit")
	cmds = append(cmds, "install -d -m 755 /srv/con/scopes")

	// Per-agent dirs
	for _, a := range cfg.Agents {
		user := "a-" + a.Name
		base := fmt.Sprintf("/srv/con/agents/%s", a.Name)
		cmds = append(cmds,
			fmt.Sprintf("install -d -o %s -g agents -m 700 %s", user, base),
			fmt.Sprintf("install -d -o %s -g agents -m 700 %s/inbox", user, base),
			fmt.Sprintf("install -d -o %s -g agents -m 700 %s/outbox", user, base),
			fmt.Sprintf("install -d -o %s -g agents -m 700 %s/workspace", user, base),
			fmt.Sprintf("install -d -o %s -g agents -m 700 %s/sessions", user, base),
			fmt.Sprintf("install -d -o %s -g agents -m 700 %s/processed", user, base),
		)
	}

	// 4. ACLs — default tasking permissions for minimal install
	// With mode 700, agents need explicit traverse (--x) on each other's base dirs
	// to reach the inbox subdirectory.
	// Concierge can task sysadmin: traverse base + rwx inbox
	cmds = append(cmds, "setfacl -m u:a-concierge:x /srv/con/agents/sysadmin/")
	cmds = append(cmds, "setfacl -m u:a-concierge:rwx /srv/con/agents/sysadmin/inbox/")
	// Sysadmin can task concierge: traverse base + rwx inbox
	cmds = append(cmds, "setfacl -m u:a-sysadmin:x /srv/con/agents/concierge/")
	cmds = append(cmds, "setfacl -m u:a-sysadmin:rwx /srv/con/agents/concierge/inbox/")

	// Sysadmin write access to inner config, contracts, and audit log (for commissioning)
	cmds = append(cmds, "setfacl -m u:a-sysadmin:rwx /srv/con/config/agents/")
	cmds = append(cmds, "setfacl -m u:a-sysadmin:rwx /srv/con/contracts/")
	cmds = append(cmds, "setfacl -m u:a-sysadmin:rwx /srv/con/logs/audit/")

	// 5. Sudoers for sysadmin
	// Patterns must match commands in commission-agent.md skill exactly.
	// Trailing * in sudoers matches all remaining arguments.
	cmds = append(cmds, `cat > /etc/sudoers.d/con-sysadmin << 'SUDOERS'
Cmnd_Alias CONSPIRACY_OPS = \
    /usr/bin/systemctl start con-*, \
    /usr/bin/systemctl stop con-*, \
    /usr/bin/systemctl restart con-*, \
    /usr/bin/systemctl enable con-*, \
    /usr/bin/systemctl enable --now con-*, \
    /usr/bin/systemctl daemon-reload, \
    /usr/sbin/useradd, \
    /usr/sbin/usermod, \
    /usr/sbin/groupadd, \
    /usr/bin/install -d /srv/con/agents/*, \
    /usr/bin/install -d -o * -g agents -m * /srv/con/agents/*, \
    /usr/bin/setfacl -m * /srv/con/agents/*, \
    /usr/bin/chown * /srv/con/agents/*, \
    /usr/bin/chown * /home/a-*, \
    /usr/bin/chmod 700 /home/a-*, \
    /usr/bin/tee /etc/systemd/system/con-*

a-sysadmin ALL=(root) NOPASSWD: CONSPIRACY_OPS
SUDOERS`)

	// 6. Install system contracts from outer config
	cmds = append(cmds, "cp /etc/con/contracts/*.yaml /srv/con/contracts/ 2>/dev/null || true")
	cmds = append(cmds, "cp -r /etc/con/contracts/scripts/ /srv/con/contracts/scripts/ 2>/dev/null || true")

	// 7. Initialize /srv/con/ as git repo
	cmds = append(cmds, "cd /srv/con && git init && git add -A && git commit -m 'initial state' --allow-empty || true")

	// 8. Outer inbox watcher — triggers concierge when files land in /srv/con/inbox
	cmds = append(cmds, `cat > /etc/systemd/system/con-outer-inbox.path << 'EOF'
[Unit]
Description=ConspiracyOS outer inbox watcher

[Path]
PathChanged=/srv/con/inbox
MakeDirectory=yes

[Install]
WantedBy=multi-user.target
EOF`)

	cmds = append(cmds, `cat > /etc/systemd/system/con-outer-inbox.service << 'EOF'
[Unit]
Description=ConspiracyOS outer inbox -> concierge inbox

[Service]
Type=oneshot
User=a-concierge
ExecStart=/usr/local/bin/con route-inbox
EnvironmentFile=-/etc/con/env
EOF`)

	cmds = append(cmds, "systemctl enable --now con-outer-inbox.path")

	return cmds
}
