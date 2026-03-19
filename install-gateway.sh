#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# VELA Executive Intelligence Systems — Gateway Install Script
# vela_scripts/install-gateway.sh
#
# Provisions an OpenClaw gateway instance for a VELA client on macOS.
# Handles: plist generation (KeepAlive/RunAtLoad), port registry,
#          Uptime Kuma monitor creation, and Tailscale SSH verification.
#
# Usage:
#   ./install-gateway.sh --name <client-name> [options]
#
# Examples:
#   ./install-gateway.sh --name greg-primary
#   ./install-gateway.sh --name client-marcus --port 18790
#   ./install-gateway.sh --name client-diana --port 18791 --config ~/.openclaw/clients/diana.json
#
# Requirements: macOS with Homebrew, OpenClaw installed, Tailscale installed
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

# ── Defaults ─────────────────────────────────────────────────────────────────
REGISTRY_FILE="$HOME/.openclaw/vela-port-registry.json"
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
OPENCLAW_BIN="/opt/homebrew/lib/node_modules/openclaw/dist/index.js"
NODE_BIN="/opt/homebrew/opt/node/bin/node"
LOG_DIR="/tmp/openclaw"

# Uptime Kuma defaults (override with env vars or flags)
KUMA_URL="${VELA_KUMA_URL:-}"
KUMA_USERNAME="${VELA_KUMA_USERNAME:-}"
KUMA_PASSWORD="${VELA_KUMA_PASSWORD:-}"

# ── Color helpers ────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

info()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
fatal() { error "$*"; exit 1; }

# ── Usage ────────────────────────────────────────────────────────────────────
usage() {
  cat <<EOF
${BOLD}VELA Gateway Installer${NC}

Usage: $(basename "$0") --name <client-name> [options]

Required:
  --name <name>         Client/instance identifier (e.g., greg-primary, client-marcus)

Optional:
  --port <port>         Gateway port (auto-assigned from registry if omitted)
  --config <path>       OpenClaw config file (default: ~/.openclaw/openclaw.json)
  --kuma-url <url>      Uptime Kuma API URL (or set VELA_KUMA_URL env var)
  --kuma-user <user>    Uptime Kuma username (or set VELA_KUMA_USERNAME env var)
  --kuma-pass <pass>    Uptime Kuma password (or set VELA_KUMA_PASSWORD env var)
  --skip-kuma           Skip Uptime Kuma monitor creation
  --skip-tailscale      Skip Tailscale SSH verification
  --dry-run             Show what would be done without making changes
  --uninstall           Remove the gateway instance
  -h, --help            Show this help

Environment variables:
  VELA_KUMA_URL         Uptime Kuma push/API URL
  VELA_KUMA_USERNAME    Uptime Kuma username
  VELA_KUMA_PASSWORD    Uptime Kuma password
EOF
  exit 0
}

# ── Argument parsing ─────────────────────────────────────────────────────────
CLIENT_NAME=""
PORT=""
CONFIG_FILE="$HOME/.openclaw/openclaw.json"
SKIP_KUMA=false
SKIP_TAILSCALE=false
DRY_RUN=false
UNINSTALL=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --name)       CLIENT_NAME="$2"; shift 2 ;;
    --port)       PORT="$2"; shift 2 ;;
    --config)     CONFIG_FILE="$2"; shift 2 ;;
    --kuma-url)   KUMA_URL="$2"; shift 2 ;;
    --kuma-user)  KUMA_USERNAME="$2"; shift 2 ;;
    --kuma-pass)  KUMA_PASSWORD="$2"; shift 2 ;;
    --skip-kuma)  SKIP_KUMA=true; shift ;;
    --skip-tailscale) SKIP_TAILSCALE=true; shift ;;
    --dry-run)    DRY_RUN=true; shift ;;
    --uninstall)  UNINSTALL=true; shift ;;
    -h|--help)    usage ;;
    *) fatal "Unknown option: $1. Use --help for usage." ;;
  esac
done

[[ -z "$CLIENT_NAME" ]] && fatal "Missing required --name argument. Use --help for usage."

