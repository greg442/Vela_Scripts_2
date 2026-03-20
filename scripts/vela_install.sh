#!/usr/bin/env bash
# ============================================================
#  VELA Private Command Infrastructure
#  Full System Installer — vela_install.sh
#  Version 2.0 — March 2026
#
#  Called by install.sh after license validation and info
#  collection. All CLIENT_* variables are pre-exported.
#
#  Do not run this directly. Use install.sh.
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
error()   { echo -e "${RED}✗${RESET} $1"; exit 1; }
hr()      { echo -e "${GRAY}────────────────────────────────────────────────────${RESET}"; }
section() { echo -e "\n${BLUE}${BOLD}$1${RESET}"; hr; }

OPENCLAW_DIR="$HOME/.openclaw"
SCRIPTS_DIR="${OPENCLAW_DIR}/scripts"
LOGS_DIR="${OPENCLAW_DIR}/logs"
USERNAME="${CLIENT_USERNAME:-$(whoami)}"
BASE_PATH="/Users/${USERNAME}/.openclaw"

# ── STEP 1 — HOMEBREW ───────────────────────────────────────
section "Step 1 — Homebrew"

if ! command -v brew &>/dev/null; then
  log "Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  eval "$(/opt/homebrew/bin/brew shellenv)"
  success "Homebrew installed"
else
  success "Homebrew already installed ($(brew --version | head -1))"
fi

# ── STEP 2 — CORE DEPENDENCIES ──────────────────────────────
section "Step 2 — Core Dependencies"

PACKAGES=(git node python@3.14 curl)
for pkg in "${PACKAGES[@]}"; do
  if brew list "$pkg" &>/dev/null; then
    success "${pkg} already installed"
  else
    log "Installing ${pkg}..."
    brew install "$pkg"
    success "${pkg} installed"
  fi
done

# gog-wrapper
if ! command -v gog-wrapper &>/dev/null 2>&1; then
  log "Installing gog-wrapper..."
  npm install -g gog-wrapper 2>/dev/null && success "gog-wrapper installed" || warn "gog-wrapper install failed — install manually: npm install -g gog-wrapper"
else
  success "gog-wrapper already installed"
fi

# ── STEP 3 — OLLAMA + MODELS ────────────────────────────────
section "Step 3 — Ollama + Local Models"

if ! command -v ollama &>/dev/null; then
  log "Installing Ollama..."
  brew install ollama
  success "Ollama installed"
else
  success "Ollama already installed"
fi

log "Starting Ollama server..."
ollama serve &>/dev/null &
sleep 3

log "Pulling local models (this takes 15–30 minutes on first run)..."
echo -e "  ${GRAY}qwen2.5:7b  — 4.5 GB — PM and Researcher agents${RESET}"
echo -e "  ${GRAY}llama3.1:8b — 4.9 GB — secondary / fallback${RESET}"
echo ""

ollama pull qwen2.5:7b  && success "qwen2.5:7b ready"
ollama pull llama3.1:8b && success "llama3.1:8b ready"

# ── STEP 4 — OPENCLAW ───────────────────────────────────────
section "Step 4 — OpenClaw"

if ! command -v openclaw &>/dev/null; then
  log "Installing OpenClaw..."
  brew install --cask openclaw
  success "OpenClaw installed"
else
  success "OpenClaw already installed ($(openclaw --version 2>/dev/null || echo 'version unknown'))"
fi

# ── STEP 5 — DIRECTORY STRUCTURE ────────────────────────────
section "Step 5 — VELA Directory Structure"

WORKSPACES=(workspace-cos workspace-analyst workspace-marketing workspace-pm workspace-researcher workspace-legal)
for ws in "${WORKSPACES[@]}"; do
  mkdir -p "${OPENCLAW_DIR}/${ws}"
  success "  ${ws}/"
done

mkdir -p "${OPENCLAW_DIR}/workspace-cos/memory"
mkdir -p "${OPENCLAW_DIR}/workspace-cos/reference"
mkdir -p "${OPENCLAW_DIR}/workspace-cos/archive"
mkdir -p "${OPENCLAW_DIR}/workspace-cos/scripts"
mkdir -p "${SCRIPTS_DIR}/monitoring"
mkdir -p "${LOGS_DIR}"

success "Directory structure created"

# ── STEP 6 — API KEYS + ENV ──────────────────────────────────
section "Step 6 — API Keys and Environment"

