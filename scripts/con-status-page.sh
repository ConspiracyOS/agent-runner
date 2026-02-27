#!/bin/bash
# con-status-page — Generate static HTML status page for ConspiracyOS
# Runs after each healthcheck (every 60s via ExecStartPost)
# Reads filesystem state directly — no subprocess calls to `con`

set -euo pipefail

OUTPUT="/srv/con/status/index.html"
TMPFILE="${OUTPUT}.tmp"
NOW=$(date '+%Y-%m-%d %H:%M:%S %Z')

# --- Data collection ---

# System info
HOSTNAME=$(hostname 2>/dev/null || echo "unknown")
UPTIME_SINCE=$(uptime -s 2>/dev/null || echo "unknown")
LOAD=$(cat /proc/loadavg 2>/dev/null | cut -d' ' -f1-3 || echo "n/a")
DISK_USAGE=$(df -h / 2>/dev/null | awk 'NR==2{printf "%s / %s (%s used)", $3, $2, $5}' || echo "n/a")
MEM_INFO=$(free -h 2>/dev/null | awk 'NR==2{printf "%s / %s (%s free)", $3, $2, $4}' || echo "n/a")

# Agent states
AGENTS_HTML=""
if [ -d /srv/con/agents ]; then
    for agent_dir in /srv/con/agents/*/; do
        [ -d "$agent_dir" ] || continue
        agent=$(basename "$agent_dir")
        svc="con-${agent}"

        # Service state
        path_state=$(systemctl is-active "${svc}.path" 2>/dev/null || echo "inactive")
        svc_state=$(systemctl is-active "${svc}.service" 2>/dev/null || echo "inactive")
        timer_state=$(systemctl is-active "${svc}.timer" 2>/dev/null || echo "inactive")

        # Determine overall state and color
        if [ "$svc_state" = "activating" ] || [ "$svc_state" = "active" ]; then
            state="RUNNING"
            color="#00ff41"
        elif [ "$path_state" = "active" ] || [ "$timer_state" = "active" ]; then
            state="WATCHING"
            color="#00ff41"
        else
            state="INACTIVE"
            color="#ff4444"
        fi

        # Count pending tasks
        pending=0
        if [ -d "${agent_dir}inbox" ]; then
            pending=$(find "${agent_dir}inbox" -name "*.task" -type f 2>/dev/null | wc -l | tr -d ' ')
        fi

        # Count processed tasks
        processed=0
        if [ -d "${agent_dir}processed" ]; then
            processed=$(find "${agent_dir}processed" -name "*.task" -type f 2>/dev/null | wc -l | tr -d ' ')
        fi

        AGENTS_HTML="${AGENTS_HTML}
    <tr>
      <td>${agent}</td>
      <td style=\"color:${color}\">${state}</td>
      <td>${pending}</td>
      <td>${processed}</td>
    </tr>"
    done
fi

# Healthcheck results
CONTRACTS_HTML=""
CONTRACTS_LOG="/srv/con/logs/audit/contracts.log"
if [ -f "$CONTRACTS_LOG" ]; then
    # Get the last healthcheck block (lines from the last run)
    CONTRACTS_HTML=$(tail -20 "$CONTRACTS_LOG" 2>/dev/null | while IFS= read -r line; do
        if echo "$line" | grep -q "PASS\|ok\|✓"; then
            echo "    <div style=\"color:#00ff41\">${line}</div>"
        elif echo "$line" | grep -q "FAIL\|WARN\|✗\|⚠"; then
            echo "    <div style=\"color:#ff4444\">${line}</div>"
        else
            echo "    <div>${line}</div>"
        fi
    done)
fi
[ -z "$CONTRACTS_HTML" ] && CONTRACTS_HTML="    <div style=\"color:#666\">No healthcheck results yet</div>"

# Recent tasks (last 10 across all agents by mtime)
RECENT_HTML=""
RECENT_TASKS=$(find /srv/con/agents/*/processed -name "*.task" -type f -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -10)
if [ -n "$RECENT_TASKS" ]; then
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        filepath=$(echo "$line" | cut -d' ' -f2-)
        agent=$(echo "$filepath" | sed 's|.*/agents/\([^/]*\)/.*|\1|')
        filename=$(basename "$filepath")
        mtime=$(stat -c '%y' "$filepath" 2>/dev/null | cut -d'.' -f1 || echo "unknown")
        # Read first line of task for summary
        summary=$(head -1 "$filepath" 2>/dev/null | cut -c1-80 || echo "")
        RECENT_HTML="${RECENT_HTML}
    <tr>
      <td>${mtime}</td>
      <td>${agent}</td>
      <td>${filename}</td>
      <td>${summary}</td>
    </tr>"
    done <<< "$RECENT_TASKS"
