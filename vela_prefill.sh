#!/usr/bin/env bash
# ============================================================
#  VELA Private Command Infrastructure
#  vela_prefill.sh — Pre-fill generator
#
#  WHAT THIS DOES:
#    You run this on YOUR Mac after receiving a Tally form submission.
#    You paste in the client's values when prompted.
#    It generates a single command to send the client.
#    Client pastes that command into Terminal.
#    The installer skips every prompt and runs clean.
#
#  USAGE:
#    bash vela_prefill.sh
#
#  OUTPUT:
#    A ready-to-send one-liner saved to ~/vela-clients/[client_id]/launch.sh
#    and printed to screen for copy-paste into your message to the client.
#
#  Greg Shindler / VELA Private Command Infrastructure
#  INTERNAL TOOL — DO NOT SHARE WITH CLIENTS
# ============================================================

set -euo pipefail

GOLD='\033[0;33m'
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
BOLD='\033[1m'
GRAY='\033[0;90m'
CYAN='\033[0;36m'
RESET='\033[0m'

log()     { echo -e "${GOLD}▸${RESET} $1"; }
success() { echo -e "${GREEN}✓${RESET} $1"; }
warn()    { echo -e "${GOLD}⚠${RESET}  $1"; }
error()   { echo -e "${RED}✗${RESET} $1"; exit 1; }
hr()      { echo -e "${GRAY}────────────────────────────────────────────────────${RESET}"; }
section() { echo -e "\n${BLUE}${BOLD}$1${RESET}"; hr; }

clear
echo -e "${GOLD}"
cat << 'BANNER'
 __   __ ____  _        _
 \ \ / /| ___|| |      / \
  \ V / |  _| | |     / _ \
   \_/  |_____||_____|/_/ \_\

 Pre-fill Generator — Internal Tool
BANNER
echo -e "${RESET}"
echo -e "  ${BOLD}VELA Handler Tool${RESET}"
echo -e "  ${GRAY}Run this after receiving the client's Tally form submission.${RESET}"
hr
echo ""

# ── COLLECT CLIENT VALUES ────────────────────────────────────
section "Client Information — from Tally submission"
echo -e "  ${GRAY}Paste in the values from the form. Press Enter after each one.${RESET}"
echo ""

read -rp "  Full name: " CLIENT_NAME
[[ -n "$CLIENT_NAME" ]] || error "Name required."

read -rp "  Company: " CLIENT_COMPANY
[[ -n "$CLIENT_COMPANY" ]] || error "Company required."

read -rp "  Role / title: " CLIENT_ROLE
[[ -n "$CLIENT_ROLE" ]] || error "Role required."

read -rp "  Agent name (default: Hannah): " AGENT_NAME
AGENT_NAME="${AGENT_NAME:-Hannah}"

read -rp "  Primary Gmail: " CLIENT_EMAIL_PRIMARY
[[ "$CLIENT_EMAIL_PRIMARY" =~ @ ]] || error "Valid email required."

read -rp "  CoS Gmail (same if only one): " CLIENT_EMAIL_COS
[[ "$CLIENT_EMAIL_COS" =~ @ ]] || error "Valid email required."

read -rp "  Mac Mini username (from whoami): " CLIENT_USERNAME
[[ -n "$CLIENT_USERNAME" ]] || error "Username required."
# Sanitise — no spaces
CLIENT_USERNAME="${CLIENT_USERNAME// /}"

read -rp "  Timezone (e.g. America/New_York): " CLIENT_TIMEZONE
CLIENT_TIMEZONE="${CLIENT_TIMEZONE:-America/New_York}"

read -rp "  Morning brief hour 24h (e.g. 6): " BRIEF_MORNING_HOUR
BRIEF_MORNING_HOUR="${BRIEF_MORNING_HOUR:-6}"

read -rp "  Evening brief hour 24h (e.g. 16): " BRIEF_EVENING_HOUR
BRIEF_EVENING_HOUR="${BRIEF_EVENING_HOUR:-16}"