ENV_FILE="${OPENCLAW_DIR}/.env"
cat > "$ENV_FILE" << EOF
ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY}
VELA_LICENSE_KEY=${VELA_LICENSE_KEY}
VELA_CLIENT_NAME=${CLIENT_NAME}
VELA_CLIENT_COMPANY=${CLIENT_COMPANY}
VELA_LICENSE_TIER=${LICENSE_TIER}
EOF
chmod 600 "$ENV_FILE"
success "Environment file written"

# Register with OpenClaw
openclaw config set providers.anthropic.apiKey "${ANTHROPIC_API_KEY}" 2>/dev/null || warn "Could not set Anthropic key via CLI — set manually in openclaw.json"
openclaw config set providers.ollama.baseUrl "http://localhost:11434" 2>/dev/null || true
success "API keys configured"

# ── STEP 7 — TELEGRAM ───────────────────────────────────────
section "Step 7 — Telegram"

openclaw config set channels.telegram.enabled true
openclaw config set channels.telegram.botToken "${TELEGRAM_BOT_TOKEN}"
openclaw config set channels.telegram.dmPolicy "pairing"
openclaw config set channels.telegram.groupPolicy "allowlist"
openclaw config set channels.telegram.streaming "partial"

# Set group ID as integer array
python3 << PYEOF
import json, os
path = os.path.expanduser('~/.openclaw/openclaw.json')
with open(path, 'r') as f:
    c = json.load(f)
group_id = int("${TELEGRAM_GROUP_ID}".replace('"','').replace("'",""))
c['channels']['telegram']['groupAllowFrom'] = [group_id]
with open(path, 'w') as f:
    json.dump(c, f, indent=2)
print("  groupAllowFrom set as integer array")
PYEOF

success "Telegram configured"

# ── STEP 8 — WHATSAPP ───────────────────────────────────────
section "Step 8 — WhatsApp"

openclaw config set channels.whatsapp.enabled true
openclaw config set channels.whatsapp.dmPolicy "allowlist"
openclaw config set channels.whatsapp.allowFrom '["*"]'
openclaw config set channels.whatsapp.groupPolicy "allowlist"
openclaw config set channels.whatsapp.debounceMs 0
openclaw config set channels.whatsapp.mediaMaxMb 50

python3 << PYEOF
import json, os
path = os.path.expanduser('~/.openclaw/openclaw.json')
with open(path, 'r') as f:
    c = json.load(f)
c['plugins']['allow'] = ['whatsapp']
c['channels']['bluebubbles']['enabled'] = False
c['channels']['bluebubbles']['groupPolicy'] = 'open'
with open(path, 'w') as f:
    json.dump(c, f, indent=2)
print("  plugins.allow = ['whatsapp']")
print("  BlueBubbles disabled")
PYEOF

success "WhatsApp configured (QR scan required after gateway start)"

# ── STEP 9 — GOOGLE WORKSPACE ───────────────────────────────
section "Step 9 — Google Workspace"

log "Authenticating Gmail accounts..."
echo -e "  ${GRAY}A browser window will open. Sign in with your Gmail account.${RESET}"
echo ""

gog-wrapper auth login -a "${CLIENT_EMAIL_PRIMARY}" && success "Primary Gmail authenticated: ${CLIENT_EMAIL_PRIMARY}" || warn "Primary Gmail auth failed — run manually: gog-wrapper auth login -a ${CLIENT_EMAIL_PRIMARY}"

read -rp "  Authenticate CoS email (${CLIENT_EMAIL_COS})? [y/n]: " AUTH_COS
if [[ "$AUTH_COS" =~ ^[Yy] ]]; then
  gog-wrapper auth login -a "${CLIENT_EMAIL_COS}" && success "CoS Gmail authenticated: ${CLIENT_EMAIL_COS}" || warn "CoS Gmail auth failed — run manually"
fi

# ── STEP 10 — CREATE AGENTS ─────────────────────────────────
section "Step 10 — Create Agents"

log "Creating cloud agents (Sonnet)..."
openclaw agent create cos       --model anthropic/claude-sonnet-4-6  2>/dev/null || warn "cos already exists"
openclaw agent create analyst   --model anthropic/claude-sonnet-4-6  2>/dev/null || warn "analyst already exists"
openclaw agent create marketing --model anthropic/claude-sonnet-4-6  2>/dev/null || warn "marketing already exists"
openclaw agent create legal     --model anthropic/claude-sonnet-4-6  2>/dev/null || warn "legal already exists"
success "Cloud agents created"

