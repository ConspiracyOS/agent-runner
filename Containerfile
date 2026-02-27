# Containerfile — ConspiracyOS base image
# Runs with systemd as PID 1 on Ubuntu 24.04
#
# Build: make linux (or make linux-arm64 for Apple Silicon)
#        then: podman build -t conspiracyos -f Containerfile .
FROM ubuntu:24.04

# Prevent interactive prompts
ENV DEBIAN_FRONTEND=noninteractive

# Static dependencies (design doc Section 17)
# Note: all packages below are in 'main' — no universe repo needed
RUN apt-get update && apt-get install -y \
    systemd systemd-sysv \
    openssh-server sudo git tmux curl jq \
    nftables acl unzip tree cron ca-certificates \
    auditd \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Install Tailscale
RUN curl -fsSL https://tailscale.com/install.sh | sh

# Install con binary (pre-built via: make linux or make linux-arm64)
# PicoClaw agent runtime is imported as a Go library — no separate binary needed
COPY con /usr/local/bin/con
RUN chmod +x /usr/local/bin/con

# Copy config profile (default: "default"; override with --build-arg CON_PROFILE=minimal)
ARG CON_PROFILE=default
COPY configs/${CON_PROFILE}/ /etc/con/

# Bootstrap entrypoint (runs as systemd oneshot after boot)
COPY scripts/con-bootstrap-entry.sh /usr/local/bin/con-bootstrap-entry
RUN chmod +x /usr/local/bin/con-bootstrap-entry

# Env export: extract CON_* vars from PID 1 on every boot (before agents start)
# systemd services don't inherit the container's environment, so we write it to a file
COPY scripts/con-export-env.sh /usr/local/bin/con-export-env
RUN chmod +x /usr/local/bin/con-export-env && \
    printf '[Unit]\nDescription=ConspiracyOS env export\nDefaultDependencies=no\nBefore=con-bootstrap.service\n\n[Service]\nType=oneshot\nExecStart=/usr/local/bin/con-export-env\nRemainAfterExit=yes\n\n[Install]\nWantedBy=multi-user.target\n' \
    > /etc/systemd/system/con-env.service && \
    systemctl enable con-env.service

# Create the bootstrap systemd unit
RUN printf '[Unit]\nDescription=ConspiracyOS Bootstrap\nAfter=network.target con-env.service\nConditionPathExists=!/srv/con/.bootstrapped\n\n[Service]\nType=oneshot\nExecStart=/usr/local/bin/con-bootstrap-entry\nRemainAfterExit=yes\n\n[Install]\nWantedBy=multi-user.target\n' \
    > /etc/systemd/system/con-bootstrap.service && \
    systemctl enable con-bootstrap.service

# Copy test suites (smoke + e2e)
COPY test/ /test/

# SSH config
RUN mkdir -p /run/sshd && \
    sed -i 's/#PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config

# systemd as PID 1
STOPSIGNAL SIGRTMIN+3
CMD ["/sbin/init"]
