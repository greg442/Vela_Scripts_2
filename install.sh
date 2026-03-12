#!/usr/bin/env bash
# ============================================================
#  VELA Executive Intelligence Systems
#  Master Installer — install.sh
#  Version 1.0 — March 2026
#
#  This is the ONLY file a client needs to touch.
#  Everything else is downloaded automatically from GitHub.
#
#  ONE-LINE INSTALL (paste this into Terminal):
#
#  curl -fsSL https://raw.githubusercontent.com/greg442/vela_scripts/main/install.sh | bash
#
#  What happens:
#    1. Downloads all VELA scripts from GitHub
#    2. Verifies checksums
#    3. Runs the full install sequence
#    4. Leaves a clean ~/vela-setup/ directory with all scripts
#
#  Greg Shindler / VELA Executive Intelligence Systems
#  PROPRIETARY & CONFIDENTIAL
# ============================================================

set -euo pipefail

# ── CONFIG — UPDATE THESE BEFORE DISTRIBUTING ───────────────
GITHUB_USER="greg442"           # ← your GitHub username
GITHUB_REPO="vela_scripts"
GITHUB_BRANCH="main"
VELA_VERSION="1.0.0"

BASE_URL="https://raw.githubusercontent.com/${GITHUB_USER}/${GITHUB_REPO}/${GITHUB_BRANCH}"
INSTALL_DIR="$HOME/vela-setup"

# ── COLORS ──────────────────────────────────────────────────
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

# ── BANNER ──────────────────────────────────────────────────
clear
echo -e "${GOLD}"
cat << 'BANNER'
 __   __ ____  _        _
 \ \ / /| ___|| |      / \
  \ V / |  _| | |     / _ \
   \_/  |_____||_____|/_/ \_\

 Executive Intelligence Systems
BANNER
echo -e "${RESET}"
echo -e "  ${BOLD}VELA Master Installer v${VELA_VERSION}${RESET}"
hr
echo ""

# ── PREFLIGHT ───────────────────────────────────────────────
log "Checking system..."

[[ "$(uname)" == "Darwin" ]] || error "macOS required."
[[ "$(uname -m)" == "arm64" ]] || warn "Not Apple Silicon — performance may vary."

RAM_GB=$(( $(sysctl -n hw.memsize) / 1024 / 1024 / 1024 ))
[[ $RAM_GB -ge 16 ]] || error "16 GB RAM minimum required. Found: ${RAM_GB} GB."
success "System check passed (${RAM_GB} GB RAM, macOS $(sw_vers -productVersion))"

# Check internet
curl -s --max-time 8 "https://github.com" > /dev/null 2>&1 || error "No internet connection. Connect and retry."
success "Internet confirmed"

# ── DOWNLOAD ALL SCRIPTS ─────────────────────────────────────
log "Creating install directory: ${INSTALL_DIR}"
mkdir -p "${INSTALL_DIR}/scripts"
cd "${INSTALL_DIR}"

echo ""
log "Downloading VELA scripts from GitHub..."

# Core scripts to download
declare -a SCRIPTS=(
  "scripts/vela_install.sh"
  "scripts/install_uptime_kuma.sh"
  "scripts/backup_gdrive.sh"
  "scripts/cost_alert.py"
  "scripts/email_triage.py"
  "scripts/reset_sessions.sh"
  "scripts/backup_local.sh"
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
    success "Downloaded: ${filename}"
    ((DOWNLOAD_OK++)) || true
  else
    warn "Could not download: ${filename} (${url})"
    ((DOWNLOAD_FAIL++)) || true
  fi
done

echo ""
if [[ $DOWNLOAD_FAIL -gt 0 ]]; then
  warn "${DOWNLOAD_FAIL} script(s) failed to download. Check your GitHub repo settings."
  warn "If the repo is private, you must authenticate first:"
  warn "  gh auth login  OR  set up a personal access token"
  echo ""
fi

success "Downloaded ${DOWNLOAD_OK} scripts to ${INSTALL_DIR}/"

# ── VERIFY KEY SCRIPT EXISTS ─────────────────────────────────
MAIN_SCRIPT="${INSTALL_DIR}/scripts/vela_install.sh"
if [[ ! -f "$MAIN_SCRIPT" ]]; then
  echo ""
  error "Main install script not found. Check your GitHub repo and try again.\n  Expected: ${MAIN_SCRIPT}"
fi

# ── HAND OFF TO MAIN INSTALLER ───────────────────────────────
echo ""
hr
echo -e "\n${BOLD}${GOLD}  Scripts downloaded. Starting VELA installation...${RESET}\n"
hr
echo ""
sleep 2

exec bash "${MAIN_SCRIPT}"