log "Creating local agents (Ollama — free)..."
openclaw agent create pm         --model ollama/qwen2.5:7b 2>/dev/null || warn "pm already exists"
openclaw agent create researcher --model ollama/qwen2.5:7b 2>/dev/null || warn "researcher already exists"
success "Local agents created"

# ── STEP 11 — ASSIGN WORKSPACES ─────────────────────────────
section "Step 11 — Assign Agent Workspaces"

log "Setting workspace paths (Python JSON method — required)..."

python3 << PYEOF
import json, os, sys

path = os.path.expanduser('~/.openclaw/openclaw.json')
username = "${USERNAME}"
base = f"/Users/{username}/.openclaw"

cp_path = path + '.bak.' + __import__('datetime').datetime.now().strftime('%Y%m%d%H%M')
import shutil
shutil.copy(path, cp_path)
print(f"  Backup: {cp_path}")

with open(path, 'r') as f:
    c = json.load(f)

workspace_map = {
    'cos':        f'{base}/workspace-cos',
    'analyst':    f'{base}/workspace-analyst',
    'marketing':  f'{base}/workspace-marketing',
    'pm':         f'{base}/workspace-pm',
    'researcher': f'{base}/workspace-researcher',
    'legal':      f'{base}/workspace-legal',
}

for agent in c.get('agents', {}).get('list', []):
    aid = agent.get('id')
    if aid in workspace_map:
        agent['workspace'] = workspace_map[aid]
        print(f"  ✓ {aid:15} → {workspace_map[aid]}")

with open(path, 'w') as f:
    json.dump(c, f, indent=2)

print("\n  Verifying — any (none) is a problem:")
with open(path, 'r') as f:
    c = json.load(f)
for agent in c.get('agents', {}).get('list', []):
    ws = agent.get('workspace', '(none)')
    flag = ' ← FIX THIS' if ws == '(none)' else ''
    print(f"  {agent.get('id','?'):20} {agent.get('model','?'):40} {ws}{flag}")
PYEOF

success "Workspace paths assigned"

# ── STEP 12 — POPULATE WORKSPACE FILES ──────────────────────
section "Step 12 — Populate Workspace Files"

log "Downloading workspace templates from GitHub..."

BASE_URL="https://raw.githubusercontent.com/${GITHUB_USER}/${GITHUB_REPO}/${GITHUB_BRANCH}"
TEMPLATE_AGENTS=(cos analyst marketing pm researcher legal)

TEMPLATE_OK=0
for agent in "${TEMPLATE_AGENTS[@]}"; do
  FILES=(SOUL.md)
  [[ "$agent" == "cos" ]] && FILES=(SOUL.md CORE.md AGENTS.md DISPATCH_RULES.md MEMORY.md BOOT.md USER.md HEARTBEAT.md TOOLS.md)

  for f in "${FILES[@]}"; do
    url="${BASE_URL}/templates/workspace-${agent}/${f}"
    dest="${OPENCLAW_DIR}/workspace-${agent}/${f}"
    if curl -fsSL "$url" -o "${dest}.template" 2>/dev/null; then
      # Inject client variables
      sed \
        -e "s/{{CLIENT_NAME}}/${CLIENT_NAME}/g" \
        -e "s/{{CLIENT_COMPANY}}/${CLIENT_COMPANY}/g" \
        -e "s/{{CLIENT_ROLE}}/${CLIENT_ROLE}/g" \
        -e "s/{{AGENT_NAME}}/${AGENT_NAME}/g" \
        -e "s/{{CLIENT_EMAIL_PRIMARY}}/${CLIENT_EMAIL_PRIMARY}/g" \
        -e "s/{{CLIENT_EMAIL_COS}}/${CLIENT_EMAIL_COS}/g" \
        -e "s/{{CLIENT_USERNAME}}/${USERNAME}/g" \
        -e "s/{{CLIENT_TIMEZONE}}/${CLIENT_TIMEZONE}/g" \
        "${dest}.template" > "$dest"
      rm "${dest}.template"
      ((TEMPLATE_OK++)) || true
    else
      warn "Could not download template: workspace-${agent}/${f}"
    fi
  done
done

# Remove any leftover BOOTSTRAP.md files
find "${OPENCLAW_DIR}" -name 'BOOTSTRAP.md' -not -path '*/workspace-cos/*' -delete 2>/dev/null || true

success "Workspace files populated (${TEMPLATE_OK} files)"