echo ""
section "API Keys and Credentials"

read -rp "  VELA License Key (VELA-XXXX-XXXX-XXXX-XXXX): " VELA_LICENSE_KEY
[[ "$VELA_LICENSE_KEY" =~ ^VELA- ]] || error "Invalid license key format."

read -rp "  Anthropic API key (sk-ant-...): " ANTHROPIC_API_KEY
[[ "$ANTHROPIC_API_KEY" =~ ^sk-ant- ]] || error "Invalid Anthropic API key."

read -rp "  Telegram Bot Token: " TELEGRAM_BOT_TOKEN
[[ -n "$TELEGRAM_BOT_TOKEN" ]] || error "Bot token required."

read -rp "  Telegram User ID (positive number): " TELEGRAM_USER_ID
[[ "$TELEGRAM_USER_ID" =~ ^[0-9]+$ ]] || error "User ID must be a positive integer."

read -rp "  Telegram Group ID (negative number, e.g. -1003750313044): " TELEGRAM_GROUP_ID
[[ "$TELEGRAM_GROUP_ID" =~ ^-[0-9]+$ ]] || error "Group ID must be a negative integer. Got: ${TELEGRAM_GROUP_ID}"

read -rp "  Google Drive Backup Folder ID: " GDRIVE_BACKUP_FOLDER_ID
[[ -n "$GDRIVE_BACKUP_FOLDER_ID" ]] || error "Drive folder ID required."

read -rp "  Google OAuth JSON file path (e.g. ~/Downloads/client_secret_XXX.json): " OAUTH_JSON_PATH
OAUTH_JSON_PATH="${OAUTH_JSON_PATH/#\~/$HOME}"
[[ -f "$OAUTH_JSON_PATH" ]] || warn "JSON file not found at that path — verify before sending to client."

echo ""
section "Review"

echo -e "  ${GRAY}Name:       ${RESET}${CLIENT_NAME}"
echo -e "  ${GRAY}Company:    ${RESET}${CLIENT_COMPANY}"
echo -e "  ${GRAY}Role:       ${RESET}${CLIENT_ROLE}"
echo -e "  ${GRAY}Agent:      ${RESET}${AGENT_NAME}"
echo -e "  ${GRAY}Email:      ${RESET}${CLIENT_EMAIL_PRIMARY}"
echo -e "  ${GRAY}CoS Email:  ${RESET}${CLIENT_EMAIL_COS}"
echo -e "  ${GRAY}Username:   ${RESET}${CLIENT_USERNAME}"
echo -e "  ${GRAY}Timezone:   ${RESET}${CLIENT_TIMEZONE}"
echo -e "  ${GRAY}Briefs:     ${RESET}${BRIEF_MORNING_HOUR}am / ${BRIEF_EVENING_HOUR}pm"
echo -e "  ${GRAY}License:    ${RESET}${VELA_LICENSE_KEY}"
echo -e "  ${GRAY}Anthropic:  ${RESET}${ANTHROPIC_API_KEY:0:12}..."
echo -e "  ${GRAY}Bot Token:  ${RESET}${TELEGRAM_BOT_TOKEN:0:12}..."
echo -e "  ${GRAY}User ID:    ${RESET}${TELEGRAM_USER_ID}"
echo -e "  ${GRAY}Group ID:   ${RESET}${TELEGRAM_GROUP_ID}"
echo -e "  ${GRAY}Drive ID:   ${RESET}${GDRIVE_BACKUP_FOLDER_ID}"
echo ""

read -rp "  All correct? Generate the client command? (y/n): " CONFIRM
[[ "$CONFIRM" =~ ^[Yy] ]] || error "Cancelled."

# ── GENERATE CLIENT ID ───────────────────────────────────────
# Lowercase, no spaces, underscores
CLIENT_ID=$(echo "${CLIENT_NAME}" | tr '[:upper:]' '[:lower:]' | tr ' ' '_' | tr -cd '[:alnum:]_')
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# ── SAVE OAUTH JSON ──────────────────────────────────────────
CLIENTS_DIR="$HOME/.vela/clients/${CLIENT_ID}"
mkdir -p "${CLIENTS_DIR}"

