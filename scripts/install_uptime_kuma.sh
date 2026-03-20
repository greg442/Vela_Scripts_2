#!/usr/bin/env bash
# ============================================================
#  VELA Executive Intelligence Systems
#  Uptime Kuma Monitoring — Install Script
#  Version 1.0 — March 2026
#
#  Installs Uptime Kuma via Node.js + PM2 (no Docker required)
#  Runs on http://localhost:3001
#  Starts automatically on boot via PM2
#  Sends Telegram alerts on any monitored service going down
#
#  Usage:
#    chmod +x install_uptime_kuma.sh
#    ./install_uptime_kuma.sh
# ============================================================

set -euo pipefail

GOLD='\033[0;33m'
GREEN='\033[0;32m'
RED='\033[0;31m'
BOLD='\033[1m'
GRAY='\033[0;90m'
RESET='\033[0m'

log()     { echo -e "${GOLD}▸${RESET} $1"; }
success() { echo -e "${GREEN}✓${RESET} $1"; }
warn()    { echo -e "${GOLD}⚠${RESET}  $1"; }
error()   { echo -e "${RED}✗${RESET} $1"; exit 1; }
hr()      { echo -e "${GRAY}────────────────────────────────────────────────────${RESET}"; }

clear
echo -e "${GOLD}"
cat << 'BANNER'
 _   _     _   _
| | | |_ _| |_(_)_ __  ___
| | | | '_ \  _| | '  \/ -_)
|_| |_| .__/\__|_|_|_|_\___|
      |_|  Kuma — VELA Monitoring
BANNER
echo -e "${RESET}"
hr
echo -e "  Installing Uptime Kuma — self-hosted service monitor"
echo -e "  Dashboard: ${BOLD}http://localhost:3001${RESET}"
hr
echo ""

# ── PREREQ CHECKS ───────────────────────────────────────────
log "Checking prerequisites..."

command -v node &>/dev/null || error "Node.js not found. Run vela_install.sh first."
command -v npm  &>/dev/null || error "npm not found. Run vela_install.sh first."
command -v git  &>/dev/null || error "git not found. Run: brew install git"

NODE_MAJOR=$(node -v | cut -d. -f1 | tr -d 'v')
[[ $NODE_MAJOR -ge 18 ]] || error "Node.js 18+ required. Found: $(node -v)"
success "Node.js $(node -v) — OK"

# ── PM2 ─────────────────────────────────────────────────────
log "Installing PM2 process manager..."
if command -v pm2 &>/dev/null; then
  success "PM2 already installed: $(pm2 --version)"
else
  npm install -g pm2 --quiet
  npm install -g pm2-logrotate --quiet
  success "PM2 installed: $(pm2 --version)"
fi

# ── UPTIME KUMA ─────────────────────────────────────────────
INSTALL_DIR="$HOME/.vela/uptime-kuma"
mkdir -p "$HOME/.vela"

if [[ -d "$INSTALL_DIR" ]]; then
  warn "Uptime Kuma directory exists at $INSTALL_DIR"
  read -p "  Update existing install? (y/n): " UPDATE_CHOICE
  if [[ "$UPDATE_CHOICE" == "y" ]]; then
    log "Pulling latest updates..."
    cd "$INSTALL_DIR"
    git pull --quiet
    npm run setup --quiet
    success "Updated to latest version"
  else
    log "Skipping download — using existing install"
    cd "$INSTALL_DIR"
  fi
else
  log "Cloning Uptime Kuma..."
  git clone https://github.com/louislam/uptime-kuma.git "$INSTALL_DIR" --quiet
  cd "$INSTALL_DIR"
  log "Running setup (installs Node dependencies)..."
  npm run setup --quiet
  success "Uptime Kuma installed at $INSTALL_DIR"
fi

# ── START WITH PM2 ──────────────────────────────────────────
log "Starting Uptime Kuma with PM2..."
cd "$INSTALL_DIR"

# Stop existing instance if running
pm2 stop uptime-kuma 2>/dev/null || true
pm2 delete uptime-kuma 2>/dev/null || true

pm2 start server/server.js --name uptime-kuma
pm2 save

log "Configuring PM2 startup (auto-start on reboot)..."
# Generate startup script — user must run the output command manually
STARTUP_CMD=$(pm2 startup 2>&1 | grep "sudo" | tail -1 || echo "")
if [[ -n "$STARTUP_CMD" ]]; then
  echo ""
  echo -e "${GOLD}━━━  ACTION REQUIRED  ━━━${RESET}"
  echo -e "Run this command to enable auto-start on boot:"
  echo -e "${BOLD}  $STARTUP_CMD${RESET}"
  echo -e "${GRAY}  (copy and paste the full command above)${RESET}"
  echo ""
fi

success "Uptime Kuma running — PID: $(pm2 id uptime-kuma 2>/dev/null || echo 'see pm2 list')"

# ── VERIFY ──────────────────────────────────────────────────
sleep 3
log "Verifying Uptime Kuma is responding..."
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3001 --max-time 10 2>/dev/null || echo "000")
if [[ "$HTTP_STATUS" == "200" || "$HTTP_STATUS" == "304" ]]; then
  success "Uptime Kuma responding at http://localhost:3001 (HTTP $HTTP_STATUS)"
else
  warn "Got HTTP $HTTP_STATUS — may still be starting up. Wait 10 seconds and visit http://localhost:3001"
fi

# ── PRINT SUMMARY ───────────────────────────────────────────
echo ""
hr
echo -e "\n${BOLD}${GOLD}  UPTIME KUMA INSTALLED${RESET}\n"
hr
echo ""
echo -e "${BOLD}Dashboard:${RESET}     http://localhost:3001"
echo -e "${BOLD}Via Tailscale:${RESET} http://[your-tailscale-ip]:3001"
echo -e "${BOLD}PM2 status:${RESET}   pm2 status"
echo -e "${BOLD}PM2 logs:${RESET}     pm2 logs uptime-kuma"
echo ""
echo -e "${BOLD}First-time setup (do this now):${RESET}"
echo -e "  1. Open http://localhost:3001 in your browser"
echo -e "  2. Create your admin account (username + password)"
echo -e "  3. Add monitors — see list below"
echo -e "  4. Configure Telegram notifications (Settings → Notifications)"
echo ""
echo -e "${BOLD}Monitors to add:${RESET}"
echo -e "  ${GRAY}Type: HTTP(s)${RESET}"
echo -e "  • https://api.anthropic.com         — Anthropic API"
echo -e "  • https://api.telegram.org          — Telegram"
echo -e "  • http://localhost:11434            — Ollama"
echo -e "  ${GRAY}Type: Ping${RESET}"
echo -e "  • 8.8.8.8                            — Internet connectivity"
echo -e "  ${GRAY}Type: TCP Port${RESET}"
echo -e "  • localhost : 3000                  — OpenClaw gateway"
echo ""
echo -e "${BOLD}Telegram notification setup:${RESET}"
echo -e "  Settings → Notifications → Add → Telegram"
echo -e "  Enter your Bot Token + Chat ID"
echo -e "  Check 'Send test notification'"
echo ""
hr
echo ""
