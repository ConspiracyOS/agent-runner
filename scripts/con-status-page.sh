#!/bin/bash
# con-status-page — Generate static HTML status page for ConspiracyOS
# Runs after each healthcheck (every 60s via ExecStartPost)
# Reads filesystem state directly — no subprocess calls to `con`

set -euo pipefail

OUTPUT="/srv/con/status/index.html"
TMPFILE="${OUTPUT}.tmp"
NOW=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
NOW_DISPLAY=$(date '+%H:%M:%S %Z')

# --- Data collection ---

HOSTNAME=$(hostname 2>/dev/null || echo "unknown")
UPTIME_SINCE=$(uptime -s 2>/dev/null || echo "unknown")
UPTIME_DAYS=$(( ( $(date +%s) - $(date -d "$UPTIME_SINCE" +%s 2>/dev/null || echo "0") ) / 86400 )) 2>/dev/null || UPTIME_DAYS="?"
LOAD=$(cat /proc/loadavg 2>/dev/null | cut -d' ' -f1-3 || echo "n/a")
DISK_USED=$(df -h / 2>/dev/null | awk 'NR==2{printf "%s/%s", $3, $2}' || echo "?")
MEM_USED=$(free -h 2>/dev/null | awk 'NR==2{printf "%s/%s", $3, $2}' || echo "?")

# Bootstrap age
BOOT_AGE="—"
if [ -f /srv/con/.bootstrapped ]; then
    boot_ts=$(stat -c '%Y' /srv/con/.bootstrapped 2>/dev/null || echo "0")
    age_s=$(( $(date +%s) - boot_ts ))
    if [ "$age_s" -lt 3600 ]; then
        BOOT_AGE="$((age_s / 60))m"
    elif [ "$age_s" -lt 86400 ]; then
        BOOT_AGE="$((age_s / 3600))h"
    else
        BOOT_AGE="$((age_s / 86400))d"
    fi
fi

# Tailscale
TSIP=""
TSHOSTNAME=""
if command -v tailscale &>/dev/null; then
    TSIP=$(tailscale ip -4 2>/dev/null || true)
    TSHOSTNAME=$(tailscale status --json 2>/dev/null | jq -r '.Self.HostName // empty' 2>/dev/null || true)
fi

# Agent data
AGENTS_ROWS=""
TOTAL_PENDING=0
TOTAL_PROCESSED=0
AGENT_COUNT=0
ACTIVE_COUNT=0

if [ -d /srv/con/agents ]; then
    for agent_dir in /srv/con/agents/*/; do
        [ -d "$agent_dir" ] || continue
        agent=$(basename "$agent_dir")
        svc="con-${agent}"
        AGENT_COUNT=$((AGENT_COUNT + 1))

        # Service state
        svc_state=$(systemctl is-active "${svc}.service" 2>/dev/null || echo "inactive")
        path_state=$(systemctl is-active "${svc}.path" 2>/dev/null || echo "inactive")
        timer_state=$(systemctl is-active "${svc}.timer" 2>/dev/null || echo "inactive")

        if [ "$svc_state" = "activating" ] || [ "$svc_state" = "active" ]; then
            state="running"
            badge="mark"
            ACTIVE_COUNT=$((ACTIVE_COUNT + 1))
        elif [ "$path_state" = "active" ] || [ "$timer_state" = "active" ]; then
            state="idle"
            badge=""
        else
            state="stopped"
            badge="del"
        fi

        # Pending / processed counts
        pending=0
        if [ -d "${agent_dir}inbox" ]; then
            pending=$(find "${agent_dir}inbox" -name "*.task" -type f 2>/dev/null | wc -l | tr -d ' ')
        fi
        processed=0
        if [ -d "${agent_dir}processed" ]; then
            processed=$(find "${agent_dir}processed" -name "*.task" -type f 2>/dev/null | wc -l | tr -d ' ')
        fi
        TOTAL_PENDING=$((TOTAL_PENDING + pending))
        TOTAL_PROCESSED=$((TOTAL_PROCESSED + processed))

        # Last active (newest file in processed/)
        last_active="—"
        newest=$(find "${agent_dir}processed" -name "*.task" -type f -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)
        if [ -n "$newest" ]; then
            last_active=$(stat -c '%y' "$newest" 2>/dev/null | cut -d'.' -f1 || echo "—")
        fi

        # Last response preview (newest .response in outbox, first 120 chars)
        response_preview=""
        newest_resp=$(find "${agent_dir}outbox" -name "*.response" -type f -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)
        if [ -n "$newest_resp" ] && [ -s "$newest_resp" ]; then
            response_preview=$(head -3 "$newest_resp" 2>/dev/null | tr '\n' ' ' | cut -c1-120)
        fi

        # Workspace size
        ws_size=$(du -sh "${agent_dir}workspace" 2>/dev/null | cut -f1 || echo "—")

        # State display with badge
        if [ -n "$badge" ]; then
            state_html="<${badge}>${state}</${badge}>"
        else
            state_html="${state}"
        fi

        resp_cell=""
        if [ -n "$response_preview" ]; then
            resp_cell="<td class=dim>${response_preview}</td>"
        else
            resp_cell="<td class=dim>—</td>"
        fi

        AGENTS_ROWS="${AGENTS_ROWS}<tr><td><b>${agent}</b></td><td>${state_html}</td><td>${pending}</td><td>${processed}</td><td class=dim>${last_active}</td><td>${ws_size}</td>${resp_cell}</tr>"
    done
fi

# Contract results — parse last run
PASS_COUNT=0
FAIL_COUNT=0
CONTRACTS_ROWS=""
CONTRACTS_LOG="/srv/con/logs/audit/contracts.log"
if [ -f "$CONTRACTS_LOG" ]; then
    while IFS= read -r line; do
        [ -z "$line" ] && continue

        if echo "$line" | grep -q "PASS"; then
            result="PASS"
            PASS_COUNT=$((PASS_COUNT + 1))
        elif echo "$line" | grep -q "FAIL"; then
            result="FAIL"
            FAIL_COUNT=$((FAIL_COUNT + 1))
        else
            continue
        fi

        cid=$(echo "$line" | grep -oP 'CON-[A-Z]+-\d+[a-z]?' 2>/dev/null || echo "")
        detail=$(echo "$line" | sed 's/.*\(PASS\|FAIL\)//' | sed 's/^ *//')

        if [ "$result" = "PASS" ]; then
            CONTRACTS_ROWS="${CONTRACTS_ROWS}<tr><td>${cid}</td><td><mark>${result}</mark></td><td class=dim>${detail}</td></tr>"
        else
            CONTRACTS_ROWS="${CONTRACTS_ROWS}<tr><td>${cid}</td><td><del>${result}</del></td><td class=dim>${detail}</td></tr>"
        fi
    done < <(tail -20 "$CONTRACTS_LOG" 2>/dev/null)
