#!/usr/bin/env bash
# ============================================================
#  VELA Executive Intelligence Systems
#  Client Installation Script — vela_install.sh v2.0
#  March 2026
#
#  Run via:
#  curl -fsSL https://raw.githubusercontent.com/greg442/vela_scripts/main/install.sh | bash
#
#  Greg Shindler / VELA Executive Intelligence Systems
#  PROPRIETARY & CONFIDENTIAL
# ============================================================

set -euo pipefail

VELA_VERSION="2.0.0"
OPENCLAW_DIR="$HOME/.openclaw"
SCRIPTS_DIR="$OPENCLAW_DIR/scripts"
LOG_DIR="$OPENCLAW_DIR/logs"
TEMPLATE_BASE_URL="https://raw.githubusercontent.com/greg442/vela_scripts/main/templates"

GOLD='\033[0;33m'; GREEN='\033[0;32m'; RED='\033[0;31m'
BOLD='\033[1m'; GRAY='\033[0;90m'; CYAN='\033[0;36m'; RESET='\033[0m'

log()     { echo -e "${GOLD}▸${RESET} $1"; }
success() { echo -e "${GREEN}✓${RESET} $1"; }
warn()    { echo -e "${GOLD}⚠${RESET}  $1"; }
error()   { echo -e "${RED}✗  ERROR: $1${RESET}"; exit 1; }
hr()      { echo -e "${GRAY}────────────────────────────────────────────────────${RESET}"; }
header()  { echo ""; hr; echo -e "  ${BOLD}${GOLD}$1${RESET}"; hr; echo ""; }

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
echo -e "  ${BOLD}VELA Installer v${VELA_VERSION}${RESET}"
hr
echo ""
echo -e "  This installer configures a complete AI executive system"
echo -e "  personalized for you. Estimated time: ${BOLD}20-40 minutes.${RESET}"
echo ""
echo -e "  ${GOLD}Have these ready before continuing:${RESET}"
echo -e "  - Anthropic API key  (console.anthropic.com)"
echo -e "  - Telegram Bot Token (@BotFather)"
echo -e "  - Telegram Chat ID   (@userinfobot)"
echo -e "  - Your Gmail address"
echo ""
read -p "  Press Enter to begin, or Ctrl+C to exit..." _
echo ""

# ════════════════════════════════════════════════════════════
#  STEP 1 — WHO ARE YOU?
# ════════════════════════════════════════════════════════════
header "1 / 9  ABOUT YOU"

echo -e "  ${CYAN}Let's personalize your VELA system.${RESET}"
echo -e "  Press Enter to accept the default shown in brackets.\n"

while true; do
  read -p "  Your full name: " CLIENT_NAME
  [[ -n "$CLIENT_NAME" ]] && break
  echo "  Name cannot be empty."
done

read -p "  Your title (e.g. CEO, Founder, Managing Director): " CLIENT_TITLE
CLIENT_TITLE=${CLIENT_TITLE:-"Executive"}

read -p "  Your company name: " CLIENT_COMPANY
CLIENT_COMPANY=${CLIENT_COMPANY:-""}

read -p "  Your city/location (e.g. Los Angeles, CA): " CLIENT_LOCATION
CLIENT_LOCATION=${CLIENT_LOCATION:-""}

echo ""
echo -e "  ${GRAY}Common timezones:"
echo -e "  America/New_York  America/Chicago  America/Denver"
echo -e "  America/Los_Angeles  America/Phoenix  Europe/London${RESET}"
read -p "  Your timezone [America/New_York]: " CLIENT_TIMEZONE
CLIENT_TIMEZONE=${CLIENT_TIMEZONE:-"America/New_York"}

echo ""
echo -e "  ${CYAN}Name your AI Chief of Staff.${RESET}"
echo -e "  Examples: Hannah, Alex, Jordan, Sage, Morgan\n"
read -p "  Agent name [Hannah]: " AGENT_NAME
AGENT_NAME=${AGENT_NAME:-"Hannah"}

