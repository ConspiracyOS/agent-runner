package main

import (
	"fmt"
	"log"
	"os"
	"os/exec"
	"os/signal"
	"strings"
	"sync"
	"syscall"
	"time"

	"github.com/bwmarrin/discordgo"
)

// Config holds the driver configuration loaded from environment variables.
type Config struct {
	BotToken  string
	ChannelID string // empty = DM mode
	SSHHost   string
	SSHPort   string
	SSHUser   string
	SSHKey    string
}

func loadConfig() Config {
	cfg := Config{
		BotToken:  os.Getenv("DISCORD_BOT_TOKEN"),
		ChannelID: os.Getenv("DISCORD_CHANNEL_ID"),
		SSHHost:   os.Getenv("CON_SSH_HOST"),
		SSHPort:   os.Getenv("CON_SSH_PORT"),
		SSHUser:   os.Getenv("CON_SSH_USER"),
		SSHKey:    os.Getenv("CON_SSH_KEY"),
	}
	if cfg.BotToken == "" {
		log.Fatal("DISCORD_BOT_TOKEN is required")
	}
	if cfg.SSHHost == "" {
		cfg.SSHHost = "localhost"
	}
	if cfg.SSHPort == "" {
		cfg.SSHPort = "22"
	}
	if cfg.SSHUser == "" {
		cfg.SSHUser = "root"
	}
	if cfg.SSHKey == "" {
		cfg.SSHKey = os.ExpandEnv("$HOME/.ssh/id_ed25519")
	}
	return cfg
}

// sshRun executes a command on the container via SSH and returns stdout.
func sshRun(cfg Config, cmd string) (string, error) {
	args := []string{
		"-o", "StrictHostKeyChecking=no",
		"-o", "BatchMode=yes",
		"-i", cfg.SSHKey,
		"-p", cfg.SSHPort,
		fmt.Sprintf("%s@%s", cfg.SSHUser, cfg.SSHHost),
		cmd,
	}
	out, err := exec.Command("ssh", args...).CombinedOutput()
	return strings.TrimSpace(string(out)), err
}

// responseTracker tracks which response files have already been posted.
type responseTracker struct {
	mu   sync.Mutex
	seen map[string]bool
}

func newResponseTracker() *responseTracker {
	return &responseTracker{seen: make(map[string]bool)}
}

func (rt *responseTracker) isNew(path string) bool {
	rt.mu.Lock()
	defer rt.mu.Unlock()
	if rt.seen[path] {
		return false
	}
	rt.seen[path] = true
	return true
}

// dmChannels tracks active DM channel IDs for response delivery.
type dmChannels struct {
	mu       sync.Mutex
	channels map[string]bool // channelID -> true
}

func newDMChannels() *dmChannels {
	return &dmChannels{channels: make(map[string]bool)}
}

func (d *dmChannels) add(channelID string) {
	d.mu.Lock()
	defer d.mu.Unlock()
	d.channels[channelID] = true
}

func (d *dmChannels) list() []string {
	d.mu.Lock()
	defer d.mu.Unlock()
	out := make([]string, 0, len(d.channels))
	for id := range d.channels {
		out = append(out, id)
	}
	return out
}

func main() {
	cfg := loadConfig()

	dg, err := discordgo.New("Bot " + cfg.BotToken)
	if err != nil {
		log.Fatalf("creating Discord session: %v", err)
	}

	// Intents: DM messages (no privileged intent needed) + guild messages if channel mode
	dg.Identify.Intents = discordgo.IntentsDirectMessages
	if cfg.ChannelID != "" {
		dg.Identify.Intents |= discordgo.IntentsGuildMessages | discordgo.IntentsMessageContent
	}

	tracker := newResponseTracker()
	dms := newDMChannels()

	// Seed the tracker with existing responses so we only post new ones
	seedResponses(cfg, tracker)

	// Message handler: Discord → conspiracy inbox
	dg.AddHandler(func(s *discordgo.Session, m *discordgo.MessageCreate) {
		// Ignore own messages
		if m.Author.ID == s.State.User.ID {
			return
		}
		// Ignore bot messages
		if m.Author.Bot {
			return
		}

		// Channel mode: only respond in the configured channel
		if cfg.ChannelID != "" && m.ChannelID != cfg.ChannelID {
			return
		}

		// DM mode: only respond to DMs
		if cfg.ChannelID == "" {
			ch, err := s.State.Channel(m.ChannelID)
			if err != nil {
				ch, err = s.Channel(m.ChannelID)
				if err != nil {
					return
				}
			}
			if ch.Type != discordgo.ChannelTypeDM {
				return
			}
			dms.add(m.ChannelID)
		}

		// Forward message to conspiracy
		message := m.Content
		if message == "" {
			return
		}

		// Escape single quotes for shell
		escaped := strings.ReplaceAll(message, "'", "'\\''")
		cmd := fmt.Sprintf("con task '%s'", escaped)

		_, err := sshRun(cfg, cmd)
		if err != nil {
			log.Printf("task failed: %v", err)
			s.MessageReactionAdd(m.ChannelID, m.ID, "\u274c") // cross mark
			return
		}

		s.MessageReactionAdd(m.ChannelID, m.ID, "\u2705") // check mark
		log.Printf("task from %s: %s", m.Author.Username, truncate(message, 80))
	})

	if err := dg.Open(); err != nil {
		log.Fatalf("opening Discord connection: %v", err)
	}
	defer dg.Close()

	mode := "DM"
	if cfg.ChannelID != "" {
		mode = fmt.Sprintf("channel %s", cfg.ChannelID)
	}
	log.Printf("discord driver started (%s mode), polling %s@%s:%s",
		mode, cfg.SSHUser, cfg.SSHHost, cfg.SSHPort)

	// Start response poller
	go pollResponses(dg, cfg, tracker, dms)

	// Block until signal
	sig := make(chan os.Signal, 1)
	signal.Notify(sig, syscall.SIGINT, syscall.SIGTERM)
	<-sig
	log.Println("shutting down")
}

