#!/usr/bin/env bash
# ============================================================
#  VELA Private Command Infrastructure
#  Master Installer — install.sh
#  Version 2.0 — March 2026
#
#  ONE-LINE INSTALL (paste into Terminal on your Mac Mini):
#
#  curl -fsSL https://raw.githubusercontent.com/greg442/Vela_Scripts_2/main/install.sh | bash
#
#  What happens:
#    1. Preflight — checks hardware, OS, internet
#    2. Downloads all VELA scripts from GitHub
#    3. Validates your VELA license key
#    4. Runs the full install sequence
#    5. Leaves a clean ~/vela-setup/ directory with all scripts
#
#  Greg Shindler / VELA Private Command Infrastructure
#  PROPRIETARY & CONFIDENTIAL
# ============================================================

set -euo pipefail

GITHUB_USER="greg442"
GITHUB_REPO="Vela_Scripts_2"
GITHUB_BRANCH="main"
VELA_VERSION="2.0.0"

BASE_URL="https://raw.githubusercontent.com/${GITHUB_USER}/${GITHUB_REPO}/${GITHUB_BRANCH}"
INSTALL_DIR="$HOME/vela-setup"

# ── COLORS ──────────────────────────────────────────────────
GOLD='\033[0;33m'
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
BOLD='\033[1m'
GRAY='\033[0;90m'
RESET='\033[0m'

log()     { echo -e "${GOLD}▸${RESET} $1"; }
success() { echo -e "${GREEN}✓${RESET} $1"; }
warn()    { echo -e "${GOLD}⚠${RESET}  $1"; }
error()   { echo -e "${RED}✗${RESET} $1"; exit 1; }
hr()      { echo -e "${GRAY}────────────────────────────────────────────────────${RESET}"; }
section() { echo -e "\n${BLUE}${BOLD}$1${RESET}"; hr; }

# ── BANNER ──────────────────────────────────────────────────
clear
echo -e "${GOLD}"
cat << 'BANNER'
 __   __ ____  _        _
 \ \ / /| ___|| |      / \
  \ V / |  _| | |     / _ \
   \_/  |_____||_____|/_/ \_\

 Private Command Infrastructure
BANNER
echo -e "${RESET}"
echo -e "  ${BOLD}VELA Installer v${VELA_VERSION}${RESET}"
echo -e "  ${GRAY}Your judgment. Our infrastructure.${RESET}"
hr
echo ""

# ── PREFLIGHT ───────────────────────────────────────────────
section "1 of 5 — System Check"

[[ "$(uname)" == "Darwin" ]] || error "macOS required."
[[ "$(uname -m)" == "arm64" ]] || warn "Not Apple Silicon — performance may vary."

OS_VER=$(sw_vers -productVersion)
RAM_GB=$(( $(sysctl -n hw.memsize) / 1024 / 1024 / 1024 ))
[[ $RAM_GB -ge 16 ]] || error "16 GB RAM minimum required. Found: ${RAM_GB} GB."

success "macOS ${OS_VER} — Apple Silicon"
success "${RAM_GB} GB unified memory"

curl -s --max-time 8 "https://github.com" > /dev/null 2>&1 || error "No internet connection."
success "Internet confirmed"

# Energy Saver check
SLEEP_SETTING=$(pmset -g | grep "sleep " | awk '{print $2}' || echo "unknown")
if [[ "$SLEEP_SETTING" != "0" ]]; then
  warn "Sleep is enabled (setting: ${SLEEP_SETTING}). VELA requires the Mac Mini to stay awake."
  warn "Fix now: System Settings → Energy → set 'Prevent automatic sleep' to ON"
  echo ""
  read -rp "  Press Enter once you've disabled sleep, or Ctrl+C to exit and fix first: "
fi

echo ""

# ── LICENSE KEY VALIDATION ───────────────────────────────────
section "2 of 5 — License Validation"

echo -e "  ${GRAY}Your VELA license key was provided by your installer.${RESET}"
echo -e "  ${GRAY}It looks like: VELA-XXXX-XXXX-XXXX-XXXX${RESET}"
echo ""
read -rp "  Enter your VELA License Key: " VELA_LICENSE_KEY