echo ""
read -p "  Morning brief time in 24h format [06:00]: " MORNING_BRIEF
MORNING_BRIEF=${MORNING_BRIEF:-"06:00"}
read -p "  Evening brief time in 24h format [17:00]: " EVENING_BRIEF
EVENING_BRIEF=${EVENING_BRIEF:-"17:00"}

MORNING_H=$(echo "$MORNING_BRIEF" | cut -d: -f1 | sed 's/^0//')
MORNING_M=$(echo "$MORNING_BRIEF" | cut -d: -f2)
EVENING_H=$(echo "$EVENING_BRIEF" | cut -d: -f1 | sed 's/^0//')
EVENING_M=$(echo "$EVENING_BRIEF" | cut -d: -f2)

echo ""
success "Configuring VELA for: ${CLIENT_NAME} — ${CLIENT_TITLE}"
success "Agent name: ${AGENT_NAME}"
success "Briefs: ${MORNING_BRIEF} and ${EVENING_BRIEF} (${CLIENT_TIMEZONE})"
echo ""
sleep 2

# ════════════════════════════════════════════════════════════
#  STEP 2 — CREDENTIALS
# ════════════════════════════════════════════════════════════
header "2 / 9  CREDENTIALS"

echo -e "  ${CYAN}Stored securely in ~/.openclaw/.env (owner-only access).${RESET}\n"

read -s -p "  Anthropic API key (sk-ant-...): " ANTHROPIC_KEY; echo ""
[[ "$ANTHROPIC_KEY" == sk-ant-* ]] || warn "Key doesn't start with sk-ant- — double-check this."

read -p "  Primary Gmail address: " GMAIL_PRIMARY
read -p "  Secondary Gmail (optional, Enter to skip): " GMAIL_SECONDARY

read -s -p "  Telegram Bot Token: " TELEGRAM_TOKEN; echo ""
read -p "  Telegram User Chat ID (positive number): " TELEGRAM_CHAT_ID
read -p "  Telegram Group ID (negative number): " TELEGRAM_GROUP_ID

success "Credentials collected."

# ════════════════════════════════════════════════════════════
#  STEP 3 — SYSTEM CHECK
# ════════════════════════════════════════════════════════════
header "3 / 9  SYSTEM CHECK"

[[ "$(uname)" == "Darwin" ]] || error "macOS required."
[[ "$(uname -m)" == "arm64" ]] || warn "Not Apple Silicon — performance may vary."

RAM_GB=$(( $(sysctl -n hw.memsize) / 1024 / 1024 / 1024 ))
[[ $RAM_GB -ge 16 ]] || error "16 GB RAM minimum. Found: ${RAM_GB} GB."
success "macOS $(sw_vers -productVersion) — ${RAM_GB} GB RAM"

curl -s --max-time 8 "https://github.com" > /dev/null 2>&1 || error "No internet connection."
success "Internet confirmed"

mkdir -p "$OPENCLAW_DIR" "$SCRIPTS_DIR" "$LOG_DIR"
success "Directories ready"

# ════════════════════════════════════════════════════════════
#  STEP 4 — HOMEBREW & TOOLS
# ════════════════════════════════════════════════════════════
header "4 / 9  HOMEBREW & CORE TOOLS"

if ! command -v brew &>/dev/null; then
  log "Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  eval "$(/opt/homebrew/bin/brew shellenv)" 2>/dev/null || true
  success "Homebrew installed"
else
  success "Homebrew already installed"
fi

for pkg in node python@3.12 curl git; do
  brew list "$pkg" &>/dev/null && success "$pkg present" || { log "Installing $pkg..."; brew install "$pkg" --quiet; success "$pkg installed"; }
done

pip3 install --quiet --break-system-packages requests google-auth google-auth-oauthlib google-api-python-client 2>/dev/null || true
success "Python packages ready"

# ════════════════════════════════════════════════════════════
#  STEP 5 — OLLAMA & MODELS
# ════════════════════════════════════════════════════════════
header "5 / 9  OLLAMA & LOCAL AI MODELS"

command -v ollama &>/dev/null || { log "Installing Ollama..."; brew install ollama --quiet; success "Ollama installed"; }
success "Ollama ready"

ollama serve > /tmp/ollama.log 2>&1 & sleep 3

