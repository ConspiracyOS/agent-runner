.PHONY: build test clean linux linux-arm64 image run stop task deploy watcher outer-task

# Build for current platform
build:
	go build -o con ./cmd/conctl/

# Build for Linux (amd64) — for Containerfile
linux:
	GOOS=linux GOARCH=amd64 go build -o con ./cmd/conctl/

# Build for Linux (arm64) — for Pi / Apple Silicon Container
linux-arm64:
	GOOS=linux GOARCH=arm64 go build -o con ./cmd/conctl/

# Build container image (Apple Silicon)
# Usage: make image            — uses default profile (Concierge + Sysadmin)
#        make image PROFILE=minimal — uses minimal profile (Concierge only)
image: linux-arm64
	container build --dns 8.8.8.8 -t conspiracyos --build-arg CON_PROFILE=$(or $(PROFILE),default) -f Containerfile .

# Run the conspiracy (reads .env for secrets)
run:
	container run --name conspiracyos --env-file .env conspiracyos

# Stop the conspiracy
stop:
	container stop conspiracyos && container rm conspiracyos

# Drop a task into the running container's outer inbox
# Usage: make task MSG="what agents are available?"
task:
	@if [ -z "$(MSG)" ]; then echo "Usage: make task MSG=\"your message\""; exit 1; fi
	@TASKID=$$(date +%s); \
	container exec conspiracyos sh -c "printf '%s' '$(MSG)' > /srv/con/inbox/$${TASKID}.task && chown a-concierge:agents /srv/con/inbox/$${TASKID}.task" && \
	echo "Task $${TASKID}.task dropped into inbox"

# Deploy: rebuild image and restart container (Apple Container has no cp command)
deploy: image
	-container kill conspiracyos 2>/dev/null; container rm conspiracyos 2>/dev/null
	container run --name conspiracyos --env-file .env conspiracyos

# Start the outer watcher (Claude Code researcher <-> inner agents)
watcher:
	./os/scripts/watcher.sh

# Send a task to the outer Claude researcher
# Usage: make outer-task MSG="how is network configured?"
outer-task:
	@if [ -z "$(MSG)" ]; then echo "Usage: make outer-task MSG=\"your message\""; exit 1; fi
	@TASKID=$$(date +%s); \
	printf '%s' '$(MSG)' > os/inbox/$${TASKID}.task && \
	echo "Task $${TASKID}.task dropped into os/inbox"

# Run all tests
test:
	go test ./... -v

# Clean
clean:
	rm -f con