# Sanitize client name for use in service identifiers
SERVICE_NAME="ai.openclaw.gateway.${CLIENT_NAME}"
PLIST_FILE="${LAUNCH_AGENTS_DIR}/${SERVICE_NAME}.plist"
UID_NUM=$(id -u)

# ── Preflight checks ────────────────────────────────────────────────────────
preflight() {
  info "Running preflight checks..."

  # macOS check
  [[ "$(uname)" == "Darwin" ]] || fatal "This script requires macOS."

  # Node
  [[ -x "$NODE_BIN" ]] || fatal "Node not found at $NODE_BIN. Install via: brew install node"

  # OpenClaw
  [[ -f "$OPENCLAW_BIN" ]] || fatal "OpenClaw not found at $OPENCLAW_BIN. Install via: npm install -g openclaw"

  # Config file
  [[ -f "$CONFIG_FILE" ]] || fatal "Config file not found: $CONFIG_FILE"

  # LaunchAgents directory
  mkdir -p "$LAUNCH_AGENTS_DIR"
  mkdir -p "$LOG_DIR"
  mkdir -p "$(dirname "$REGISTRY_FILE")"

  ok "Preflight checks passed"
}

# ── Port Registry ────────────────────────────────────────────────────────────
init_registry() {
  if [[ ! -f "$REGISTRY_FILE" ]]; then
    echo '{"instances":[],"_meta":{"created":"'"$(date -u +%Y-%m-%dT%H:%M:%SZ)"'","version":"1.0"}}' > "$REGISTRY_FILE"
    info "Created port registry at $REGISTRY_FILE"
  fi
}

