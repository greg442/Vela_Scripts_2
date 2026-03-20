#!/usr/bin/env bash
# ============================================================
#  VELA Private Command Infrastructure
#  Client Provisioning Script — vela_deploy.sh
#  Version 2.0 — March 2026
#
#  YOU run this. Not the client.
#  Run on your Mac Mini or laptop before each pilot/client install.
#
#  What it does:
#    1. Collects client info
#    2. Generates a VELA license key
#    3. Prints the SQL to add key to the license server
#    4. Creates a client manifest file for your records
#    5. Generates a Tailscale auth key naming convention
#    6. Prints the delivery checklist for handoff
#
#  Usage:
#    bash vela_deploy.sh
#    bash vela_deploy.sh --client john_smith  (skip prompts for known client)
#
#  Greg Shindler / VELA Private Command Infrastructure
# ============================================================

set -euo pipefail

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
hr()      { echo -e "${GRAY}────────────────────────────────────────────────────${RESET}"; }
section() { echo -e "\n${BLUE}${BOLD}$1${RESET}"; hr; }

DEPLOY_DIR="$HOME/.vela/deployments"
mkdir -p "$DEPLOY_DIR"

# ── BANNER ──────────────────────────────────────────────────
clear
echo -e "${GOLD}"
cat << 'BANNER'
 __   __ ____  _        _
 \ \ / /| ___|| |      / \
  \ V / |  _| | |     / _ \
   \_/  |_____||_____|/_/ \_\
BANNER
echo -e "${RESET}"
echo -e "  ${BOLD}VELA Client Provisioning${RESET}"
echo -e "  ${GRAY}Run this before each new install.${RESET}"
hr
echo ""

# ── CLIENT INFO ─────────────────────────────────────────────
section "Client Information"

read -rp "  Client full name (e.g. John Smith): " CLIENT_FULL_NAME
[[ -n "$CLIENT_FULL_NAME" ]] || { echo "Name required."; exit 1; }

# Generate client_id from name (lowercase, underscored)
CLIENT_ID=$(echo "$CLIENT_FULL_NAME" | tr '[:upper:]' '[:lower:]' | tr ' ' '_' | tr -cd 'a-z0-9_')
read -rp "  Client ID [${CLIENT_ID}]: " CLIENT_ID_INPUT
CLIENT_ID="${CLIENT_ID_INPUT:-$CLIENT_ID}"

read -rp "  Company: " CLIENT_COMPANY
read -rp "  Email: " CLIENT_EMAIL
read -rp "  Tier [command]: " TIER_INPUT
TIER="${TIER_INPUT:-command}"

read -rp "  License expiry (ISO date, e.g. 2027-01-01, or Enter for none): " EXPIRY_INPUT

read -rp "  Pilot or paying? [pilot/paying]: " INSTALL_TYPE_INPUT
INSTALL_TYPE="${INSTALL_TYPE_INPUT:-pilot}"

read -rp "  Notes (optional): " NOTES_INPUT

echo ""
echo -e "  ${BOLD}Confirm:${RESET}"
echo -e "  ${GRAY}Client ID:  ${RESET}${CLIENT_ID}"
echo -e "  ${GRAY}Full name:  ${RESET}${CLIENT_FULL_NAME}"
echo -e "  ${GRAY}Company:    ${RESET}${CLIENT_COMPANY}"
echo -e "  ${GRAY}Email:      ${RESET}${CLIENT_EMAIL}"
echo -e "  ${GRAY}Tier:       ${RESET}${TIER}"
echo -e "  ${GRAY}Type:       ${RESET}${INSTALL_TYPE}"
[[ -n "$EXPIRY_INPUT" ]] && echo -e "  ${GRAY}Expiry:     ${RESET}${EXPIRY_INPUT}"
echo ""
read -rp "  Continue? (y/n): " CONFIRM
[[ "$CONFIRM" =~ ^[Yy] ]] || { echo "Cancelled."; exit 0; }

# ── GENERATE LICENSE KEY ─────────────────────────────────────
section "License Key Generation"

# Generate VELA-XXXX-XXXX-XXXX-XXXX
generate_key() {
  python3 -c "
import secrets, string
chars = string.ascii_uppercase + string.digits
parts = [''.join(secrets.choice(chars) for _ in range(4)) for _ in range(4)]
print('VELA-' + '-'.join(parts))
"
}

hash_key() {
  echo -n "$1" | python3 -c "import sys,hashlib; print(hashlib.sha256(sys.stdin.buffer.read()).hexdigest())"
}

LICENSE_KEY=$(generate_key)
KEY_HASH=$(hash_key "$LICENSE_KEY")
CREATED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)

echo ""
echo -e "  ${GOLD}${BOLD}License Key:${RESET}"
echo -e "  ${BOLD}${LICENSE_KEY}${RESET}"
echo ""
success "Key generated and hashed"

# ── LICENSE SERVER SQL ───────────────────────────────────────
section "License Server — Add This Key"

EXPIRY_SQL="NULL"
[[ -n "$EXPIRY_INPUT" ]] && EXPIRY_SQL="'${EXPIRY_INPUT}'"

NOTES_SQL="NULL"
[[ -n "$NOTES_INPUT" ]] && NOTES_SQL="'${NOTES_INPUT} | ${INSTALL_TYPE}'"