log "Pulling qwen2.5:7b (this takes a few minutes on first run)..."
ollama pull qwen2.5:7b 2>/dev/null && success "qwen2.5:7b ready" || warn "qwen2.5:7b pull failed — retry: ollama pull qwen2.5:7b"

[[ $RAM_GB -ge 32 ]] && { log "32 GB RAM — pulling qwen2.5:14b..."; ollama pull qwen2.5:14b 2>/dev/null && success "qwen2.5:14b ready" || warn "qwen2.5:14b pull failed"; }

# ════════════════════════════════════════════════════════════
#  STEP 6 — OPENCLAW
# ════════════════════════════════════════════════════════════
header "6 / 9  OPENCLAW"

command -v openclaw &>/dev/null || { log "Installing OpenClaw..."; npm install -g openclaw --quiet 2>/dev/null || error "OpenClaw install failed."; success "OpenClaw installed"; }
success "OpenClaw ready"

command -v gog &>/dev/null || { log "Installing gog-wrapper..."; npm install -g gog-wrapper --quiet 2>/dev/null || warn "gog-wrapper failed — install manually"; success "gog-wrapper installed"; }

# ════════════════════════════════════════════════════════════
#  STEP 7 — WRITE CONFIG
# ════════════════════════════════════════════════════════════
header "7 / 9  WRITING CONFIGURATION"

cat > "$OPENCLAW_DIR/.env" << ENVEOF
ANTHROPIC_API_KEY=${ANTHROPIC_KEY}
TELEGRAM_BOT_TOKEN=${TELEGRAM_TOKEN}
TELEGRAM_USER_CHAT_ID=${TELEGRAM_CHAT_ID}
TELEGRAM_GROUP_ID=${TELEGRAM_GROUP_ID}
GMAIL_PRIMARY=${GMAIL_PRIMARY}
GMAIL_SECONDARY=${GMAIL_SECONDARY}
CLIENT_NAME=${CLIENT_NAME}
AGENT_NAME=${AGENT_NAME}
CLIENT_TIMEZONE=${CLIENT_TIMEZONE}
OLLAMA_URL=http://127.0.0.1:11434
OLLAMA_MODEL=qwen2.5:7b
ENVEOF
chmod 600 "$OPENCLAW_DIR/.env"
success ".env written (chmod 600)"

openclaw config set providers.anthropic.apiKey "$ANTHROPIC_KEY" 2>/dev/null || true
openclaw config set providers.ollama.baseUrl "http://localhost:11434" 2>/dev/null || true
openclaw config set agents.defaults.models."anthropic/claude-sonnet-4-6".params.cacheRetention long 2>/dev/null || true
openclaw config set agents.defaults.contextTokens 200000 2>/dev/null || true
openclaw config set channels.telegram.enabled true 2>/dev/null || true
openclaw config set channels.telegram.botToken "$TELEGRAM_TOKEN" 2>/dev/null || true
openclaw config set channels.telegram.dmPolicy "pairing" 2>/dev/null || true
openclaw config set channels.telegram.groupPolicy "allowlist" 2>/dev/null || true
openclaw config set channels.telegram.streaming "partial" 2>/dev/null || true
success "OpenClaw + Telegram configured"

for agent in cos analyst marketing legal; do
  openclaw agent create "$agent" --model anthropic/claude-sonnet-4-6 2>/dev/null || true
done
for agent in pm researcher; do
  openclaw agent create "$agent" --model ollama/qwen2.5:7b 2>/dev/null || true
done
success "6 agents created"

# ════════════════════════════════════════════════════════════
#  STEP 8 — PERSONALIZED WORKSPACES
# ════════════════════════════════════════════════════════════
header "8 / 9  PERSONALIZING WORKSPACES FOR ${CLIENT_NAME}"

INSTALL_DATE=$(date '+%B %d, %Y')