get_next_port() {
  # Base port is 18789, each new instance increments by 1
  local max_port
  max_port=$(python3 -c "
import json, sys
try:
    with open('$REGISTRY_FILE') as f:
        reg = json.load(f)
    ports = [inst['port'] for inst in reg.get('instances', [])]
    print(max(ports) if ports else 18788)
except:
    print(18788)
")
  echo $((max_port + 1))
}

check_port_conflict() {
  local port="$1"
  # Check registry
  local conflict
  conflict=$(python3 -c "
import json
try:
    with open('$REGISTRY_FILE') as f:
        reg = json.load(f)
    for inst in reg.get('instances', []):
        if inst['port'] == $port and inst['name'] != '$CLIENT_NAME':
            print(inst['name'])
            break
except:
    pass
")
  if [[ -n "$conflict" ]]; then
    fatal "Port $port already assigned to '$conflict' in registry."
  fi

  # Check if port is actually in use
  if lsof -i :"$port" -sTCP:LISTEN &>/dev/null; then
    warn "Port $port is currently in use by another process."
    lsof -i :"$port" -sTCP:LISTEN | head -3
    echo ""
    read -rp "Continue anyway? (y/N) " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || fatal "Aborted."
  fi
}

register_instance() {
  local port="$1"
  python3 -c "
import json
from datetime import datetime, timezone

with open('$REGISTRY_FILE') as f:
    reg = json.load(f)

# Remove existing entry for this client name (idempotent)
reg['instances'] = [i for i in reg.get('instances', []) if i['name'] != '$CLIENT_NAME']

reg['instances'].append({
    'name': '$CLIENT_NAME',
    'port': $port,
    'config': '$CONFIG_FILE',
    'service': '$SERVICE_NAME',
    'plist': '$PLIST_FILE',
    'installed_at': datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
})

reg['instances'].sort(key=lambda x: x['port'])

with open('$REGISTRY_FILE', 'w') as f:
    json.dump(reg, f, indent=2)
"
  ok "Registered $CLIENT_NAME on port $port in registry"
}

deregister_instance() {
  python3 -c "
import json
with open('$REGISTRY_FILE') as f:
    reg = json.load(f)
reg['instances'] = [i for i in reg.get('instances', []) if i['name'] != '$CLIENT_NAME']
with open('$REGISTRY_FILE', 'w') as f:
    json.dump(reg, f, indent=2)
" 2>/dev/null || true
  ok "Removed $CLIENT_NAME from registry"
}

# ── Plist Generation ─────────────────────────────────────────────────────────
generate_plist() {
  local port="$1"

  cat > "$PLIST_FILE" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${SERVICE_NAME}</string>

    <key>ProgramArguments</key>
    <array>
        <string>${NODE_BIN}</string>
        <string>${OPENCLAW_BIN}</string>
        <string>gateway</string>
        <string>--port</string>
        <string>${port}</string>
    </array>

    <key>EnvironmentVariables</key>
    <dict>
        <key>OPENCLAW_GATEWAY_PORT</key>
        <string>${port}</string>
        <key>OPENCLAW_CONFIG</key>
        <string>${CONFIG_FILE}</string>
        <key>PATH</key>
        <string>/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
    </dict>

    <!-- Auto-start on login -->
    <key>RunAtLoad</key>
    <true/>

    <!-- Auto-restart if process dies for ANY reason -->
    <key>KeepAlive</key>
    <true/>

    <!-- Throttle restarts: wait 10s between crash-restart cycles -->
    <key>ThrottleInterval</key>
    <integer>10</integer>

    <!-- Logging -->
    <key>StandardOutPath</key>
    <string>${LOG_DIR}/${CLIENT_NAME}-stdout.log</string>
    <key>StandardErrorPath</key>
    <string>${LOG_DIR}/${CLIENT_NAME}-stderr.log</string>

    <!-- Working directory -->
    <key>WorkingDirectory</key>
    <string>${HOME}</string>

    <!-- Resource limits -->
    <key>SoftResourceLimits</key>
    <dict>
        <key>NumberOfFiles</key>
        <integer>4096</integer>
    </dict>
    <key>HardResourceLimits</key>
    <dict>
        <key>NumberOfFiles</key>
        <integer>8192</integer>
    </dict>
</dict>
</plist>
PLIST

  ok "Generated plist at $PLIST_FILE"
  info "  KeepAlive: true (auto-restart on crash/signal)"
  info "  RunAtLoad: true (auto-start on login)"
  info "  ThrottleInterval: 10s (prevents restart storms)"
}

# ── Service Management ───────────────────────────────────────────────────────
load_service() {
  # Unload if already loaded (idempotent)
  launchctl bootout "gui/${UID_NUM}/${SERVICE_NAME}" 2>/dev/null || true
  sleep 1

  # Load and start
  launchctl bootstrap "gui/${UID_NUM}" "$PLIST_FILE"
  ok "Service loaded: $SERVICE_NAME"

  # Wait for startup
  info "Waiting for gateway to start..."
  local attempts=0
  local max_attempts=15
  while [[ $attempts -lt $max_attempts ]]; do
    if lsof -i :"$PORT" -sTCP:LISTEN &>/dev/null; then
      ok "Gateway is listening on port $PORT (PID $(lsof -ti :"$PORT" -sTCP:LISTEN))"
      return 0
    fi
    sleep 1
    attempts=$((attempts + 1))
  done

  warn "Gateway did not start within ${max_attempts}s. Check logs:"
  warn "  tail -50 ${LOG_DIR}/${CLIENT_NAME}-stderr.log"
  return 1
}

unload_service() {
  launchctl bootout "gui/${UID_NUM}/${SERVICE_NAME}" 2>/dev/null || true
  ok "Service unloaded: $SERVICE_NAME"
}

# ── Uptime Kuma ──────────────────────────────────────────────────────────────
setup_kuma_monitor() {
  local port="$1"

  if [[ "$SKIP_KUMA" == true ]]; then
    info "Skipping Uptime Kuma monitor setup (--skip-kuma)"
    return 0
  fi

  if [[ -z "$KUMA_URL" ]]; then
    warn "No Uptime Kuma URL configured. Set VELA_KUMA_URL or pass --kuma-url."
    warn "Skipping monitor creation. You can add it manually later."
    echo ""
    info "Manual setup in Uptime Kuma:"
    info "  Monitor Name: Hannah-${CLIENT_NAME}"
    info "  Type: TCP Port"
    info "  Hostname: 127.0.0.1 (or Tailscale IP)"
    info "  Port: ${port}"
    info "  Heartbeat Interval: 60s"
    return 0
  fi

  info "Creating Uptime Kuma monitor for ${CLIENT_NAME}..."

  # Get Tailscale IP for monitoring (prefer Tailscale IP over localhost)
  local monitor_host="127.0.0.1"
  if command -v tailscale &>/dev/null; then
    local ts_ip
    ts_ip=$(tailscale ip -4 2>/dev/null || true)
    if [[ -n "$ts_ip" ]]; then
      monitor_host="$ts_ip"
      info "Using Tailscale IP $ts_ip for remote monitoring"
    fi
  fi

  # Uptime Kuma API: Create TCP port monitor
  local response
  response=$(curl -s -w "\n%{http_code}" -X POST "${KUMA_URL}/api/monitors" \
    -H "Content-Type: application/json" \
    -u "${KUMA_USERNAME}:${KUMA_PASSWORD}" \
    -d "{
      \"type\": \"port\",
      \"name\": \"Hannah-${CLIENT_NAME}\",
      \"hostname\": \"${monitor_host}\",
      \"port\": ${port},
      \"interval\": 60,
      \"retryInterval\": 30,
      \"maxretries\": 3,
      \"notificationIDList\": {},
      \"description\": \"VELA Gateway: ${CLIENT_NAME} on port ${port}\"
    }" 2>/dev/null || echo -e "\n000")

  local http_code
  http_code=$(echo "$response" | tail -1)

  if [[ "$http_code" =~ ^2[0-9]{2}$ ]]; then
    ok "Uptime Kuma monitor created: Hannah-${CLIENT_NAME}"
  else
    warn "Could not create Uptime Kuma monitor (HTTP $http_code)."
    warn "You may need to create it manually in the Kuma dashboard."
    info "  Monitor Name: Hannah-${CLIENT_NAME}"
    info "  Type: TCP Port"
    info "  Hostname: ${monitor_host}"
    info "  Port: ${port}"
  fi
}

# ── Tailscale SSH Verification ───────────────────────────────────────────────
verify_tailscale() {
  if [[ "$SKIP_TAILSCALE" == true ]]; then
    info "Skipping Tailscale verification (--skip-tailscale)"
    return 0
  fi

  info "Verifying Tailscale SSH access..."

  # Check Tailscale is installed
  if ! command -v tailscale &>/dev/null; then
    warn "Tailscale CLI not found. Install from: https://tailscale.com/download"
    warn "Without Tailscale, you cannot remotely restart this gateway."
    return 1
  fi

  # Check Tailscale is connected
  local ts_status
  ts_status=$(tailscale status --json 2>/dev/null || echo '{}')
  local ts_state
  ts_state=$(echo "$ts_status" | python3 -c "import json,sys; print(json.load(sys.stdin).get('BackendState',''))" 2>/dev/null || echo "unknown")

  if [[ "$ts_state" != "Running" ]]; then
    warn "Tailscale is not running (state: $ts_state). Start with: tailscale up"
    return 1
  fi

  local ts_ip
  ts_ip=$(tailscale ip -4 2>/dev/null || echo "unknown")
  ok "Tailscale is running (IP: $ts_ip)"

  # Check SSH is enabled on macOS
  local ssh_enabled
  ssh_enabled=$(sudo systemsetup -getremotelogin 2>/dev/null | grep -i "on" || true)
  if [[ -z "$ssh_enabled" ]]; then
    warn "Remote Login (SSH) is not enabled on this Mac."
    warn "Enable it: System Settings → General → Sharing → Remote Login → On"
    warn "Or run: sudo systemsetup -setremotelogin on"
  else
    ok "SSH (Remote Login) is enabled"
  fi

  # Print the remote restart command for reference
  echo ""
  info "${BOLD}Remote restart command (from phone/laptop via Tailscale):${NC}"
  info "  ssh $(whoami)@${ts_ip} 'launchctl kickstart -k gui/${UID_NUM}/${SERVICE_NAME}'"
  echo ""
}

# ── Uninstall ────────────────────────────────────────────────────────────────
do_uninstall() {
  info "Uninstalling gateway instance: $CLIENT_NAME"

  unload_service
  
  if [[ -f "$PLIST_FILE" ]]; then
    rm -f "$PLIST_FILE"
    ok "Removed plist: $PLIST_FILE"
  fi

  deregister_instance

  info "Note: Uptime Kuma monitor must be removed manually if it was created."
  info "Note: Log files in $LOG_DIR were not removed."

  ok "Uninstall complete for $CLIENT_NAME"
}

# ── Summary ──────────────────────────────────────────────────────────────────
print_summary() {
  local port="$1"
  local ts_ip
  ts_ip=$(tailscale ip -4 2>/dev/null || echo "<tailscale-ip>")

  echo ""
  echo -e "${BOLD}═══════════════════════════════════════════════════════════${NC}"
  echo -e "${BOLD} VELA Gateway: ${CLIENT_NAME}${NC}"
  echo -e "${BOLD}═══════════════════════════════════════════════════════════${NC}"
  echo -e "  Service:     ${SERVICE_NAME}"
  echo -e "  Port:        ${port}"
  echo -e "  Config:      ${CONFIG_FILE}"
  echo -e "  Plist:       ${PLIST_FILE}"
  echo -e "  Logs:        ${LOG_DIR}/${CLIENT_NAME}-std{out,err}.log"
  echo -e "  Registry:    ${REGISTRY_FILE}"
  echo ""
  echo -e "  ${BOLD}Remote restart:${NC}"
  echo -e "  ssh $(whoami)@${ts_ip} 'launchctl kickstart -k gui/${UID_NUM}/${SERVICE_NAME}'"
  echo ""
  echo -e "  ${BOLD}Quick commands:${NC}"
  echo -e "  Status:      launchctl print gui/${UID_NUM}/${SERVICE_NAME}"
  echo -e "  Stop:        launchctl kill SIGTERM gui/${UID_NUM}/${SERVICE_NAME}"
  echo -e "  Restart:     launchctl kickstart -k gui/${UID_NUM}/${SERVICE_NAME}"
  echo -e "  Uninstall:   $(basename "$0") --name ${CLIENT_NAME} --uninstall"
  echo -e "${BOLD}═══════════════════════════════════════════════════════════${NC}"
  echo ""
}

# ── Main ─────────────────────────────────────────────────────────────────────
main() {
  echo ""
  echo -e "${BOLD}VELA Gateway Installer${NC}"
  echo -e "Instance: ${CYAN}${CLIENT_NAME}${NC}"
  echo ""

  # Handle uninstall
  if [[ "$UNINSTALL" == true ]]; then
    init_registry
    do_uninstall
    exit 0
  fi

  # Preflight
  preflight
  init_registry

  # Port assignment
  if [[ -z "$PORT" ]]; then
    PORT=$(get_next_port)
    info "Auto-assigned port: $PORT"
  else
    info "Using specified port: $PORT"
  fi
  check_port_conflict "$PORT"

  # Dry run check
  if [[ "$DRY_RUN" == true ]]; then
    echo ""
    info "${BOLD}DRY RUN — would perform:${NC}"
    info "  1. Generate plist: $PLIST_FILE"
    info "  2. Register in: $REGISTRY_FILE"
    info "  3. Load service: $SERVICE_NAME on port $PORT"
    info "  4. Create Uptime Kuma monitor: Hannah-${CLIENT_NAME}"
    info "  5. Verify Tailscale SSH access"
    echo ""
    exit 0
  fi

  # Generate and load
  generate_plist "$PORT"
  register_instance "$PORT"
  load_service

  # Monitoring and remote access
  setup_kuma_monitor "$PORT"
  verify_tailscale

  # Summary
  print_summary "$PORT"
}

main
