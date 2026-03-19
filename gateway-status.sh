#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# VELA Executive Intelligence Systems — Gateway Status Overview
# vela_scripts/gateway-status.sh
#
# Shows all registered gateway instances, their ports, and live status.
# Designed to be readable on a phone SSH session at 2 AM.
#
# Usage: ./gateway-status.sh
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

REGISTRY_FILE="$HOME/.openclaw/vela-port-registry.json"
UID_NUM=$(id -u)

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

if [[ ! -f "$REGISTRY_FILE" ]]; then
  echo "No registry found at $REGISTRY_FILE"
  echo "Run install-gateway.sh to create instances."
  exit 1
fi

echo ""
echo -e "${BOLD}VELA Gateway Status${NC}  $(date '+%Y-%m-%d %H:%M:%S %Z')"
echo -e "────────────────────────────────────────────────────────"
printf "${BOLD}%-20s %-7s %-10s %-8s %s${NC}\n" "INSTANCE" "PORT" "SERVICE" "PID" "UPTIME"
echo -e "────────────────────────────────────────────────────────"

python3 -c "
import json, subprocess, re

with open('$REGISTRY_FILE') as f:
    reg = json.load(f)

for inst in reg.get('instances', []):
    name = inst['name']
    port = inst['port']
    service = inst['service']

    # Check if port is listening
    try:
        result = subprocess.run(
            ['lsof', '-ti', ':' + str(port), '-sTCP:LISTEN'],
            capture_output=True, text=True, timeout=3
        )
        pid = result.stdout.strip().split('\n')[0] if result.returncode == 0 else ''
    except:
        pid = ''

    # Check launchctl service state
    try:
        result = subprocess.run(
            ['launchctl', 'print', f'gui/$UID_NUM/{service}'],
            capture_output=True, text=True, timeout=3
        )
        if result.returncode == 0:
            state_match = re.search(r'state\s*=\s*(\S+)', result.stdout)
            state = state_match.group(1) if state_match else 'loaded'
        else:
            state = 'unloaded'
    except:
        state = 'unknown'

    # Determine status indicator
    if pid and state in ('active', 'running', 'loaded'):
        status = '\033[0;32m●\033[0m'  # green
        status_text = 'UP'
    elif pid:
        status = '\033[1;33m●\033[0m'  # yellow
        status_text = 'ORPHAN'
    else:
        status = '\033[0;31m●\033[0m'  # red
        status_text = 'DOWN'
        pid = '-'

    print(f'{status} {name:<19} {port:<7} {status_text:<10} {pid:<8} {inst.get(\"config\", \"\")}')
"

echo -e "────────────────────────────────────────────────────────"

# Tailscale info
if command -v tailscale &>/dev/null; then
  TS_IP=$(tailscale ip -4 2>/dev/null || echo "not connected")
  echo -e "${DIM}Tailscale IP: ${TS_IP}${NC}"
  echo -e "${DIM}SSH: ssh $(whoami)@${TS_IP}${NC}"
fi

echo ""
echo -e "${DIM}Restart a gateway:  launchctl kickstart -k gui/${UID_NUM}/ai.openclaw.gateway.<name>${NC}"
echo -e "${DIM}Restart all:        for svc in \$(cat $REGISTRY_FILE | python3 -c \"import json,sys;[print(i['service']) for i in json.load(sys.stdin)['instances']]\"); do launchctl kickstart -k gui/${UID_NUM}/\$svc; done${NC}"
echo ""