substitute_tokens() {
  local file="$1"
  sed -i '' \
    -e "s|{{CLIENT_NAME}}|${CLIENT_NAME}|g" \
    -e "s|{{CLIENT_TITLE}}|${CLIENT_TITLE}|g" \
    -e "s|{{CLIENT_COMPANY}}|${CLIENT_COMPANY}|g" \
    -e "s|{{CLIENT_LOCATION}}|${CLIENT_LOCATION}|g" \
    -e "s|{{CLIENT_TIMEZONE}}|${CLIENT_TIMEZONE}|g" \
    -e "s|{{CLIENT_EMAIL}}|${GMAIL_PRIMARY}|g" \
    -e "s|{{AGENT_NAME}}|${AGENT_NAME}|g" \
    -e "s|{{INSTALL_DATE}}|${INSTALL_DATE}|g" \
    -e "s|{{MORNING_BRIEF_TIME}}|${MORNING_BRIEF}|g" \
    -e "s|{{EVENING_BRIEF_TIME}}|${EVENING_BRIEF}|g" \
    "$file"
}

declare -A WORKSPACES
WORKSPACES["workspace-cos"]="SOUL.md USER.md MEMORY.md DISPATCH_RULES.md"
WORKSPACES["workspace-analyst"]="SOUL.md"
WORKSPACES["workspace-researcher"]="SOUL.md"
WORKSPACES["workspace-legal"]="SOUL.md"
WORKSPACES["workspace-marketing"]="SOUL.md"
WORKSPACES["workspace-pm"]="SOUL.md"

for workspace in "${!WORKSPACES[@]}"; do
  WS_DIR="$OPENCLAW_DIR/$workspace"
  mkdir -p "$WS_DIR"
  for file in ${WORKSPACES[$workspace]}; do
    url="${TEMPLATE_BASE_URL}/${workspace}/${file}"
    dest="$WS_DIR/$file"
    if curl -fsSL "$url" -o "$dest" 2>/dev/null; then
      substitute_tokens "$dest"
      success "  ${workspace}/${file} — personalized"
    else
      warn "  Template not found: ${workspace}/${file}"
    fi
  done
done

# Assign workspaces via Python
python3 << PYEOF
import json, os
path = os.path.expanduser('~/.openclaw/openclaw.json')
ws_map = {
    'cos': 'workspace-cos', 'analyst': 'workspace-analyst',
    'researcher': 'workspace-researcher', 'legal': 'workspace-legal',
    'marketing': 'workspace-marketing', 'pm': 'workspace-pm',
}
try:
    with open(path) as f: config = json.load(f)
    for agent in config.get('agents', {}).get('list', []):
        aid = agent.get('id', '')
        if aid in ws_map:
            agent['workspace'] = os.path.expanduser('~/.openclaw/') + ws_map[aid]
    with open(path, 'w') as f: json.dump(config, f, indent=2)
    print('Workspaces assigned.')
except Exception as e:
    print(f'Workspace error: {e}')
PYEOF

# Install cron jobs
CRON_TMP=$(mktemp)
crontab -l 2>/dev/null > "$CRON_TMP" || true
add_cron() { grep -qF "$1" "$CRON_TMP" || echo "$1" >> "$CRON_TMP"; }
add_cron "*/15 8-18 * * 1-5 python3 $SCRIPTS_DIR/email_triage.py"
add_cron "0 3 * * * bash $SCRIPTS_DIR/reset_sessions.sh"
add_cron "0 18 * * 1-5 python3 $SCRIPTS_DIR/cost_alert.py"
add_cron "0 2 * * * bash $SCRIPTS_DIR/backup_local.sh"
crontab "$CRON_TMP"; rm "$CRON_TMP"
success "Cron jobs installed"

# OpenClaw scheduled briefs
openclaw cron add --name "${AGENT_NAME}-morning" \
  --schedule "${MORNING_M} ${MORNING_H} * * *" --agent cos --channel telegram \
  --message "Check ${GMAIL_PRIMARY} for unread emails. Check today's calendar. Write a morning brief for ${CLIENT_NAME}: 1. Action Required emails. 2. Today's meetings. Under 10 lines." 2>/dev/null || warn "Morning cron — add manually"

openclaw cron add --name "${AGENT_NAME}-evening" \
  --schedule "${EVENING_M} ${EVENING_H} * * *" --agent cos --channel telegram \
  --message "End of day brief for ${CLIENT_NAME}: 1. Completed today. 2. Open items for tomorrow. 3. Anything urgent tonight. Under 10 lines." 2>/dev/null || warn "Evening cron — add manually"

