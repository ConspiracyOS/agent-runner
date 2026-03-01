.PHONY: build test test-smoke test-e2e test-all clean linux linux-arm64 image run stop task deploy apply status reset discord

# Container instance name — override for production: make deploy NAME=cos
NAME ?= conspiracyos

# Config profile baked into image — override: make image PROFILE=default
PROFILE ?= minimal

# Persistent Tailscale state — survives container rebuilds
TS_STATE ?= $(CURDIR)/srv/dev/tailscale-state

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
	container build --dns 8.8.8.8 --build-arg PROFILE=$(PROFILE) -t conspiracyos -f Containerfile .

# Run the conspiracy (reads container env for secrets, detached)
run:
	@mkdir -p $(TS_STATE)
	container run -d --name $(NAME) -v $(TS_STATE):/var/lib/tailscale-persist --env-file srv/dev/container.env conspiracyos

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
	@mkdir -p $(TS_STATE)
	container run -d --name $(NAME) -v $(TS_STATE):/var/lib/tailscale-persist --env-file srv/dev/container.env conspiracyos

# Apply a config profile to a running instance via container exec
# Usage: make apply PROFILE=default
apply:
	@if [ -z "$(PROFILE)" ]; then echo "Usage: make apply PROFILE=<name>"; exit 1; fi
	@if [ ! -d "configs/$(PROFILE)" ]; then echo "Error: profile not found: configs/$(PROFILE)"; exit 1; fi
	@echo "Applying profile: $(PROFILE) -> $(NAME)"
	@scripts/con-apply.sh "$(PROFILE)" "$(NAME)"

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

# Build Discord driver (runs on host, not in container)
discord:
	go build -o con-discord ./drivers/discord/

# Run Go unit tests (fast, host-side)
test:
	go test ./... -v

# Run smoke tests inside the container
test-smoke:
	container exec $(NAME) bash /test/smoke/smoke_test.sh

# Run e2e tests inside the container (slow, needs LLM API key)
test-e2e:
	@for f in test/e2e/[0-9]*.sh; do \
		echo ""; echo ">>> $$f"; \
		container exec $(NAME) bash /$$f || true; \
	done

# Run unit + smoke (no LLM needed)
test-all: test test-smoke

# Clean
clean:
	rm -f con con-discord