fi
[ -z "$RECENT_HTML" ] && RECENT_HTML="
    <tr><td colspan=\"4\" style=\"color:#666\">No processed tasks yet</td></tr>"

# Tailscale status
TAILSCALE_HTML=""
if command -v tailscale &>/dev/null; then
    TSIP=$(tailscale ip -4 2>/dev/null || true)
    if [ -n "$TSIP" ]; then
        TSSTATUS=$(tailscale status --json 2>/dev/null | jq -r '.Self.HostName // "unknown"' 2>/dev/null || echo "unknown")
        TAILSCALE_HTML="
  <h2>// TAILSCALE</h2>
  <div>Status: <span style=\"color:#00ff41\">CONNECTED</span></div>
  <div>IP: ${TSIP}</div>
  <div>Hostname: ${TSSTATUS}</div>"
    fi
fi

# --- HTML generation ---

cat > "$TMPFILE" << HTMLEOF
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta http-equiv="refresh" content="60">
  <title>ConspiracyOS — ${HOSTNAME}</title>
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body {
      background: #1a1a2e;
      color: #e0e0e0;
      font-family: 'Courier New', monospace;
      font-size: 14px;
      padding: 20px;
      line-height: 1.5;
    }
    h1 {
      color: #00ff41;
      font-size: 18px;
      margin-bottom: 4px;
    }
    h2 {
      color: #00aaff;
      font-size: 14px;
      margin-top: 20px;
      margin-bottom: 8px;
    }
    .header-meta {
      color: #666;
      font-size: 12px;
      margin-bottom: 16px;
    }
    table {
      border-collapse: collapse;
      width: 100%;
      margin-bottom: 8px;
    }
    th {
      text-align: left;
      color: #888;
      border-bottom: 1px solid #333;
      padding: 4px 12px 4px 0;
      font-weight: normal;
    }
    td {
      padding: 3px 12px 3px 0;
      white-space: nowrap;
      overflow: hidden;
      text-overflow: ellipsis;
      max-width: 400px;
    }
    .contracts-box {
      background: #16213e;
      padding: 10px;
      border-left: 2px solid #333;
      font-size: 13px;
      overflow-x: auto;
    }
  </style>
</head>
<body>
  <h1>ConspiracyOS // ${HOSTNAME}</h1>
  <div class="header-meta">Generated: ${NOW} | Up since: ${UPTIME_SINCE}</div>

  <h2>// SYSTEM</h2>
  <div>Load: ${LOAD}</div>
  <div>Disk: ${DISK_USAGE}</div>
  <div>Memory: ${MEM_INFO}</div>

  <h2>// AGENTS</h2>
  <table>
    <tr><th>Agent</th><th>State</th><th>Pending</th><th>Processed</th></tr>${AGENTS_HTML}
  </table>

  <h2>// CONTRACTS</h2>
  <div class="contracts-box">
${CONTRACTS_HTML}
  </div>

  <h2>// RECENT TASKS</h2>
  <table>
    <tr><th>Time</th><th>Agent</th><th>File</th><th>Summary</th></tr>${RECENT_HTML}
  </table>
${TAILSCALE_HTML}
</body>
</html>
HTMLEOF

mv "$TMPFILE" "$OUTPUT"
