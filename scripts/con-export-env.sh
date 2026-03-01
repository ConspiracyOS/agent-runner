#!/bin/sh
# Extract CON_* environment variables from PID 1 (container runtime)
# and write them to /etc/con/env for systemd services.
# Runs on every boot before other ConspiracyOS services.
#
# Mode 600 root:root — only root (systemd PID 1) can read.
# Agents receive env vars via systemd EnvironmentFile= injection,
# never by reading the file directly. This prevents any agent from
# reading secrets belonging to other agents.
tr '\0' '\n' < /proc/1/environ | grep -E '^(CON_|TS_)' > /etc/con/env 2>/dev/null
chmod 600 /etc/con/env
chown root:root /etc/con/env