if [[ -f "$OAUTH_JSON_PATH" ]]; then
  cp "${OAUTH_JSON_PATH}" "${CLIENTS_DIR}/oauth_credentials.json"
  success "OAuth JSON saved to ${CLIENTS_DIR}/oauth_credentials.json"
fi

# ── SAVE CLIENT MANIFEST ─────────────────────────────────────
cat > "${CLIENTS_DIR}/manifest.conf" << MANIFEST
# VELA Client Manifest
# Generated: ${TIMESTAMP}
CLIENT_ID="${CLIENT_ID}"
CLIENT_NAME="${CLIENT_NAME}"
CLIENT_COMPANY="${CLIENT_COMPANY}"
CLIENT_ROLE="${CLIENT_ROLE}"
AGENT_NAME="${AGENT_NAME}"
CLIENT_EMAIL_PRIMARY="${CLIENT_EMAIL_PRIMARY}"
CLIENT_EMAIL_COS="${CLIENT_EMAIL_COS}"
CLIENT_USERNAME="${CLIENT_USERNAME}"
CLIENT_TIMEZONE="${CLIENT_TIMEZONE}"
BRIEF_MORNING_HOUR="${BRIEF_MORNING_HOUR}"
BRIEF_EVENING_HOUR="${BRIEF_EVENING_HOUR}"
VELA_LICENSE_KEY="${VELA_LICENSE_KEY}"
ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY}"
TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN}"
TELEGRAM_USER_ID="${TELEGRAM_USER_ID}"
TELEGRAM_GROUP_ID="${TELEGRAM_GROUP_ID}"
GDRIVE_BACKUP_FOLDER_ID="${GDRIVE_BACKUP_FOLDER_ID}"
INSTALL_DATE=""
TAILSCALE_IP=""
TAILSCALE_HOSTNAME="vela-${CLIENT_ID}"
MANIFEST

success "Manifest saved to ${CLIENTS_DIR}/manifest.conf"

# ── BUILD ENCODED PAYLOAD ────────────────────────────────────
# Encode all variables as a base64 payload that the client's
# install.sh will decode and load before prompting.
# This avoids exposing secrets in plain text in the one-liner.

PAYLOAD=$(cat << VARS
VELA_LICENSE_KEY=${VELA_LICENSE_KEY}
CLIENT_NAME=${CLIENT_NAME}
CLIENT_COMPANY=${CLIENT_COMPANY}
CLIENT_ROLE=${CLIENT_ROLE}
AGENT_NAME=${AGENT_NAME}
CLIENT_EMAIL_PRIMARY=${CLIENT_EMAIL_PRIMARY}
CLIENT_EMAIL_COS=${CLIENT_EMAIL_COS}
CLIENT_USERNAME=${CLIENT_USERNAME}
CLIENT_TIMEZONE=${CLIENT_TIMEZONE}
BRIEF_MORNING_HOUR=${BRIEF_MORNING_HOUR}
BRIEF_EVENING_HOUR=${BRIEF_EVENING_HOUR}
TELEGRAM_BOT_TOKEN=${TELEGRAM_BOT_TOKEN}
TELEGRAM_USER_ID=${TELEGRAM_USER_ID}
TELEGRAM_GROUP_ID=${TELEGRAM_GROUP_ID}
ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY}
GDRIVE_BACKUP_FOLDER_ID=${GDRIVE_BACKUP_FOLDER_ID}
VARS
)

ENCODED=$(echo "$PAYLOAD" | base64 | tr -d '\n')

# ── BUILD LAUNCH SCRIPT ──────────────────────────────────────
# This is what the client runs. It decodes the payload,
# loads the variables, then calls the standard install.sh.
# The install.sh sees everything pre-populated and skips all prompts.

LAUNCH_SCRIPT="${CLIENTS_DIR}/launch.sh"