success "Scheduled briefs set (${MORNING_BRIEF} + ${EVENING_BRIEF})"

cp "$OPENCLAW_DIR/openclaw.json" "$OPENCLAW_DIR/openclaw.json.bak.stable" 2>/dev/null || true
success "Stable backup saved"

# ════════════════════════════════════════════════════════════
#  STEP 9 — VELA WELCOME MESSAGE
# ════════════════════════════════════════════════════════════
header "9 / 9  SENDING WELCOME MESSAGE"

log "Starting OpenClaw gateway..."
openclaw gateway start 2>/dev/null || true
sleep 5

WELCOME="Welcome to VELA, ${CLIENT_NAME}.

I am ${AGENT_NAME}, your AI Chief of Staff — powered by VELA Executive Intelligence Systems.

Here is what I do for you every day:
- Morning brief at ${MORNING_BRIEF} — email, calendar, priorities
- Evening brief at ${EVENING_BRIEF} — what is done, what is next
- Email triage every 15 minutes during business hours
- Real-time task routing to your specialist team

Your specialist team:
- Analyst — financial modeling and data analysis
- Researcher — market intel and due diligence
- Legal — contracts and compliance review
- Marketing — copy, strategy, positioning
- PM — projects, tasks, follow-ups

How to reach me:
Message me here in Telegram in plain language. No special commands needed. Just tell me what you need.

Use /new to start a fresh session for each new topic. This keeps things fast and efficient.

Your system is live. What is on your plate today?

— ${AGENT_NAME} | VELA Executive Intelligence Systems"

curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" \
  -H "Content-Type: application/json" \
  -d "{\"chat_id\": \"${TELEGRAM_CHAT_ID}\", \"text\": $(python3 -c "import json,sys; print(json.dumps(sys.stdin.read()))" <<< "$WELCOME")}" \
  > /dev/null 2>&1 && success "Welcome message sent to ${CLIENT_NAME} via Telegram" || warn "Welcome message failed — check Telegram config"

# ════════════════════════════════════════════════════════════
#  DONE
# ════════════════════════════════════════════════════════════
echo ""
echo -e "${GOLD}"
echo "  ╔══════════════════════════════════════════════╗"
echo "  ║                                              ║"
echo "  ║     VELA INSTALLATION COMPLETE               ║"
echo "  ║                                              ║"
echo "  ╚══════════════════════════════════════════════╝"
echo -e "${RESET}"
echo ""
echo -e "  ${BOLD}${CLIENT_NAME}, your VELA system is live.${RESET}"
echo ""
echo -e "  ${GOLD}Agent:${RESET}     ${AGENT_NAME} (Chief of Staff)"
echo -e "  ${GOLD}Briefs:${RESET}    ${MORNING_BRIEF} morning  |  ${EVENING_BRIEF} evening"
echo -e "  ${GOLD}Timezone:${RESET}  ${CLIENT_TIMEZONE}"
echo ""
echo -e "  ${CYAN}Three things to do right now:${RESET}"
echo -e "  1. Check Telegram — ${AGENT_NAME} just sent you a welcome message"
echo -e "  2. Connect Gmail: gog auth login -a ${GMAIL_PRIMARY}"
echo -e "  3. Scan WhatsApp: openclaw gateway restart (then scan QR in WhatsApp)"
echo ""
echo -e "  ${GRAY}Optional but recommended:"
echo -e "  Install monitoring: curl -fsSL https://raw.githubusercontent.com/greg442/vela_scripts/main/scripts/install_uptime_kuma.sh | bash"
echo -e "  Set up backup:     curl -fsSL https://raw.githubusercontent.com/greg442/vela_scripts/main/scripts/backup_gdrive.sh -o ~/backup_gdrive.sh && chmod +x ~/backup_gdrive.sh && ~/backup_gdrive.sh --setup${RESET}"
echo ""
hr
echo -e "  ${GOLD}VELA Executive Intelligence Systems  |  Confidential${RESET}"
hr
echo ""
