#!/usr/bin/env bash
# backup_intelligence.sh — Daily backup of hannah.db → Google Drive
# Cron: 2AM daily

set -euo pipefail

DB_PATH="$HOME/.openclaw/hannah.db"
BACKUP_DIR="$HOME/.openclaw/backups"
DRIVE_FOLDER="VELA Greg/Backups"
KEEP=7

TIMESTAMP=$(date -u +"%Y-%m-%dT%H%M%SZ")
BACKUP_FILENAME="hannah_${TIMESTAMP}.db"
BACKUP_PATH="${BACKUP_DIR}/${BACKUP_FILENAME}"

log() { echo "[$(date -u +%H:%M:%S)] $*"; }

if [ ! -f "$DB_PATH" ]; then
    log "ERROR: Database not found at $DB_PATH"
    exit 1
fi

mkdir -p "$BACKUP_DIR"

log "Creating backup: $BACKUP_FILENAME"
sqlite3 "$DB_PATH" ".backup '${BACKUP_PATH}'"
SIZE=$(du -h "$BACKUP_PATH" | cut -f1)
log "Backup created: $SIZE"

log "Uploading to Google Drive: $DRIVE_FOLDER/$BACKUP_FILENAME"
if command -v gog-wrapper &>/dev/null; then
    gog-wrapper drive upload \
        -a "cos.gregshindler@gmail.com" \
        --file "$BACKUP_PATH" \
        --folder "$DRIVE_FOLDER" \
        --filename "$BACKUP_FILENAME" 2>&1 || {
        log "WARNING: Drive upload failed — backup retained locally"
        exit 0
    }
    log "Upload complete"
else
    log "WARNING: gog-wrapper not found — local backup only"
fi

log "Pruning local backups (keeping last $KEEP)"
ls -t "${BACKUP_DIR}"/hannah_*.db 2>/dev/null | tail -n +$((KEEP + 1)) | xargs -r rm -f
REMAINING=$(ls "${BACKUP_DIR}"/hannah_*.db 2>/dev/null | wc -l | tr -d ' ')
log "Local backups retained: $REMAINING"

PROACTIVE_LOG="$HOME/.openclaw/workspace-cos/PROACTIVE_LOG.md"
if [ -f "$PROACTIVE_LOG" ]; then
    echo "- [${TIMESTAMP}] BACKUP: hannah.db -> Drive ($DRIVE_FOLDER/$BACKUP_FILENAME) — $SIZE" >> "$PROACTIVE_LOG"
fi

log "Backup complete: $BACKUP_FILENAME"