if [[ -z "$VELA_LICENSE_KEY" ]]; then
  error "License key required. Contact greg@gregshindler.com."
fi

log "Validating license key..."

LICENSE_RESPONSE=$(curl -s --max-time 15 \
  -X POST "https://license.vela.run/validate" \
  -H "Content-Type: application/json" \
  -d "{\"license_key\": \"${VELA_LICENSE_KEY}\"}" 2>/dev/null || echo "TIMEOUT")

if [[ "$LICENSE_RESPONSE" == "TIMEOUT" ]]; then
  warn "License server unreachable. Proceeding with 24-hour grace period."
  warn "Hannah will check again at next session start."
  LICENSE_STATUS="grace"
  LICENSE_TIER="command"
else
  LICENSE_STATUS=$(echo "$LICENSE_RESPONSE" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('status','invalid'))" 2>/dev/null || echo "invalid")
  LICENSE_TIER=$(echo "$LICENSE_RESPONSE" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tier','command'))" 2>/dev/null || echo "command")
fi

case "$LICENSE_STATUS" in
  active|grace)
    success "License valid — Tier: ${LICENSE_TIER}"
    ;;
  revoked)
    error "License revoked. Contact greg@gregshindler.com."
    ;;
  expired)
    error "License expired. Contact greg@gregshindler.com to renew."
    ;;
  *)
    error "Invalid license key. Check the key and try again, or contact greg@gregshindler.com."
    ;;
esac

echo ""

# ── COLLECT CLIENT INFO ──────────────────────────────────────
section "3 of 5 — Your Information"

echo -e "  ${GRAY}This personalizes Hannah for you. Take your time.${RESET}"
echo ""

read -rp "  Your full name (e.g. John Smith): " CLIENT_NAME
[[ -n "$CLIENT_NAME" ]] || error "Name required."

read -rp "  Your company / organization: " CLIENT_COMPANY
[[ -n "$CLIENT_COMPANY" ]] || error "Company required."

read -rp "  Your role / title: " CLIENT_ROLE
[[ -n "$CLIENT_ROLE" ]] || error "Role required."

read -rp "  What would you like your agent called? (default: Hannah): " AGENT_NAME
AGENT_NAME="${AGENT_NAME:-Hannah}"

read -rp "  Your primary Gmail address: " CLIENT_EMAIL_PRIMARY
[[ "$CLIENT_EMAIL_PRIMARY" =~ @ ]] || error "Valid email required."

read -rp "  Your CoS Gmail address (for outbound): " CLIENT_EMAIL_COS
[[ "$CLIENT_EMAIL_COS" =~ @ ]] || error "Valid email required."

read -rp "  Your Mac Mini username (no spaces, e.g. johnsmith): " CLIENT_USERNAME
[[ -n "$CLIENT_USERNAME" ]] || error "Username required."

read -rp "  Your timezone (e.g. America/New_York): " CLIENT_TIMEZONE
CLIENT_TIMEZONE="${CLIENT_TIMEZONE:-America/New_York}"

read -rp "  Morning brief time — hour in 24h format (e.g. 6 for 6am): " BRIEF_MORNING_HOUR
BRIEF_MORNING_HOUR="${BRIEF_MORNING_HOUR:-6}"

read -rp "  Evening brief time — hour in 24h format (e.g. 16 for 4pm): " BRIEF_EVENING_HOUR
BRIEF_EVENING_HOUR="${BRIEF_EVENING_HOUR:-16}"

echo ""
log "Collecting Telegram credentials..."
echo -e "  ${GRAY}Need help? See README_First.pdf for step-by-step instructions.${RESET}"
echo ""

read -rp "  Telegram Bot Token: " TELEGRAM_BOT_TOKEN
[[ -n "$TELEGRAM_BOT_TOKEN" ]] || error "Telegram bot token required."

read -rp "  Telegram User ID (from @userinfobot): " TELEGRAM_USER_ID
[[ -n "$TELEGRAM_USER_ID" ]] || error "Telegram user ID required."

read -rp "  Telegram Group ID (negative integer, e.g. -1003750313044): " TELEGRAM_GROUP_ID
[[ -n "$TELEGRAM_GROUP_ID" ]] || error "Telegram group ID required."

