#!/bin/bash
# ─────────────────────────────────────────────
# VELA Health Check
# Runs every 15 minutes via cron
# Alerts Greg via Telegram if anything is wrong
# ─────────────────────────────────────────────

CONFIG_FILE="$HOME/.openclaw/vela_client.conf"

if [ ! -f "$CONFIG_FILE" ]; then
  echo "ERROR: vela_client.conf not found at $CONFIG_FILE"
  exit 1
fi

source "$CONFIG_FILE"

GATEWAY_HOST="127.0.0.1"
GATEWAY_PORT="18789"
LOG_FILE="$HOME/.openclaw/logs/health_check.log"
ALERT_FLAG_DIR="$HOME/.openclaw/health_flags"
mkdir -p "$ALERT_FLAG_DIR"

timestamp() { date '+%Y-%m-%d %H:%M:%S'; }
log() { echo "[$(timestamp)] $1" >> "$LOG_FILE"; }

send_alert() {
  local message="$1"
  local flag_file="$ALERT_FLAG_DIR/$2.flag"
  if [ -f "$flag_file" ]; then log "Alert suppressed: $2"; return; fi
  touch "$flag_file"
  curl -s -X POST "https://api.telegram.org/bot${ALERT_BOT_TOKEN}/sendMessage" \
    -d chat_id="${ALERT_CHAT_ID}" \
    -d parse_mode="HTML" \
    -d text="🚨 <b>VELA Alert — ${CLIENT_NAME}</b>%0A%0A${message}%0A%0A<i>$(timestamp)</i>" > /dev/null 2>&1
  log "Alert sent: $2"
}

clear_alert() {
  local flag_file="$ALERT_FLAG_DIR/$1.flag"
  if [ -f "$flag_file" ]; then rm "$flag_file"; log "Alert cleared: $1"; fi
}

send_recovery() {
  curl -s -X POST "https://api.telegram.org/bot${ALERT_BOT_TOKEN}/sendMessage" \
    -d chat_id="${ALERT_CHAT_ID}" \
    -d parse_mode="HTML" \
    -d text="✅ <b>VELA Recovered — ${CLIENT_NAME}</b>%0A%0A$1%0A%0A<i>$(timestamp)</i>" > /dev/null 2>&1
}

log "--- Health check started ---"
ALL_OK=true

# Gateway process
if pgrep -f "openclaw" > /dev/null 2>&1; then
  log "✓ Gateway process: running"
  clear_alert "gateway_process"
else
  log "✗ Gateway process: NOT running"
  send_alert "Gateway process is not running. Hannah is offline." "gateway_process"
  ALL_OK=false
fi

# Gateway port
if nc -z -w3 "$GATEWAY_HOST" "$GATEWAY_PORT" > /dev/null 2>&1; then
  log "✓ Gateway port $GATEWAY_PORT: responding"
  clear_alert "gateway_port"
else
  log "✗ Gateway port $GATEWAY_PORT: NOT responding"
  send_alert "Gateway port $GATEWAY_PORT is not responding." "gateway_port"
  ALL_OK=false
fi

# Disk space
DISK_USAGE=$(df -h "$HOME" | awk 'NR==2 {print $5}' | tr -d '%')
if [ "$DISK_USAGE" -lt 85 ]; then
  log "✓ Disk usage: ${DISK_USAGE}%"
  clear_alert "disk_space"
else
  log "✗ Disk usage: ${DISK_USAGE}% (HIGH)"
  send_alert "Disk usage is at ${DISK_USAGE}%." "disk_space"
  ALL_OK=false
fi

# API key
if grep -q "sk-ant-" "$HOME/.openclaw/.env" > /dev/null 2>&1; then
  log "✓ API key: present"
  clear_alert "api_key"
else
  log "✗ API key: NOT found"
  send_alert "Anthropic API key not found. All agents offline." "api_key"
  ALL_OK=false
fi

$ALL_OK && log "✓ All checks passed" || log "✗ One or more checks failed"
log "--- Health check complete ---"
