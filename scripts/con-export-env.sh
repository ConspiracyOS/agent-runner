#!/bin/sh
# Extract CON_* environment variables from PID 1 (container runtime)
# and write them to /etc/con/env for systemd services.
# Runs on every boot before other ConspiracyOS services.
#
# Mode 640 root:agents — only root and agents group can read.
# Prevents non-agent processes from accessing API keys.
tr '\0' '\n' < /proc/1/environ | grep '^CON_' > /etc/con/env 2>/dev/null
chown root:agents /etc/con/env
chmod 640 /etc/con/env