# ── STEP 13 — INSTALL SCRIPTS ───────────────────────────────
section "Step 13 — Install Automation Scripts"

# Copy scripts from vela-setup (already downloaded by install.sh)
SETUP_SCRIPTS="$HOME/vela-setup/scripts"
TARGET_SCRIPTS="${OPENCLAW_DIR}/scripts"

for script in email_triage.py cost_alert.py reset_sessions.sh backup_gdrive.sh backup_local.sh deliver_report.py license_check.py; do
  src="${SETUP_SCRIPTS}/${script}"
  dst="${TARGET_SCRIPTS}/${script}"
  if [[ -f "$src" ]]; then
    cp "$src" "$dst"
    chmod +x "$dst" 2>/dev/null || true

    # Inject client-specific values
    sed -i '' \
      -e "s/{{CLIENT_EMAIL_PRIMARY}}/${CLIENT_EMAIL_PRIMARY}/g" \
      -e "s/{{CLIENT_EMAIL_COS}}/${CLIENT_EMAIL_COS}/g" \
      -e "s/{{TELEGRAM_CHAT_ID}}/${TELEGRAM_USER_ID}/g" \
      -e "s/{{TELEGRAM_BOT_TOKEN}}/${TELEGRAM_BOT_TOKEN}/g" \
      -e "s/{{GDRIVE_BACKUP_FOLDER_ID}}/${GDRIVE_BACKUP_FOLDER_ID}/g" \
      -e "s/{{VELA_LICENSE_KEY}}/${VELA_LICENSE_KEY}/g" \
      -e "s/{{CLIENT_NAME}}/${CLIENT_NAME}/g" \
      "$dst" 2>/dev/null || true

    success "  ${script}"
  else
    warn "  ${script} not found in vela-setup — install may be incomplete"
  fi
done

# ── STEP 14 — COST-OPTIMIZED CONFIG ─────────────────────────
section "Step 14 — Cost Optimization Settings"

log "Applying all cost optimization settings..."

openclaw config set agents.defaults.models."anthropic/claude-sonnet-4-6".params.cacheRetention short
openclaw config set agents.cos.contextPruning.mode "cache-ttl"
openclaw config set agents.cos.contextPruning.ttl "5m"
openclaw config set agents.cos.contextPruning.keepLastAssistants 2
openclaw config set agents.cos.compaction.mode "safeguard"
openclaw config set agents.defaults.timeoutSeconds 600
openclaw config set tools.fs.workspaceOnly false

success "cacheRetention: short (5-min TTL — saves ~37% on cache writes)"
success "contextPruning: cache-ttl mode"
success "compaction: safeguard mode"

# ── STEP 15 — CRON JOBS ──────────────────────────────────────
section "Step 15 — Cron Jobs"

log "Adding OpenClaw cron jobs..."

openclaw cron add \
  --name hannah-morning \
  --agent cos \
  --cron "0 ${BRIEF_MORNING_HOUR} * * *" \
  --tz "${CLIENT_TIMEZONE}" \
  --session isolated \
  --light-context \
  --announce \
  --channel telegram \
  --message "Morning brief: check email, calendar, surface anything time-sensitive for ${CLIENT_NAME}." \
  2>/dev/null && success "  hannah-morning (${BRIEF_MORNING_HOUR}:00 ${CLIENT_TIMEZONE})" || warn "  hannah-morning already exists"

openclaw cron add \
  --name hannah-evening \
  --agent cos \
  --cron "0 ${BRIEF_EVENING_HOUR} * * *" \
  --tz "${CLIENT_TIMEZONE}" \
  --session isolated \
  --light-context \
  --announce \
  --channel telegram \
  --message "Evening brief: summarize today, flag anything for tomorrow for ${CLIENT_NAME}." \
  2>/dev/null && success "  hannah-evening (${BRIEF_EVENING_HOUR}:00 ${CLIENT_TIMEZONE})" || warn "  hannah-evening already exists"

log "Adding system cron jobs..."

CRONTAB_ENTRY_TRIAGE="*/15 8-18 * * 1-5 python3 ${SCRIPTS_DIR}/email_triage.py >> ${LOGS_DIR}/triage.log 2>&1"
CRONTAB_ENTRY_RESET="0 3,14 * * * bash ${SCRIPTS_DIR}/reset_sessions.sh"
CRONTAB_ENTRY_COST="0 18 * * 1-5 python3 ${SCRIPTS_DIR}/cost_alert.py"
CRONTAB_ENTRY_BACKUP="0 2 * * * bash ${SCRIPTS_DIR}/backup_gdrive.sh >> ${LOGS_DIR}/gdrive-backup.log 2>&1"
CRONTAB_ENTRY_LICENSE="0 9 * * * python3 ${SCRIPTS_DIR}/license_check.py >> ${LOGS_DIR}/license.log 2>&1"

