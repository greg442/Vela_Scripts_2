#!/bin/bash
# ─────────────────────────────────────────────
# VELA Monitoring Setup
# Run once per client at installation
# ─────────────────────────────────────────────

set -e

SCRIPTS_DIR="$HOME/.openclaw/scripts"
CONFIG_FILE="$HOME/.openclaw/vela_client.conf"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  VELA Monitoring Setup"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

read -p "Client name (e.g. 'John Smith'): " CLIENT_NAME
read -p "VELA alert bot token: " ALERT_BOT_TOKEN
read -p "VELA alert chat ID: " ALERT_CHAT_ID
read -p "VELA tier (turnkey/diy): " VELA_TIER

INSTALL_DATE=$(date '+%Y-%m-%d')
MONITORING_EXPIRES=$(date -v+1y '+%Y-%m-%d' 2>/dev/null || date --date='+1 year' '+%Y-%m-%d')

cat > "$CONFIG_FILE" << EOF
CLIENT_NAME="${CLIENT_NAME}"
ALERT_BOT_TOKEN="${ALERT_BOT_TOKEN}"
ALERT_CHAT_ID="${ALERT_CHAT_ID}"
INSTALL_DATE="${INSTALL_DATE}"
VELA_TIER="${VELA_TIER}"
MONITORING_EXPIRES="${MONITORING_EXPIRES}"
EOF

chmod 600 "$CONFIG_FILE"
echo "✓ Config saved"

HEALTH_SCRIPT="$SCRIPTS_DIR/health_check.sh"
cp "$(dirname "$0")/health_check.sh" "$HEALTH_SCRIPT"
chmod +x "$HEALTH_SCRIPT"
echo "✓ Health check installed"

CRON_TMP=$(mktemp)
crontab -l 2>/dev/null > "$CRON_TMP" || true
grep -v "health_check.sh" "$CRON_TMP" > "${CRON_TMP}.clean" && mv "${CRON_TMP}.clean" "$CRON_TMP"
echo "*/15 * * * * bash $HEALTH_SCRIPT >> $HOME/.openclaw/logs/health_check.log 2>&1" >> "$CRON_TMP"
crontab "$CRON_TMP"
rm "$CRON_TMP"
echo "✓ Cron installed (every 15 minutes)"

source "$CONFIG_FILE"
RESULT=$(curl -s -X POST "https://api.telegram.org/bot${ALERT_BOT_TOKEN}/sendMessage" \
  -d chat_id="${ALERT_CHAT_ID}" \
  -d parse_mode="HTML" \
  -d text="✅ <b>VELA Monitoring Active — ${CLIENT_NAME}</b>%0A%0AHealth checks every 15 min.%0AInstalled: ${INSTALL_DATE}%0AExpires: ${MONITORING_EXPIRES}")

echo "$RESULT" | grep -q '"ok":true' && echo "✓ Test alert sent" || echo "✗ Alert failed — check token and chat ID"

echo ""
echo "✓ Monitoring setup complete for: $CLIENT_NAME"
echo "  Next: run setup_tailscale.sh"
echo ""