cat > "${LAUNCH_SCRIPT}" << LAUNCH
#!/usr/bin/env bash
# VELA Installation Command — ${CLIENT_NAME}
# Generated: ${TIMESTAMP}
# DO NOT MODIFY — send as-is

_VELA_PAYLOAD="${ENCODED}"
eval "\$(echo "\$_VELA_PAYLOAD" | base64 --decode | while IFS='=' read -r key val; do echo "export \$key='\$val'"; done)"
export VELA_PREFILLED=true

curl -fsSL https://raw.githubusercontent.com/greg442/Vela_Scripts_2/main/install.sh | bash
LAUNCH

chmod +x "${LAUNCH_SCRIPT}"

# ── ALSO GENERATE A CLEAN PASTE COMMAND ──────────────────────
# Simpler one-liner the client can paste directly into Terminal
ONELINER="bash <(curl -fsSL https://raw.githubusercontent.com/greg442/Vela_Scripts_2/main/install.sh) <<< '${ENCODED}'"

# ── OUTPUT ───────────────────────────────────────────────────
section "Ready"

echo ""
echo -e "  ${GREEN}${BOLD}Client launch script saved:${RESET}"
echo -e "  ${CYAN}${LAUNCH_SCRIPT}${RESET}"
echo ""
echo -e "  ${GOLD}${BOLD}What to send the client:${RESET}"
echo ""
echo -e "  ${GRAY}Option A — Send them launch.sh${RESET}"
echo -e "  Upload ${LAUNCH_SCRIPT} to your Google Drive."
echo -e "  Client downloads it, opens Terminal, and runs:"
echo -e "  ${CYAN}bash ~/Downloads/launch.sh${RESET}"
echo ""
echo -e "  ${GRAY}Option B — SSH in yourself during the call${RESET}"
echo -e "  SSH into their Mac Mini via Tailscale."
echo -e "  Run the launch script directly:"
echo -e "  ${CYAN}bash ${LAUNCH_SCRIPT}${RESET}"
echo ""
echo -e "  ${GRAY}Option C — Paste block (for screen-share installs)${RESET}"
echo -e "  Paste this block into their Terminal yourself during the call:"
echo ""

# Print the export block cleanly for screen-share use
echo -e "${CYAN}"
echo "export VELA_LICENSE_KEY='${VELA_LICENSE_KEY}'"
echo "export CLIENT_NAME='${CLIENT_NAME}'"
echo "export CLIENT_COMPANY='${CLIENT_COMPANY}'"
echo "export CLIENT_ROLE='${CLIENT_ROLE}'"
echo "export AGENT_NAME='${AGENT_NAME}'"
echo "export CLIENT_EMAIL_PRIMARY='${CLIENT_EMAIL_PRIMARY}'"
echo "export CLIENT_EMAIL_COS='${CLIENT_EMAIL_COS}'"
echo "export CLIENT_USERNAME='${CLIENT_USERNAME}'"
echo "export CLIENT_TIMEZONE='${CLIENT_TIMEZONE}'"
echo "export BRIEF_MORNING_HOUR='${BRIEF_MORNING_HOUR}'"
echo "export BRIEF_EVENING_HOUR='${BRIEF_EVENING_HOUR}'"
echo "export TELEGRAM_BOT_TOKEN='${TELEGRAM_BOT_TOKEN}'"
echo "export TELEGRAM_USER_ID='${TELEGRAM_USER_ID}'"
echo "export TELEGRAM_GROUP_ID='${TELEGRAM_GROUP_ID}'"
echo "export ANTHROPIC_API_KEY='${ANTHROPIC_API_KEY}'"
echo "export GDRIVE_BACKUP_FOLDER_ID='${GDRIVE_BACKUP_FOLDER_ID}'"
echo "export VELA_PREFILLED=true"
echo "curl -fsSL https://raw.githubusercontent.com/greg442/Vela_Scripts_2/main/install.sh | bash"
echo -e "${RESET}"

echo ""
hr
echo -e "  ${GRAY}All client files: ${RESET}${CLIENTS_DIR}"
echo ""
