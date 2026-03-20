#!/usr/bin/env bash
# ============================================================
#  VELA Executive Intelligence Systems
#  Google Drive Backup — Setup & Runtime Script
#  Version 1.0 — March 2026
#
#  Uses rclone to back up ~/.openclaw to Google Drive
#  Target folder: VELA Backups (ID: 1LtIKxp0sHq60IOSZgMwUGSjF1-0lsQOC)
#
#  First run: sets up rclone remote (requires browser auth)
#  Subsequent runs: executes backup silently via cron
#
#  Usage:
#    First run:  ./backup_gdrive.sh --setup
#    Manual run: ./backup_gdrive.sh
#    Via cron:   0 2 * * * /path/to/backup_gdrive.sh
# ============================================================

set -euo pipefail

# ── CONFIG ──────────────────────────────────────────────────
REMOTE_NAME="vela-gdrive"
GDRIVE_FOLDER_ID="1LtIKxp0sHq60IOSZgMwUGSjF1-0lsQOC"
LOCAL_DIR="$HOME/.openclaw"
REMOTE_PATH="${REMOTE_NAME}:VELA-Backups"
LOG_FILE="$HOME/.openclaw/logs/gdrive-backup.log"
RETENTION_DAYS=14
TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
TELEGRAM_CHAT_ID="${TELEGRAM_USER_CHAT_ID:-}"

# Load .env if present
ENV_FILE="$HOME/.openclaw/.env"
if [[ -f "$ENV_FILE" ]]; then
  set -a; source "$ENV_FILE"; set +a
  TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
  TELEGRAM_CHAT_ID="${TELEGRAM_USER_CHAT_ID:-}"
fi

GOLD='\033[0;33m'
GREEN='\033[0;32m'
RED='\033[0;31m'
BOLD='\033[1m'
GRAY='\033[0;90m'
RESET='\033[0m'

log()     { echo -e "${GOLD}▸${RESET} $1"; }
success() { echo -e "${GREEN}✓${RESET} $1"; }
warn()    { echo -e "${GOLD}⚠${RESET}  $1"; }
error()   { echo -e "${RED}✗${RESET} $1" >&2; exit 1; }
ts()      { date '+%Y-%m-%d %H:%M:%S'; }

# ── TELEGRAM NOTIFY ─────────────────────────────────────────
notify() {
  local msg="$1"
  if [[ -n "$TELEGRAM_BOT_TOKEN" && -n "$TELEGRAM_CHAT_ID" ]]; then
    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
      -d "chat_id=${TELEGRAM_CHAT_ID}" \
      --data-urlencode "text=${msg}" \
      -o /dev/null 2>/dev/null || true
  fi
}

# ── SETUP MODE ──────────────────────────────────────────────
if [[ "${1:-}" == "--setup" ]]; then
  echo ""
  echo -e "${BOLD}${GOLD}VELA Google Drive Backup — First-Time Setup${RESET}"
  echo ""

  # Install rclone
  if ! command -v rclone &>/dev/null; then
    log "Installing rclone..."
    brew install rclone --quiet
    success "rclone installed: $(rclone --version | head -1)"
  else
    success "rclone already installed: $(rclone --version | head -1)"
  fi

  echo ""
  echo -e "${BOLD}Configuring Google Drive remote...${RESET}"
  echo -e "${GRAY}A browser window will open to authenticate with Google."
  echo -e "Sign in with the Google account that owns the VELA Backups folder.${RESET}"
  echo ""

  # Check if remote already exists
  if rclone listremotes 2>/dev/null | grep -q "^${REMOTE_NAME}:"; then
    warn "Remote '${REMOTE_NAME}' already configured."
    read -p "  Reconfigure? (y/n): " RECONFIG
    if [[ "$RECONFIG" != "y" ]]; then
      success "Using existing remote '${REMOTE_NAME}'"
      echo ""
      echo -e "Run ${BOLD}./backup_gdrive.sh${RESET} to execute a manual backup now."
      exit 0
    fi
    rclone config delete "${REMOTE_NAME}" 2>/dev/null || true
  fi

  # Non-interactive rclone config using --drive-root-folder-id to pin to your folder
  log "Opening browser for Google authentication..."
  rclone config create "${REMOTE_NAME}" drive \
    scope=drive \
    root_folder_id="${GDRIVE_FOLDER_ID}"

  # Verify
  if rclone lsd "${REMOTE_PATH}" &>/dev/null 2>&1; then
    success "Google Drive remote configured and accessible"
  else
    warn "Could not list remote — try: rclone lsd ${REMOTE_PATH}"
    warn "If the folder is empty that is fine — first backup will create structure."
  fi

  # Add to cron
  echo ""
  log "Adding nightly backup cron job (2am daily)..."
  SCRIPT_PATH="$(realpath "$0")"
  CRON_TMP=$(mktemp)
  crontab -l 2>/dev/null > "$CRON_TMP" || true
  grep -v "backup_gdrive\|gdrive-backup" "$CRON_TMP" > "${CRON_TMP}.clean" || true
  mv "${CRON_TMP}.clean" "$CRON_TMP"
  echo "# VELA Google Drive backup — nightly 2am" >> "$CRON_TMP"
  echo "0 2 * * * ${SCRIPT_PATH} >> ${LOG_FILE} 2>&1" >> "$CRON_TMP"
  crontab "$CRON_TMP"
  rm -f "$CRON_TMP"
  success "Cron job installed: runs nightly at 2am"

  echo ""
  echo -e "${BOLD}${GREEN}Setup complete.${RESET}"
  echo -e "  Remote:   ${REMOTE_NAME}:VELA-Backups"
  echo -e "  Schedule: Nightly at 2am"
  echo -e "  Logs:     ${LOG_FILE}"
  echo ""
  echo -e "Run a test backup now: ${BOLD}./backup_gdrive.sh${RESET}"
  echo ""
  exit 0
