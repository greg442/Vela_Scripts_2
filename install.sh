#!/usr/bin/env bash
# ============================================================
#  VELA Private Command Infrastructure
#  Master Installer — install.sh
#  Version 2.1 — March 2026
#
#  STANDARD INSTALL (client pastes into Terminal):
#  curl -fsSL https://raw.githubusercontent.com/greg442/Vela_Scripts_2/main/install.sh | bash
#
#  PRE-FILLED INSTALL (Handler-generated, skips all prompts):
#  bash ~/Downloads/launch.sh
#
#  Greg Shindler / VELA Private Command Infrastructure
#  PROPRIETARY & CONFIDENTIAL
# ============================================================

set -euo pipefail

GITHUB_USER="greg442"
GITHUB_REPO="Vela_Scripts_2"
GITHUB_BRANCH="main"
VELA_VERSION="2.1.0"

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

# ── PROMPT HELPER ────────────────────────────────────────────
# ask VAR_NAME "Prompt" "optional_default"
# If VAR_NAME already set: shows value (masked if secret) and skips.
# If not set: prompts interactively.
SECRETS_PATTERN="API_KEY|TOKEN|SECRET|PASSWORD"

ask() {
  local var_name="$1"
  local prompt="$2"
  local default="${3:-}"
  local current_val="${!var_name:-}"

  if [[ -n "$current_val" ]]; then
    if echo "$var_name" | grep -qE "$SECRETS_PATTERN"; then
      echo -e "  ${GREEN}✓${RESET}  ${prompt}: ${current_val:0:8}... ${GRAY}(pre-filled)${RESET}"
    else
      echo -e "  ${GREEN}✓${RESET}  ${prompt}: ${current_val} ${GRAY}(pre-filled)${RESET}"
    fi
    return 0
  fi

  if [[ -n "$default" ]]; then
    read -rp "  ${prompt} (default: ${default}): " _input
    printf -v "$var_name" '%s' "${_input:-$default}"
  else
    read -rp "  ${prompt}: " _input
    printf -v "$var_name" '%s' "$_input"
  fi
}

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

if [[ "${VELA_PREFILLED:-false}" == "true" ]]; then
  echo -e "  ${GREEN}${BOLD}Pre-filled install — credentials loaded. Prompts skipped.${RESET}"
fi

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

SLEEP_SETTING=$(pmset -g | grep "sleep " | awk '{print $2}' || echo "unknown")
if [[ "$SLEEP_SETTING" != "0" ]]; then
  warn "Sleep is enabled. VELA requires the Mac Mini to stay awake."
  warn "Fix: System Settings → Energy → Prevent automatic sleep → ON"
  echo ""
  read -rp "  Press Enter once sleep is disabled, or Ctrl+C to fix first: "
fi
echo ""

# ── LICENSE KEY VALIDATION ───────────────────────────────────
section "2 of 5 — License Validation"

if [[ -z "${VELA_LICENSE_KEY:-}" ]]; then
  echo -e "  ${GRAY}Your VELA license key was provided by your Handler.${RESET}"
  echo -e "  ${GRAY}Format: VELA-XXXX-XXXX-XXXX-XXXX${RESET}"
  echo ""
  ask VELA_LICENSE_KEY "Your VELA License Key"
fi

[[ -n "${VELA_LICENSE_KEY:-}" ]] || error "License key required. Contact greg@gregshindler.com."

log "Validating license key..."

LICENSE_RESPONSE=$(curl -s --max-time 15 \
  -X POST "https://license.vela.run/validate" \
  -H "Content-Type: application/json" \
  -d "{\"license_key\": \"${VELA_LICENSE_KEY}\"}" 2>/dev/null || echo "TIMEOUT")

if [[ "$LICENSE_RESPONSE" == "TIMEOUT" ]]; then
  warn "License server unreachable. Proceeding with 24-hour grace period."
  LICENSE_STATUS="grace"
  LICENSE_TIER="command"
else
  LICENSE_STATUS=$(echo "$LICENSE_RESPONSE" | python3 -c \
    "import sys,json; d=json.load(sys.stdin); print(d.get('status','invalid'))" 2>/dev/null || echo "invalid")
  LICENSE_TIER=$(echo "$LICENSE_RESPONSE" | python3 -c \
    "import sys,json; d=json.load(sys.stdin); print(d.get('tier','command'))" 2>/dev/null || echo "command")
fi

case "$LICENSE_STATUS" in
  active|grace) success "License valid — Tier: ${LICENSE_TIER}" ;;
  revoked)      error "License revoked. Contact greg@gregshindler.com." ;;
  expired)      error "License expired. Contact greg@gregshindler.com to renew." ;;
  *)            error "Invalid license key. Contact greg@gregshindler.com." ;;