SQL="INSERT INTO licenses (client_id, key_hash, status, tier, expiry, notes) VALUES ('${CLIENT_ID}', '${KEY_HASH}', 'active', '${TIER}', ${EXPIRY_SQL}, ${NOTES_SQL});"

echo ""
echo -e "  ${GOLD}Run on your DigitalOcean droplet:${RESET}"
echo ""
echo -e "  ${BLUE}ssh root@license.vela.run \\${RESET}"
echo -e "  ${BLUE}  'sqlite3 /opt/vela/licenses.db \"${SQL}\"'${RESET}"
echo ""
echo -e "  ${GRAY}Or use admin.py add (prints same SQL):${RESET}"
echo -e "  ${GRAY}  python3 license_server/admin.py add ${CLIENT_ID} --tier ${TIER}${RESET}"
echo ""

# ── CLIENT MANIFEST ──────────────────────────────────────────
section "Client Manifest"

MANIFEST_FILE="${DEPLOY_DIR}/${CLIENT_ID}.conf"
cat > "$MANIFEST_FILE" << EOF
# VELA Client Manifest — ${CLIENT_FULL_NAME}
# Created: ${CREATED_AT}
# ─────────────────────────────────────────

CLIENT_ID="${CLIENT_ID}"
CLIENT_FULL_NAME="${CLIENT_FULL_NAME}"
CLIENT_COMPANY="${CLIENT_COMPANY}"
CLIENT_EMAIL="${CLIENT_EMAIL}"
LICENSE_KEY="${LICENSE_KEY}"
LICENSE_TIER="${TIER}"
INSTALL_TYPE="${INSTALL_TYPE}"
EXPIRY="${EXPIRY_INPUT}"
CREATED_AT="${CREATED_AT}"
NOTES="${NOTES_INPUT}"

# Set after install:
TAILSCALE_IP=""
TAILSCALE_HOSTNAME="vela-${CLIENT_ID}"
INSTALL_DATE=""
ANTHROPIC_ACCOUNT=""
TELEGRAM_BOT=""
TELEGRAM_GROUP_ID=""
EOF

chmod 600 "$MANIFEST_FILE"
success "Manifest saved: ${MANIFEST_FILE}"

# ── TAILSCALE HOSTNAME ───────────────────────────────────────
section "Tailscale"

echo -e "  When running setup_tailscale.sh, enter hostname:"
echo -e "  ${GOLD}${BOLD}vela-${CLIENT_ID}${RESET}"
echo ""
echo -e "  ${GRAY}After install, their machine will appear in your Tailscale dashboard as:${RESET}"
echo -e "  ${GRAY}  vela-${CLIENT_ID} (100.x.x.x)${RESET}"
echo ""
echo -e "  ${GRAY}SSH access after install:${RESET}"
echo -e "  ${BLUE}  ssh [username]@vela-${CLIENT_ID}${RESET}"

# ── DELIVERY CHECKLIST ───────────────────────────────────────
section "Pre-Install Checklist"

echo -e "  Complete these before the install call:\n"
echo -e "  ${GOLD}□${RESET} Send README_First.pdf — client needs 45–90 min to collect credentials"
echo -e "  ${GOLD}□${RESET} Confirm Mac Mini M4 is in hand (16 GB min, 32 GB recommended)"
echo -e "  ${GOLD}□${RESET} Confirm Ethernet cable is connected"
echo -e "  ${GOLD}□${RESET} Confirm Energy Saver is set to Never"
echo -e "  ${GOLD}□${RESET} Add key to license server (SQL above)"
echo -e "  ${GOLD}□${RESET} Schedule install call (block 90 min)"
echo -e "  ${GOLD}□${RESET} Tailscale auth key ready from tailscale.com/admin"

section "Install Call — What to Have Ready"

echo -e "  ${GOLD}License key to give client:${RESET}"
echo -e "  ${BOLD}  ${LICENSE_KEY}${RESET}"
echo ""
echo -e "  ${GRAY}Install command they paste into Terminal:${RESET}"
echo -e "  ${BLUE}  curl -fsSL https://raw.githubusercontent.com/greg442/Vela_Scripts_2/main/install.sh | bash${RESET}"
echo ""
echo -e "  ${GRAY}Your Tailscale SSH to watch/assist:${RESET}"
echo -e "  ${BLUE}  ssh [username]@vela-${CLIENT_ID}${RESET}"
echo ""

section "Post-Install — Update Manifest"

echo -e "  After install, fill in the blanks in:"
echo -e "  ${BLUE}  ${MANIFEST_FILE}${RESET}"
echo ""
echo -e "  ${GRAY}Fields to add: TAILSCALE_IP, INSTALL_DATE, ANTHROPIC_ACCOUNT, TELEGRAM_BOT, TELEGRAM_GROUP_ID${RESET}"
echo ""

hr
echo -e "\n${GOLD}${BOLD}  Provisioning complete for ${CLIENT_FULL_NAME}.${RESET}\n"
echo -e "  ${GRAY}Manifest: ${MANIFEST_FILE}${RESET}"
echo -e "  ${RED}  ⚠️  This file contains a plaintext license key. Keep it secure.${RESET}"
echo ""