// seedResponses marks all existing response files as seen so we don't replay history.
func seedResponses(cfg Config, tracker *responseTracker) {
	out, err := sshRun(cfg, "ls /srv/con/agents/*/outbox/*.response 2>/dev/null")
	if err != nil || out == "" {
		return
	}
	for _, path := range strings.Split(out, "\n") {
		path = strings.TrimSpace(path)
		if path != "" {
			tracker.isNew(path) // marks as seen
		}
	}
	log.Printf("seeded %d existing responses", len(tracker.seen))
}

// pollResponses checks for new response files and posts them to Discord.
func pollResponses(dg *discordgo.Session, cfg Config, tracker *responseTracker, dms *dmChannels) {
	for {
		time.Sleep(5 * time.Second)

		out, err := sshRun(cfg, "ls /srv/con/agents/*/outbox/*.response 2>/dev/null")
		if err != nil || out == "" {
			continue
		}

		for _, path := range strings.Split(out, "\n") {
			path = strings.TrimSpace(path)
			if path == "" || !tracker.isNew(path) {
				continue
			}

			// Extract agent name from path: /srv/con/agents/<name>/outbox/...
			agent := agentFromPath(path)

			content, err := sshRun(cfg, fmt.Sprintf("cat '%s'", path))
			if err != nil {
				log.Printf("reading response %s: %v", path, err)
				continue
			}

			if content == "" {
				continue
			}

			header := fmt.Sprintf("**%s:**\n", agent)
			sendResponse(dg, cfg, dms, header+content)
			log.Printf("posted response from %s (%d chars)", agent, len(content))
		}
	}
}

// sendResponse posts a message to the appropriate Discord destination.
func sendResponse(dg *discordgo.Session, cfg Config, dms *dmChannels, content string) {
	chunks := splitMessage(content, 2000)

	if cfg.ChannelID != "" {
		// Channel mode: post to configured channel
		for _, chunk := range chunks {
			dg.ChannelMessageSend(cfg.ChannelID, chunk)
		}
		return
	}

	// DM mode: post to all active DM channels
	for _, chID := range dms.list() {
		for _, chunk := range chunks {
			dg.ChannelMessageSend(chID, chunk)
		}
	}
}

// splitMessage splits content into chunks that fit Discord's 2000 char limit.
func splitMessage(content string, limit int) []string {
	if len(content) <= limit {
		return []string{content}
	}
	var chunks []string
	for len(content) > 0 {
		end := limit
		if end > len(content) {
			end = len(content)
		}
		// Try to split on newline
		if end < len(content) {
			if idx := strings.LastIndex(content[:end], "\n"); idx > 0 {
				end = idx + 1
			}
		}
		chunks = append(chunks, content[:end])
		content = content[end:]
	}
	return chunks
}

// agentFromPath extracts agent name from /srv/con/agents/<name>/outbox/...
func agentFromPath(path string) string {
	parts := strings.Split(path, "/")
	for i, p := range parts {
		if p == "agents" && i+1 < len(parts) {
			return parts[i+1]
		}
	}
	return "unknown"
}

func truncate(s string, n int) string {
	if len(s) <= n {
		return s
	}
	return s[:n] + "..."
}