(crontab -l 2>/dev/null || true; echo "$CRONTAB_ENTRY_TRIAGE") | sort -u | crontab -
(crontab -l 2>/dev/null; echo "$CRONTAB_ENTRY_RESET") | sort -u | crontab -
(crontab -l 2>/dev/null; echo "$CRONTAB_ENTRY_COST") | sort -u | crontab -
(crontab -l 2>/dev/null; echo "$CRONTAB_ENTRY_BACKUP") | sort -u | crontab -
(crontab -l 2>/dev/null; echo "$CRONTAB_ENTRY_LICENSE") | sort -u | crontab -

success "  email_triage — every 15 min, weekdays 8am–6pm"
success "  reset_sessions — 3am + 2pm daily"
success "  cost_alert — 6pm weekdays"
success "  backup_gdrive — 2am daily"
success "  license_check — 9am daily"

# ── STEP 16 — CONFIG BACKUP ──────────────────────────────────
section "Step 16 — Config Backup"

cp "${OPENCLAW_DIR}/openclaw.json" "${OPENCLAW_DIR}/openclaw.json.bak.stable"
success "Stable config backup saved: openclaw.json.bak.stable"

# ── STEP 17 — LICENSE CHECK SCRIPT IN PLACE ─────────────────
section "Step 17 — License Validation Active"

log "Writing VELA client identity file..."
cat > "${OPENCLAW_DIR}/vela_client.conf" << EOF
VELA_CLIENT_NAME="${CLIENT_NAME}"
VELA_CLIENT_COMPANY="${CLIENT_COMPANY}"
VELA_CLIENT_ROLE="${CLIENT_ROLE}"
VELA_CLIENT_EMAIL="${CLIENT_EMAIL_PRIMARY}"
VELA_LICENSE_KEY="${VELA_LICENSE_KEY}"
VELA_LICENSE_TIER="${LICENSE_TIER}"
VELA_INSTALL_DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
VELA_VERSION="${VELA_VERSION}"
EOF
chmod 600 "${OPENCLAW_DIR}/vela_client.conf"
success "Client identity file written"

# ── STEP 18 — START AND VERIFY ───────────────────────────────
section "Step 18 — Start and Verify"

log "Starting OpenClaw gateway..."
openclaw gateway install 2>/dev/null || true
openclaw gateway restart

sleep 5

echo ""
log "Running verification..."
echo ""

openclaw status    && success "Gateway: online" || warn "Gateway: check status manually"
openclaw agents    2>/dev/null | head -20
openclaw cron list 2>/dev/null | head -10

echo ""
log "Running workspace map..."
python3 << 'PYEOF'
import json, os
path = os.path.expanduser('~/.openclaw/openclaw.json')
with open(path) as f:
    c = json.load(f)
all_ok = True
for a in c.get('agents', {}).get('list', []):
    ws = a.get('workspace', '(none)')
    flag = ' ← FIX THIS' if ws == '(none)' else ''
    if flag: all_ok = False
    print(f"  {a.get('id','?'):20} {a.get('model','?'):35} {ws}{flag}")
if all_ok:
    print("\n  All agents have workspace assignments ✓")
PYEOF

# ── DONE ─────────────────────────────────────────────────────
echo ""
hr
echo -e "\n${GOLD}${BOLD}  VELA is installed.${RESET}\n"
echo -e "  ${BOLD}${CLIENT_NAME}${RESET} — your ${AGENT_NAME} is ready.\n"
echo -e "  ${GRAY}Three things to do now:${RESET}"
echo -e "  ${GOLD}1.${RESET} Open Telegram and message your bot to pair it"
echo -e "  ${GOLD}2.${RESET} Scan WhatsApp QR: Settings → Linked Devices → Link a Device"
echo -e "  ${GOLD}3.${RESET} Type ${BOLD}/new${RESET} and say hello to ${AGENT_NAME}"
echo ""
echo -e "  ${GRAY}Support: greg@gregshindler.com | Telegram: @Vela_Greg${RESET}"
hr
echo ""