read -rp "  Anthropic API key (sk-ant-...): " ANTHROPIC_API_KEY
[[ "$ANTHROPIC_API_KEY" =~ ^sk-ant- ]] || error "Invalid Anthropic API key format."

read -rp "  Google Drive backup folder ID: " GDRIVE_BACKUP_FOLDER_ID

echo ""
echo -e "  ${BOLD}Confirm your details:${RESET}"
echo -e "  ${GRAY}Name:      ${RESET}${CLIENT_NAME}"
echo -e "  ${GRAY}Company:   ${RESET}${CLIENT_COMPANY}"
echo -e "  ${GRAY}Role:      ${RESET}${CLIENT_ROLE}"
echo -e "  ${GRAY}Agent:     ${RESET}${AGENT_NAME}"
echo -e "  ${GRAY}Email:     ${RESET}${CLIENT_EMAIL_PRIMARY}"
echo -e "  ${GRAY}Timezone:  ${RESET}${CLIENT_TIMEZONE}"
echo -e "  ${GRAY}Briefs:    ${RESET}${BRIEF_MORNING_HOUR}am / ${BRIEF_EVENING_HOUR}pm"
echo ""
read -rp "  Continue? (y/n): " CONFIRM
[[ "$CONFIRM" =~ ^[Yy] ]] || error "Cancelled."

echo ""

# ── DOWNLOAD SCRIPTS ─────────────────────────────────────────
section "4 of 5 — Downloading VELA"

mkdir -p "${INSTALL_DIR}/scripts/monitoring"
cd "${INSTALL_DIR}"

declare -a SCRIPTS=(
  "scripts/vela_install.sh"
  "scripts/license_check.py"
  "scripts/install_uptime_kuma.sh"
  "scripts/backup_gdrive.sh"
  "scripts/cost_alert.py"
  "scripts/email_triage.py"
  "scripts/reset_sessions.sh"
  "scripts/backup_local.sh"
  "scripts/deliver_report.py"
  "scripts/monitoring/setup_monitoring.sh"
  "scripts/monitoring/health_check.sh"
  "scripts/monitoring/setup_tailscale.sh"
)

DOWNLOAD_OK=0
DOWNLOAD_FAIL=0

for script in "${SCRIPTS[@]}"; do
  filename=$(basename "$script")
  url="${BASE_URL}/${script}"
  dest="${INSTALL_DIR}/${script}"
  mkdir -p "$(dirname "$dest")"

  if curl -fsSL "$url" -o "$dest" 2>/dev/null; then
    chmod +x "$dest" 2>/dev/null || true
    success "  ${filename}"
    ((DOWNLOAD_OK++)) || true
  else
    warn "  Could not download: ${filename}"
    ((DOWNLOAD_FAIL++)) || true
  fi
done

echo ""
[[ $DOWNLOAD_FAIL -gt 0 ]] && warn "${DOWNLOAD_FAIL} script(s) failed. Install may be incomplete."
success "Downloaded ${DOWNLOAD_OK} scripts"

# ── HAND OFF TO MAIN INSTALLER ───────────────────────────────
section "5 of 5 — Installing VELA"

MAIN_SCRIPT="${INSTALL_DIR}/scripts/vela_install.sh"
[[ -f "$MAIN_SCRIPT" ]] || error "Main install script not found. Check repo and retry."

# Export all collected variables for the main installer
export VELA_LICENSE_KEY CLIENT_NAME CLIENT_COMPANY CLIENT_ROLE AGENT_NAME
export CLIENT_EMAIL_PRIMARY CLIENT_EMAIL_COS CLIENT_USERNAME CLIENT_TIMEZONE
export BRIEF_MORNING_HOUR BRIEF_EVENING_HOUR
export TELEGRAM_BOT_TOKEN TELEGRAM_USER_ID TELEGRAM_GROUP_ID
export ANTHROPIC_API_KEY GDRIVE_BACKUP_FOLDER_ID
export LICENSE_TIER VELA_VERSION GITHUB_USER GITHUB_REPO GITHUB_BRANCH

echo ""
exec bash "${MAIN_SCRIPT}"
