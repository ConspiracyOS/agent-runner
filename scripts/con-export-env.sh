#!/bin/sh
# Extract CON_* environment variables from PID 1 (container runtime)
# and write them to /etc/con/env for systemd services.
# Runs on every boot before other ConspiracyOS services.
tr '\0' '\n' < /proc/1/environ | grep '^CON_' > /etc/con/env 2>/dev/null
chmod 644 /etc/con/env