esac
echo ""

# ── COLLECT CLIENT INFO ──────────────────────────────────────
section "3 of 5 — Your Information"

if [[ "${VELA_PREFILLED:-false}" == "true" ]]; then
  echo -e "  ${GRAY}Credentials loaded from your setup form. Confirming...${RESET}"
else
  echo -e "  ${GRAY}This personalizes Hannah for you. Take your time.${RESET}"
fi
echo ""

ask CLIENT_NAME          "Your full name (e.g. John Smith)"
[[ -n "${CLIENT_NAME:-}" ]] || error "Name required."

ask CLIENT_COMPANY       "Your company"
[[ -n "${CLIENT_COMPANY:-}" ]] || error "Company required."

ask CLIENT_ROLE          "Your role / title"
[[ -n "${CLIENT_ROLE:-}" ]] || error "Role required."

ask AGENT_NAME           "Agent name" "Hannah"
AGENT_NAME="${AGENT_NAME:-Hannah}"

ask CLIENT_EMAIL_PRIMARY "Primary Gmail address"
[[ "${CLIENT_EMAIL_PRIMARY:-}" =~ @ ]] || error "Valid email required."

ask CLIENT_EMAIL_COS     "CoS Gmail address (for outbound)"
[[ "${CLIENT_EMAIL_COS:-}" =~ @ ]] || error "Valid email required."

ask CLIENT_USERNAME      "Mac Mini username (no spaces)"
[[ -n "${CLIENT_USERNAME:-}" ]] || error "Username required."

ask CLIENT_TIMEZONE      "Timezone" "America/New_York"
CLIENT_TIMEZONE="${CLIENT_TIMEZONE:-America/New_York}"

ask BRIEF_MORNING_HOUR   "Morning brief hour (24h, e.g. 6)" "6"
BRIEF_MORNING_HOUR="${BRIEF_MORNING_HOUR:-6}"

ask BRIEF_EVENING_HOUR   "Evening brief hour (24h, e.g. 16)" "16"
BRIEF_EVENING_HOUR="${BRIEF_EVENING_HOUR:-16}"

echo ""

if [[ "${VELA_PREFILLED:-false}" != "true" ]]; then
  log "Collecting credentials..."
  echo -e "  ${GRAY}See the setup guides in your Google Drive folder if you need help.${RESET}"
  echo ""
fi

ask TELEGRAM_BOT_TOKEN   "Telegram Bot Token"
[[ -n "${TELEGRAM_BOT_TOKEN:-}" ]] || error "Bot token required."

ask TELEGRAM_USER_ID     "Telegram User ID (positive number)"
[[ -n "${TELEGRAM_USER_ID:-}" ]] || error "User ID required."

ask TELEGRAM_GROUP_ID    "Telegram Group ID (negative number, e.g. -1003750313044)"
[[ -n "${TELEGRAM_GROUP_ID:-}" ]] || error "Group ID required."
[[ "${TELEGRAM_GROUP_ID:-}" =~ ^- ]] || error "Group ID must start with minus sign. Got: ${TELEGRAM_GROUP_ID}. Re-run @userinfobot inside your VELA Command group."

ask ANTHROPIC_API_KEY    "Anthropic API key (sk-ant-...)"
[[ "${ANTHROPIC_API_KEY:-}" =~ ^sk-ant- ]] || error "Invalid API key. Must start with sk-ant-"

ask GDRIVE_BACKUP_FOLDER_ID "Google Drive backup folder ID"

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

if [[ "${VELA_PREFILLED:-false}" == "true" ]]; then
  success "Values pre-verified by your Handler. Proceeding."
  CONFIRM="y"
else
  read -rp "  Continue? (y/n): " CONFIRM
fi

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

export VELA_LICENSE_KEY CLIENT_NAME CLIENT_COMPANY CLIENT_ROLE AGENT_NAME
export CLIENT_EMAIL_PRIMARY CLIENT_EMAIL_COS CLIENT_USERNAME CLIENT_TIMEZONE
export BRIEF_MORNING_HOUR BRIEF_EVENING_HOUR
export TELEGRAM_BOT_TOKEN TELEGRAM_USER_ID TELEGRAM_GROUP_ID
export ANTHROPIC_API_KEY GDRIVE_BACKUP_FOLDER_ID
export LICENSE_TIER VELA_VERSION GITHUB_USER GITHUB_REPO GITHUB_BRANCH
export VELA_PREFILLED

echo ""
exec bash "${MAIN_SCRIPT}"
