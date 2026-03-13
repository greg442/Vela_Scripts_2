#!/bin/bash
# ─────────────────────────────────────────────
# VELA Tailscale Setup
# Installs and authenticates Tailscale for
# remote monitoring access
# ─────────────────────────────────────────────

set -e

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  VELA — Remote Access Setup (Tailscale)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if command -v tailscale &> /dev/null; then
  echo "✓ Tailscale already installed"
else
  echo "→ Installing Tailscale..."
  if command -v brew &> /dev/null; then
    brew install --cask tailscale
    echo "✓ Tailscale installed"
  else
    echo "ERROR: Homebrew not found."
    exit 1
  fi
fi

CONFIG_FILE="$HOME/.openclaw/vela_client.conf"
[ -f "$CONFIG_FILE" ] && source "$CONFIG_FILE"
HOSTNAME="vela-${CLIENT_NAME:-client}"
HOSTNAME="${HOSTNAME,,}"
HOSTNAME="${HOSTNAME// /-}"

read -p "Enter VELA Tailscale auth key (tskey-auth-...): " AUTH_KEY

if [ -z "$AUTH_KEY" ]; then
  echo "No auth key provided. Run 'sudo tailscale up' manually."
  exit 0
fi

echo "→ Authenticating as: $HOSTNAME"
sudo tailscale up --authkey="$AUTH_KEY" --hostname="$HOSTNAME" --accept-routes

TAILSCALE_IP=$(tailscale ip -4 2>/dev/null || echo "unknown")
echo ""
echo "✓ Tailscale connected"
echo "  IP:       $TAILSCALE_IP"
echo "  Hostname: $HOSTNAME"
echo ""