fi

# ── BACKUP MODE (default / cron) ────────────────────────────
mkdir -p "$(dirname "$LOG_FILE")"
echo "[$(ts)] ── VELA Google Drive Backup Started ──" >> "$LOG_FILE"

# Verify rclone exists
if ! command -v rclone &>/dev/null; then
  MSG="❌ VELA Backup FAILED: rclone not installed. Run: ./backup_gdrive.sh --setup"
  echo "[$(ts)] ERROR: $MSG" >> "$LOG_FILE"
  notify "$MSG"
  exit 1
fi

# Verify remote is configured
if ! rclone listremotes 2>/dev/null | grep -q "^${REMOTE_NAME}:"; then
  MSG="❌ VELA Backup FAILED: rclone remote '${REMOTE_NAME}' not configured. Run: ./backup_gdrive.sh --setup"
  echo "[$(ts)] ERROR: $MSG" >> "$LOG_FILE"
  notify "$MSG"
  exit 1
fi

# Create timestamped archive of .openclaw (exclude sessions + old backups)
TS_STAMP=$(date '+%Y%m%d_%H%M%S')
ARCHIVE_NAME="vela_backup_${TS_STAMP}.tar.gz"
TEMP_ARCHIVE="/tmp/${ARCHIVE_NAME}"

echo "[$(ts)] Creating local archive: $ARCHIVE_NAME" >> "$LOG_FILE"

tar -czf "$TEMP_ARCHIVE" \
  --exclude="${LOCAL_DIR}/backups" \
  --exclude="${LOCAL_DIR}/agents/*/sessions" \
  --exclude="${LOCAL_DIR}/logs/triage.log" \
  "$LOCAL_DIR" 2>> "$LOG_FILE" || {
    MSG="❌ VELA Backup FAILED: Could not create archive. Check ${LOG_FILE}"
    echo "[$(ts)] ERROR: archive creation failed" >> "$LOG_FILE"
    notify "$MSG"
    rm -f "$TEMP_ARCHIVE"
    exit 1
  }

ARCHIVE_SIZE=$(du -h "$TEMP_ARCHIVE" | cut -f1)
echo "[$(ts)] Archive created: $ARCHIVE_SIZE" >> "$LOG_FILE"

# Upload to Google Drive
echo "[$(ts)] Uploading to Google Drive: ${REMOTE_PATH}/${ARCHIVE_NAME}" >> "$LOG_FILE"

rclone copy "$TEMP_ARCHIVE" "${REMOTE_PATH}/" \
  --log-level INFO \
  --log-file "$LOG_FILE" \
  --timeout 60s \
  --retries 3 || {
    MSG="❌ VELA Backup FAILED: Upload error. Check ${LOG_FILE}"
    echo "[$(ts)] ERROR: rclone upload failed" >> "$LOG_FILE"
    notify "$MSG"
    rm -f "$TEMP_ARCHIVE"
    exit 1
  }

rm -f "$TEMP_ARCHIVE"
echo "[$(ts)] Upload complete. Archive size: $ARCHIVE_SIZE" >> "$LOG_FILE"

# Purge old backups from Google Drive (keep RETENTION_DAYS)
echo "[$(ts)] Pruning backups older than ${RETENTION_DAYS} days from Google Drive..." >> "$LOG_FILE"
rclone delete "${REMOTE_PATH}/" \
  --min-age "${RETENTION_DAYS}d" \
  --log-level INFO \
  --log-file "$LOG_FILE" 2>/dev/null || true

# Count remaining backups on Drive
REMOTE_COUNT=$(rclone ls "${REMOTE_PATH}/" 2>/dev/null | wc -l | tr -d ' ')
echo "[$(ts)] Remote backup count: ${REMOTE_COUNT}" >> "$LOG_FILE"

# Success notification
MSG="✅ VELA Backup complete — ${ARCHIVE_SIZE} uploaded to Google Drive. ${REMOTE_COUNT} backups on file."
echo "[$(ts)] $MSG" >> "$LOG_FILE"
echo "[$(ts)] ── Backup Finished ──" >> "$LOG_FILE"
notify "$MSG"

echo ""
success "$MSG"
echo ""
