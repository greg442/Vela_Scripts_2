#!/usr/bin/env bash
# VELA Local Backup — archives ~/.openclaw to ~/.openclaw/backups/
BACKUP_DIR="$HOME/.openclaw/backups"
TS=$(date '+%Y%m%d_%H%M%S')
ARCHIVE="$BACKUP_DIR/openclaw_backup_$TS.tar.gz"
LOG="$HOME/.openclaw/logs/backup.log"
mkdir -p "$BACKUP_DIR"
tar -czf "$ARCHIVE" \
    --exclude="$HOME/.openclaw/backups" \
    --exclude="$HOME/.openclaw/agents/*/sessions" \
    "$HOME/.openclaw/" 2>/dev/null
SIZE=$(du -h "$ARCHIVE" | cut -f1)
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Local backup: $ARCHIVE ($SIZE)" >> "$LOG"
# Keep last 7 local backups
ls -t "$BACKUP_DIR"/openclaw_backup_*.tar.gz 2>/dev/null | tail -n +8 | xargs rm -f 2>/dev/null || true
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Local backup complete." >> "$LOG"
