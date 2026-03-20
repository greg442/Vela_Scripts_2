#!/usr/bin/env bash
# VELA Session Reset — clears bloated session files over 100KB
SESSION_DIR="$HOME/.openclaw/agents"
LOG="$HOME/.openclaw/logs/session-reset.log"
TS=$(date '+%Y-%m-%d %H:%M:%S')
COUNT=0
if [[ -d "$SESSION_DIR" ]]; then
  while IFS= read -r f; do
    echo "[$TS] Resetting: $f ($(du -h "$f" | cut -f1))" >> "$LOG"
    echo '{"messages":[]}' > "$f"
    ((COUNT++)) || true
  done < <(find "$SESSION_DIR" -name "*.json" -size +100k)
fi
echo "[$TS] Session reset complete. Files reset: $COUNT" >> "$LOG"
