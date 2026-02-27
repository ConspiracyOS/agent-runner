.PHONY: build test clean linux linux-arm64 image run stop task deploy apply status reset

# Container instance name — override for production: make deploy NAME=cos
NAME ?= conspiracyos

# SSH key for apply target — override: make apply SSH_KEY=~/.ssh/other_key PROFILE=default
SSH_KEY ?= ~/.ssh/id_ed25519
SSH_OPTS := -o StrictHostKeyChecking=no -o BatchMode=yes -i $(SSH_KEY)

# Build for current platform
build:
	go build -o con ./cmd/conctl/

# Build for Linux (amd64) — for Containerfile
linux:
	GOOS=linux GOARCH=amd64 go build -o con ./cmd/conctl/

# Build for Linux (arm64) — for Pi / Apple Silicon Container
linux-arm64:
	GOOS=linux GOARCH=arm64 go build -o con ./cmd/conctl/

# Build container image (Apple Silicon) — generic, no profile arg
image: linux-arm64
	container build --dns 8.8.8.8 -t conspiracyos -f Containerfile .

# Run the conspiracy (reads .env for secrets, detached)
run:
	container run -d --name $(NAME) --env-file .env conspiracyos

# Stop the conspiracy
stop:
	container stop $(NAME) && container rm $(NAME)

# Drop a task into the running container's outer inbox
# Usage: make task MSG="what agents are available?"
task:
	@if [ -z "$(MSG)" ]; then echo "Usage: make task MSG=\"your message\""; exit 1; fi
	@TASKID=$$(date +%s); \
	container exec $(NAME) sh -c "printf '%s' '$(MSG)' > /srv/con/inbox/$${TASKID}.task && chown a-concierge:agents /srv/con/inbox/$${TASKID}.task" && \
	echo "Task $${TASKID}.task dropped into inbox"

# Deploy: rebuild image and restart container (boots with minimal profile)
deploy: image
	-container kill $(NAME) 2>/dev/null; container rm $(NAME) 2>/dev/null
	container run -d --name $(NAME) --env-file .env conspiracyos

# Apply a config profile to a running instance
# Resolves container IP and uses SSH tar pipe for file transfer
# (Apple Container CLI doesn't support stdin piping for container exec)
# Requires: CON_SSH_AUTHORIZED_KEYS in .env or ssh-copy-id to container
# Usage: make apply PROFILE=default
apply:
	@if [ -z "$(PROFILE)" ]; then echo "Usage: make apply PROFILE=<name>"; exit 1; fi
	@if [ ! -d "configs/$(PROFILE)" ]; then echo "Error: profile not found: configs/$(PROFILE)"; exit 1; fi
	$(eval IP := $(shell container list 2>/dev/null | grep '$(NAME) ' | awk '{print $$6}' | cut -d/ -f1))
	@if [ -z "$(IP)" ]; then echo "Error: container $(NAME) not running"; exit 1; fi
	@echo "Applying profile: $(PROFILE) -> $(IP)"
	tar -C configs/$(PROFILE) -cf - . | ssh $(SSH_OPTS) root@$(IP) 'tar -C /etc/con -xf -'
	ssh $(SSH_OPTS) root@$(IP) 'set -a; . /etc/con/env 2>/dev/null; set +a; con bootstrap'
	@echo "Profile $(PROFILE) applied successfully."

# Show agent status
status:
	@container exec $(NAME) con status 2>/dev/null || true

# Reset all state (destructive — wipes /srv/con/, preserves /etc/con/ config)
# Usage: make reset CONFIRM=yes
reset:
	@if [ "$(CONFIRM)" != "yes" ]; then \
		echo "This will WIPE all agent state (sessions, tasks, logs, git history)."; \
		echo "Config in /etc/con/ is preserved."; \
		echo "Run: make reset CONFIRM=yes"; \
		exit 1; \
	fi
	container exec $(NAME) bash -c 'systemctl stop con-*.path con-*.timer con-*.service 2>/dev/null || true'
	container exec $(NAME) bash -c 'rm -rf /srv/con && rm -f /srv/con/.bootstrapped'
	container exec $(NAME) con bootstrap
	@echo "Reset complete. State wiped, config preserved."

# Run all tests
test:
	go test ./... -v

# Clean
clean:
	rm -f con