fi

CONTRACT_TOTAL=$((PASS_COUNT + FAIL_COUNT))

# Recent tasks
RECENT_ROWS=""
RECENT_TASKS=$(find /srv/con/agents/*/processed -name "*.task" -type f -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -8)
if [ -n "$RECENT_TASKS" ]; then
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        filepath=$(echo "$line" | cut -d' ' -f2-)
        agent=$(echo "$filepath" | sed 's|.*/agents/\([^/]*\)/.*|\1|')
        mtime=$(stat -c '%y' "$filepath" 2>/dev/null | cut -d'.' -f1 || echo "?")
        summary=$(head -1 "$filepath" 2>/dev/null | cut -c1-120 || echo "")
        RECENT_ROWS="${RECENT_ROWS}<tr><td class=dim>${mtime}</td><td>${agent}</td><td>${summary}</td></tr>"
    done <<< "$RECENT_TASKS"
fi

# Audit log tail (last 8 entries)
LOG_ROWS=""
for logfile in /srv/con/logs/audit/*.log; do
    [ -f "$logfile" ] || continue
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        # Color PASS/FAIL/WARN
        colored=$(echo "$line" | sed \
            -e 's/PASS/<mark>PASS<\/mark>/g' \
            -e 's/FAIL/<del>FAIL<\/del>/g' \
            -e 's/WARN/<b class=warn>WARN<\/b>/g')
        LOG_ROWS="${LOG_ROWS}<div>${colored}</div>"
    done < <(tail -8 "$logfile" 2>/dev/null)
done

# Health summary
if [ "$FAIL_COUNT" -gt 0 ]; then
    HEALTH_SUMMARY="<del>${FAIL_COUNT} fail</del> ${PASS_COUNT} pass"
elif [ "$CONTRACT_TOTAL" -gt 0 ]; then
    HEALTH_SUMMARY="<mark>${PASS_COUNT}/${CONTRACT_TOTAL} pass</mark>"
else
    HEALTH_SUMMARY="none"
fi

# --- HTML generation ---

cat > "$TMPFILE" << HTMLEOF
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta http-equiv="refresh" content="60">
<title>${HOSTNAME} — ConspiracyOS</title>
<style>
*{margin:0;padding:0;box-sizing:border-box}
html{font-family:system-ui,-apple-system,sans-serif;font-size:13px;line-height:1.4;
  color:#e5e7eb;background:#111827}
header{padding:10px 16px;background:#1f2937;border-bottom:1px solid #374151;
  display:flex;justify-content:space-between;align-items:baseline}
header h1{font-size:15px;font-weight:600}
header span{font-size:12px;color:#9ca3af}
main{max-width:1100px;margin:0 auto;padding:8px 16px 24px}
h2{font-size:13px;font-weight:600;color:#9ca3af;text-transform:uppercase;
  letter-spacing:.06em;margin:12px 0 4px;padding-bottom:3px;border-bottom:1px solid #1f2937}
table{width:100%;border-collapse:collapse}
th{text-align:left;font-weight:500;color:#6b7280;padding:3px 8px 3px 0;font-size:12px}
td{padding:3px 8px 3px 0;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;max-width:320px}
td:last-child{max-width:none;white-space:normal}
tr:hover{background:rgba(255,255,255,.03)}
b{font-weight:600}
.dim{color:#6b7280}
.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(130px,1fr));gap:6px;margin:8px 0}
.card{padding:6px 10px;background:#1f2937;border-radius:4px}
.card .l{font-size:11px;color:#6b7280}
.card .v{font-size:16px;font-weight:600}
mark{background:#065f46;color:#d1fae5;padding:1px 5px;border-radius:2px;font-size:12px}
del{text-decoration:none;background:#7f1d1d;color:#fecaca;padding:1px 5px;border-radius:2px;font-size:12px}
b.warn{color:#f59e0b;font-weight:600}
details summary{cursor:pointer;font-weight:500;font-size:13px;color:#9ca3af}
.log{font-family:ui-monospace,monospace;font-size:12px;line-height:1.6;
  background:#1f2937;padding:6px 10px;border-radius:4px;max-height:200px;overflow-y:auto}
.log div{white-space:pre-wrap;word-break:break-all}
footer{text-align:center;font-size:11px;color:#4b5563;padding:12px}
@media(prefers-color-scheme:light){
  html{color:#1f2937;background:#f9fafb}
  header{background:#fff;border-color:#e5e7eb}
  h2{border-color:#e5e7eb;color:#6b7280}
  .card{background:#fff;border:1px solid #e5e7eb}
  .log{background:#fff;border:1px solid #e5e7eb}
  tr:hover{background:rgba(0,0,0,.02)}
  .dim{color:#9ca3af}
}
</style>
</head>
<body>
<header>
  <h1>${HOSTNAME}</h1>
  <span>up ${UPTIME_DAYS}d &middot; boot ${BOOT_AGE} ago &middot; ${NOW_DISPLAY}</span>
</header>
<main>

<div class="grid">
  <div class="card"><div class="l">agents</div><div class="v">${ACTIVE_COUNT}/${AGENT_COUNT}</div></div>
  <div class="card"><div class="l">pending</div><div class="v">${TOTAL_PENDING}</div></div>
  <div class="card"><div class="l">processed</div><div class="v">${TOTAL_PROCESSED}</div></div>
  <div class="card"><div class="l">contracts</div><div class="v">${HEALTH_SUMMARY}</div></div>
  <div class="card"><div class="l">load</div><div class="v">${LOAD}</div></div>
  <div class="card"><div class="l">disk</div><div class="v">${DISK_USED}</div></div>
  <div class="card"><div class="l">memory</div><div class="v">${MEM_USED}</div></div>
HTMLEOF

if [ -n "$TSIP" ]; then
    echo "  <div class=\"card\"><div class=\"l\">tailscale</div><div class=\"v\">${TSHOSTNAME}</div></div>" >> "$TMPFILE"
fi

echo '</div>' >> "$TMPFILE"

# Agents table
if [ -n "$AGENTS_ROWS" ]; then
    cat >> "$TMPFILE" << HTMLEOF
<h2>Agents</h2>
<table>
<tr><th>Name</th><th>State</th><th>Pend</th><th>Done</th><th>Last active</th><th>Disk</th><th>Last response</th></tr>
${AGENTS_ROWS}
</table>
HTMLEOF
fi

# Contracts
if [ "$CONTRACT_TOTAL" -gt 0 ]; then
    if [ "$FAIL_COUNT" -gt 0 ]; then
        cat >> "$TMPFILE" << HTMLEOF
<h2>Contracts</h2>
<table>
<tr><th>ID</th><th>Result</th><th>Detail</th></tr>
${CONTRACTS_ROWS}
</table>
HTMLEOF
    else
        cat >> "$TMPFILE" << HTMLEOF
<details>
<summary>Contracts — all ${PASS_COUNT} passing</summary>
<table>
<tr><th>ID</th><th>Result</th><th>Detail</th></tr>
${CONTRACTS_ROWS}
</table>
</details>
HTMLEOF
    fi
fi

# Recent tasks
if [ -n "$RECENT_ROWS" ]; then
    cat >> "$TMPFILE" << HTMLEOF
<h2>Recent tasks</h2>
<table>
<tr><th>Time</th><th>Agent</th><th>Summary</th></tr>
${RECENT_ROWS}
</table>
HTMLEOF
fi

# Audit log tail
if [ -n "$LOG_ROWS" ]; then
    cat >> "$TMPFILE" << HTMLEOF
<h2>Audit log</h2>
<div class="log">
${LOG_ROWS}
</div>
HTMLEOF
fi

cat >> "$TMPFILE" << HTMLEOF
</main>
<footer>${NOW}</footer>
</body>
</html>
HTMLEOF

mv "$TMPFILE" "$OUTPUT"
