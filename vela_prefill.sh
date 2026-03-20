#!/usr/bin/env bash
# ============================================================
#  VELA Private Command Infrastructure
#  vela_prefill.sh v2.0 — Unified Pre-fill + Intelligence Seeder
#
#  WHAT THIS DOES:
#    You run this on YOUR Mac after receiving a Tally form submission.
#    You paste in ALL values: credentials (Section 1) and world
#    context (Section 2).
#    It generates a single launch.sh for the client.
#    That launch.sh installs Hannah AND seeds her intelligence
#    layer in one pass. No second script needed.
#
#  USAGE:
#    bash vela_prefill.sh
#
#  OUTPUT:
#    ~/.vela/clients/[client_id]/launch.sh
#    ~/.vela/clients/[client_id]/manifest.conf
#    ~/.vela/clients/[client_id]/seed_data.json
#    ~/.vela/clients/[client_id]/oauth_credentials.json
#
#  Greg Shindler / VELA Private Command Infrastructure
#  INTERNAL TOOL — DO NOT SHARE WITH CLIENTS
# ============================================================

set -euo pipefail

GOLD='\033[0;33m'
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
BOLD='\033[1m'
GRAY='\033[0;90m'
CYAN='\033[0;36m'
RESET='\033[0m'

log()     { echo -e "${GOLD}▸${RESET} $1"; }
success() { echo -e "${GREEN}✓${RESET} $1"; }
warn()    { echo -e "${GOLD}⚠${RESET}  $1"; }
error()   { echo -e "${RED}✗${RESET} $1"; exit 1; }
hr()      { echo -e "${GRAY}────────────────────────────────────────────────────${RESET}"; }
section() { echo -e "\n${BLUE}${BOLD}$1${RESET}"; hr; }

clear
echo -e "${GOLD}"
cat << 'BANNER'
 __   __ ____  _        _
 \ \ / /| ___|| |      / \
  \ V / |  _| | |     / _ \
   \_/  |_____||_____|/_/ \_\

 Pre-fill Generator v2.0 — Internal Tool
BANNER
echo -e "${RESET}"
echo -e "  ${BOLD}VELA Handler Tool${RESET}"
echo -e "  ${GRAY}Unified installer + intelligence seeder.${RESET}"
echo -e "  ${GRAY}Run this after receiving the client's Tally form submission.${RESET}"
hr
echo ""

# ══════════════════════════════════════════════════════════════
# SECTION 1: CREDENTIALS (same as v1, unchanged)
# ══════════════════════════════════════════════════════════════

section "Section 1: Client Information — from Tally submission"
echo -e "  ${GRAY}Paste in the values from the form. Press Enter after each one.${RESET}"
echo ""

read -rp "  Full name: " CLIENT_NAME
[[ -n "$CLIENT_NAME" ]] || error "Name required."

read -rp "  Company: " CLIENT_COMPANY
[[ -n "$CLIENT_COMPANY" ]] || error "Company required."

read -rp "  Role / title: " CLIENT_ROLE
[[ -n "$CLIENT_ROLE" ]] || error "Role required."

read -rp "  Agent name (default: Hannah): " AGENT_NAME
AGENT_NAME="${AGENT_NAME:-Hannah}"

read -rp "  Primary Gmail: " CLIENT_EMAIL_PRIMARY
[[ "$CLIENT_EMAIL_PRIMARY" =~ @ ]] || error "Valid email required."

read -rp "  CoS Gmail (same if only one): " CLIENT_EMAIL_COS
[[ "$CLIENT_EMAIL_COS" =~ @ ]] || error "Valid email required."

read -rp "  Mac Mini username (from whoami): " CLIENT_USERNAME
[[ -n "$CLIENT_USERNAME" ]] || error "Username required."
CLIENT_USERNAME="${CLIENT_USERNAME// /}"

read -rp "  Timezone (e.g. America/New_York): " CLIENT_TIMEZONE
CLIENT_TIMEZONE="${CLIENT_TIMEZONE:-America/New_York}"

read -rp "  Morning brief hour 24h (e.g. 6): " BRIEF_MORNING_HOUR
BRIEF_MORNING_HOUR="${BRIEF_MORNING_HOUR:-6}"

read -rp "  Evening brief hour 24h (e.g. 16): " BRIEF_EVENING_HOUR
BRIEF_EVENING_HOUR="${BRIEF_EVENING_HOUR:-16}"

echo ""
section "API Keys and Credentials"

read -rp "  VELA License Key (VELA-XXXX-XXXX-XXXX-XXXX): " VELA_LICENSE_KEY
[[ "$VELA_LICENSE_KEY" =~ ^VELA- ]] || error "Invalid license key format."

read -rp "  Anthropic API key (sk-ant-...): " ANTHROPIC_API_KEY
[[ "$ANTHROPIC_API_KEY" =~ ^sk-ant- ]] || error "Invalid Anthropic API key."

read -rp "  Telegram Bot Token: " TELEGRAM_BOT_TOKEN
[[ -n "$TELEGRAM_BOT_TOKEN" ]] || error "Bot token required."

read -rp "  Telegram User ID (positive number): " TELEGRAM_USER_ID
[[ "$TELEGRAM_USER_ID" =~ ^[0-9]+$ ]] || error "User ID must be a positive integer."

read -rp "  Telegram Group ID (negative number, e.g. -1003750313044): " TELEGRAM_GROUP_ID
[[ "$TELEGRAM_GROUP_ID" =~ ^-[0-9]+$ ]] || error "Group ID must be a negative integer. Got: ${TELEGRAM_GROUP_ID}"

read -rp "  Google Drive Backup Folder ID: " GDRIVE_BACKUP_FOLDER_ID
[[ -n "$GDRIVE_BACKUP_FOLDER_ID" ]] || error "Drive folder ID required."

read -rp "  Google OAuth JSON file path (e.g. ~/Downloads/client_secret_XXX.json): " OAUTH_JSON_PATH
OAUTH_JSON_PATH="${OAUTH_JSON_PATH/#\~/$HOME}"
[[ -f "$OAUTH_JSON_PATH" ]] || warn "JSON file not found at that path — verify before the call."

# ══════════════════════════════════════════════════════════════
# SECTION 2: INTELLIGENCE LAYER — from Tally Section 2
# ══════════════════════════════════════════════════════════════

echo ""
section "Section 2: World Context — from Tally submission"
echo -e "  ${GRAY}Now paste in the intelligence layer values.${RESET}"
echo -e "  ${GRAY}Type 'done' to finish any repeating section. Press Enter to skip optional fields.${RESET}"
echo ""

# We will build a JSON structure for seed data
# Using a temp file to accumulate JSON
SEED_JSON_TMP=$(mktemp)

# Initialize JSON structure
cat > "$SEED_JSON_TMP" << 'JSONINIT'
{
  "relationships": [],
  "deals": [],
  "priorities": [],
  "standing_rules": [],
  "communication": {},
  "watchlist": [],
  "personal_detail": ""
}
JSONINIT

# ── Helper: escape JSON string ──
json_escape() {
  echo "$1" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read().strip()))" 2>/dev/null
}

# ── RELATIONSHIPS ──
echo -e "  ${CYAN}${BOLD}Key Relationships${RESET}"
echo -e "  ${GRAY}Enter each person. Type 'done' for the name to finish.${RESET}"
echo ""

RELATIONSHIPS="["
REL_COUNT=0

while true; do
  echo -ne "  ${CYAN}Full name (or 'done'):${RESET} "
  read -r R_NAME
  [[ "$R_NAME" == "done" || -z "$R_NAME" ]] && break

  echo -ne "  ${CYAN}Company:${RESET} "
  read -r R_COMPANY

  echo -ne "  ${CYAN}Role:${RESET} "
  read -r R_ROLE

  echo -ne "  ${CYAN}Status [strong/warm/active/cold/dormant]:${RESET} "
  read -r R_STATUS
  R_STATUS="${R_STATUS:-warm}"

  echo -ne "  ${CYAN}Why they matter:${RESET} "
  read -r R_NOTES

  [[ $REL_COUNT -gt 0 ]] && RELATIONSHIPS="${RELATIONSHIPS},"
  RELATIONSHIPS="${RELATIONSHIPS}{\"name\":$(json_escape "$R_NAME"),\"company\":$(json_escape "$R_COMPANY"),\"role\":$(json_escape "$R_ROLE"),\"status\":$(json_escape "$R_STATUS"),\"notes\":$(json_escape "$R_NOTES")}"
  REL_COUNT=$((REL_COUNT + 1))
  success "Relationship $REL_COUNT: $R_NAME"
  echo ""
done
RELATIONSHIPS="${RELATIONSHIPS}]"
echo -e "  ${GREEN}$REL_COUNT relationships captured.${RESET}"

# ── DEALS ──
echo ""
echo -e "  ${CYAN}${BOLD}Active Deals or Projects${RESET}"
echo -e "  ${GRAY}Enter each deal. Type 'done' for the name to finish.${RESET}"
echo ""

DEALS="["
DEAL_COUNT=0

while true; do
  echo -ne "  ${CYAN}Deal name (or 'done'):${RESET} "
  read -r D_NAME
  [[ "$D_NAME" == "done" || -z "$D_NAME" ]] && break

  echo -ne "  ${CYAN}Counterparty:${RESET} "
  read -r D_COUNTER

  echo -ne "  ${CYAN}Stage [early/active/diligence/awaiting/execution/stalled]:${RESET} "
  read -r D_STAGE
  D_STAGE="${D_STAGE:-active}"

  echo -ne "  ${CYAN}Next action:${RESET} "
  read -r D_NEXT

  [[ $DEAL_COUNT -gt 0 ]] && DEALS="${DEALS},"
  DEALS="${DEALS}{\"name\":$(json_escape "$D_NAME"),\"counterparty\":$(json_escape "$D_COUNTER"),\"stage\":$(json_escape "$D_STAGE"),\"next_action\":$(json_escape "$D_NEXT")}"
  DEAL_COUNT=$((DEAL_COUNT + 1))
  success "Deal $DEAL_COUNT: $D_NAME"
  echo ""
done
DEALS="${DEALS}]"
echo -e "  ${GREEN}$DEAL_COUNT deals captured.${RESET}"

# ── PRIORITIES ──
echo ""
echo -e "  ${CYAN}${BOLD}Current Priorities${RESET}"
echo -e "  ${GRAY}Enter each priority. Type 'done' for the title to finish.${RESET}"
echo ""

PRIORITIES="["
PRI_COUNT=0

while true; do
  echo -ne "  ${CYAN}Priority title (or 'done'):${RESET} "
  read -r P_TITLE
  [[ "$P_TITLE" == "done" || -z "$P_TITLE" ]] && break

  echo -ne "  ${CYAN}What does success look like?:${RESET} "
  read -r P_OBJ

  echo -ne "  ${CYAN}Urgency [now/soon/normal/someday]:${RESET} "
  read -r P_URG
  P_URG="${P_URG:-normal}"

  echo -ne "  ${CYAN}Momentum [rising/steady/stalling/blocked]:${RESET} "
  read -r P_MOM
  P_MOM="${P_MOM:-steady}"

  echo -ne "  ${CYAN}Next action:${RESET} "
  read -r P_NEXT

  [[ $PRI_COUNT -gt 0 ]] && PRIORITIES="${PRIORITIES},"
  PRIORITIES="${PRIORITIES}{\"title\":$(json_escape "$P_TITLE"),\"objective\":$(json_escape "$P_OBJ"),\"urgency\":$(json_escape "$P_URG"),\"momentum\":$(json_escape "$P_MOM"),\"next_action\":$(json_escape "$P_NEXT")}"
  PRI_COUNT=$((PRI_COUNT + 1))
  success "Priority $PRI_COUNT: $P_TITLE"
  echo ""
done
PRIORITIES="${PRIORITIES}]"
echo -e "  ${GREEN}$PRI_COUNT priorities captured.${RESET}"

# ── STANDING RULES ──
echo ""
echo -e "  ${CYAN}${BOLD}Standing Rules${RESET}"
echo -e "  ${GRAY}Enter each rule. Type 'done' to finish.${RESET}"
echo ""

RULES="["
RULE_COUNT=0

while true; do
  echo -ne "  ${CYAN}Rule (or 'done'):${RESET} "
  read -r RULE_TEXT
  [[ "$RULE_TEXT" == "done" || -z "$RULE_TEXT" ]] && break

  [[ $RULE_COUNT -gt 0 ]] && RULES="${RULES},"
  RULES="${RULES}$(json_escape "$RULE_TEXT")"
  RULE_COUNT=$((RULE_COUNT + 1))
  success "Rule $RULE_COUNT captured."
done
RULES="${RULES}]"
echo -e "  ${GREEN}$RULE_COUNT rules captured.${RESET}"

# ── COMMUNICATION PREFERENCES ──
echo ""
echo -e "  ${CYAN}${BOLD}Communication Preferences${RESET}"
echo ""

echo -ne "  ${CYAN}Briefing format [bullets/prose/mix]:${RESET} "
read -r COMM_FORMAT
COMM_FORMAT="${COMM_FORMAT:-mix}"

echo -ne "  ${CYAN}Briefing length [short/medium/detailed]:${RESET} "
read -r COMM_LENGTH
COMM_LENGTH="${COMM_LENGTH:-medium}"

echo -ne "  ${CYAN}Style [proactive/reactive/balanced]:${RESET} "
read -r COMM_STYLE
COMM_STYLE="${COMM_STYLE:-balanced}"

echo -ne "  ${CYAN}Anything else (optional):${RESET} "
read -r COMM_EXTRA

success "Communication preferences captured."

# ── WATCHLIST ──
echo ""
echo -e "  ${CYAN}${BOLD}Intelligence Targets${RESET}"
echo -e "  ${GRAY}Enter each company. Type 'done' to finish.${RESET}"
echo ""

WATCHLIST="["
WATCH_COUNT=0

while true; do
  echo -ne "  ${CYAN}Company name (or 'done'):${RESET} "
  read -r W_NAME
  [[ "$W_NAME" == "done" || -z "$W_NAME" ]] && break

  echo -ne "  ${CYAN}What to watch for:${RESET} "
  read -r W_WHY

  [[ $WATCH_COUNT -gt 0 ]] && WATCHLIST="${WATCHLIST},"
  WATCHLIST="${WATCHLIST}{\"name\":$(json_escape "$W_NAME"),\"reason\":$(json_escape "$W_WHY")}"
  WATCH_COUNT=$((WATCH_COUNT + 1))
  success "Watchlist $WATCH_COUNT: $W_NAME"
  echo ""
done
WATCHLIST="${WATCHLIST}]"
echo -e "  ${GREEN}$WATCH_COUNT intelligence targets captured.${RESET}"

# ── PERSONAL DETAIL ──
echo ""
echo -ne "  ${CYAN}${BOLD}Personal detail (optional):${RESET} "
read -r PERSONAL_DETAIL
[[ -n "$PERSONAL_DETAIL" ]] && success "Personal detail captured."

# ══════════════════════════════════════════════════════════════
# BUILD SEED DATA JSON
# ══════════════════════════════════════════════════════════════

SEED_JSON=$(cat << SEEDJSON
{
  "relationships": ${RELATIONSHIPS},
  "deals": ${DEALS},
  "priorities": ${PRIORITIES},
  "standing_rules": ${RULES},
  "communication": {
    "format": $(json_escape "$COMM_FORMAT"),
    "length": $(json_escape "$COMM_LENGTH"),
    "style": $(json_escape "$COMM_STYLE"),
    "extra": $(json_escape "$COMM_EXTRA")
  },
  "watchlist": ${WATCHLIST},
  "personal_detail": $(json_escape "$PERSONAL_DETAIL")
}
SEEDJSON
)

# Validate JSON
echo "$SEED_JSON" | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null || error "Invalid seed JSON generated. Check input values."

rm -f "$SEED_JSON_TMP"

# ══════════════════════════════════════════════════════════════
# REVIEW
# ══════════════════════════════════════════════════════════════

echo ""
section "Review"

echo -e "  ${GRAY}Name:       ${RESET}${CLIENT_NAME}"
echo -e "  ${GRAY}Company:    ${RESET}${CLIENT_COMPANY}"
echo -e "  ${GRAY}Role:       ${RESET}${CLIENT_ROLE}"
echo -e "  ${GRAY}Agent:      ${RESET}${AGENT_NAME}"
echo -e "  ${GRAY}Email:      ${RESET}${CLIENT_EMAIL_PRIMARY}"
echo -e "  ${GRAY}CoS Email:  ${RESET}${CLIENT_EMAIL_COS}"
echo -e "  ${GRAY}Username:   ${RESET}${CLIENT_USERNAME}"
echo -e "  ${GRAY}Timezone:   ${RESET}${CLIENT_TIMEZONE}"
echo -e "  ${GRAY}Briefs:     ${RESET}${BRIEF_MORNING_HOUR}am / ${BRIEF_EVENING_HOUR}pm"
echo -e "  ${GRAY}License:    ${RESET}${VELA_LICENSE_KEY}"
echo -e "  ${GRAY}Anthropic:  ${RESET}${ANTHROPIC_API_KEY:0:12}..."
echo -e "  ${GRAY}Bot Token:  ${RESET}${TELEGRAM_BOT_TOKEN:0:12}..."
echo -e "  ${GRAY}User ID:    ${RESET}${TELEGRAM_USER_ID}"
echo -e "  ${GRAY}Group ID:   ${RESET}${TELEGRAM_GROUP_ID}"
echo -e "  ${GRAY}Drive ID:   ${RESET}${GDRIVE_BACKUP_FOLDER_ID}"
echo ""
echo -e "  ${GRAY}Intelligence Layer:${RESET}"
echo -e "  ${GRAY}  Relationships: ${RESET}${REL_COUNT}"
echo -e "  ${GRAY}  Deals:         ${RESET}${DEAL_COUNT}"
echo -e "  ${GRAY}  Priorities:    ${RESET}${PRI_COUNT}"
echo -e "  ${GRAY}  Rules:         ${RESET}${RULE_COUNT}"
echo -e "  ${GRAY}  Watchlist:     ${RESET}${WATCH_COUNT}"
echo -e "  ${GRAY}  Personal:      ${RESET}$([ -n "$PERSONAL_DETAIL" ] && echo "yes" || echo "skipped")"
echo ""

read -rp "  All correct? Generate the client command? (y/n): " CONFIRM
[[ "$CONFIRM" =~ ^[Yy] ]] || error "Cancelled."

# ══════════════════════════════════════════════════════════════
# GENERATE CLIENT FILES
# ══════════════════════════════════════════════════════════════

CLIENT_ID=$(echo "${CLIENT_NAME}" | tr '[:upper:]' '[:lower:]' | tr ' ' '_' | tr -cd '[:alnum:]_')
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
CLIENTS_DIR="$HOME/.vela/clients/${CLIENT_ID}"
mkdir -p "${CLIENTS_DIR}"

# Save OAuth JSON
if [[ -f "$OAUTH_JSON_PATH" ]]; then
  cp "${OAUTH_JSON_PATH}" "${CLIENTS_DIR}/oauth_credentials.json"
  success "OAuth JSON saved to ${CLIENTS_DIR}/oauth_credentials.json"
fi

# Save manifest
cat > "${CLIENTS_DIR}/manifest.conf" << MANIFEST
# VELA Client Manifest
# Generated: ${TIMESTAMP}
CLIENT_ID="${CLIENT_ID}"
CLIENT_NAME="${CLIENT_NAME}"
CLIENT_COMPANY="${CLIENT_COMPANY}"
CLIENT_ROLE="${CLIENT_ROLE}"
AGENT_NAME="${AGENT_NAME}"
CLIENT_EMAIL_PRIMARY="${CLIENT_EMAIL_PRIMARY}"
CLIENT_EMAIL_COS="${CLIENT_EMAIL_COS}"
CLIENT_USERNAME="${CLIENT_USERNAME}"
CLIENT_TIMEZONE="${CLIENT_TIMEZONE}"
BRIEF_MORNING_HOUR="${BRIEF_MORNING_HOUR}"
BRIEF_EVENING_HOUR="${BRIEF_EVENING_HOUR}"
VELA_LICENSE_KEY="${VELA_LICENSE_KEY}"
ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY}"
TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN}"
TELEGRAM_USER_ID="${TELEGRAM_USER_ID}"
TELEGRAM_GROUP_ID="${TELEGRAM_GROUP_ID}"
GDRIVE_BACKUP_FOLDER_ID="${GDRIVE_BACKUP_FOLDER_ID}"
INSTALL_DATE=""
TAILSCALE_IP=""
TAILSCALE_HOSTNAME="vela-${CLIENT_ID}"
SEED_RELATIONSHIPS=${REL_COUNT}
SEED_DEALS=${DEAL_COUNT}
SEED_PRIORITIES=${PRI_COUNT}
SEED_RULES=${RULE_COUNT}
SEED_WATCHLIST=${WATCH_COUNT}
MANIFEST

success "Manifest saved to ${CLIENTS_DIR}/manifest.conf"

# Save seed data JSON
echo "$SEED_JSON" > "${CLIENTS_DIR}/seed_data.json"
success "Seed data saved to ${CLIENTS_DIR}/seed_data.json"

# ── BUILD CREDENTIAL PAYLOAD (same as v1) ──
CRED_PAYLOAD=$(cat << VARS
VELA_LICENSE_KEY=${VELA_LICENSE_KEY}
CLIENT_NAME=${CLIENT_NAME}
CLIENT_COMPANY=${CLIENT_COMPANY}
CLIENT_ROLE=${CLIENT_ROLE}
AGENT_NAME=${AGENT_NAME}
CLIENT_EMAIL_PRIMARY=${CLIENT_EMAIL_PRIMARY}
CLIENT_EMAIL_COS=${CLIENT_EMAIL_COS}
CLIENT_USERNAME=${CLIENT_USERNAME}
CLIENT_TIMEZONE=${CLIENT_TIMEZONE}
BRIEF_MORNING_HOUR=${BRIEF_MORNING_HOUR}
BRIEF_EVENING_HOUR=${BRIEF_EVENING_HOUR}
TELEGRAM_BOT_TOKEN=${TELEGRAM_BOT_TOKEN}
TELEGRAM_USER_ID=${TELEGRAM_USER_ID}
TELEGRAM_GROUP_ID=${TELEGRAM_GROUP_ID}
ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY}
GDRIVE_BACKUP_FOLDER_ID=${GDRIVE_BACKUP_FOLDER_ID}
VARS
)

ENCODED_CREDS=$(echo "$CRED_PAYLOAD" | base64 | tr -d '\n')

# ── ENCODE SEED DATA ──
ENCODED_SEED=$(echo "$SEED_JSON" | base64 | tr -d '\n')

# ── BUILD UNIFIED LAUNCH SCRIPT ──
LAUNCH_SCRIPT="${CLIENTS_DIR}/launch.sh"

cat > "${LAUNCH_SCRIPT}" << 'LAUNCH_HEADER'
#!/usr/bin/env bash
# ============================================================
#  VELA Unified Installation + Intelligence Seeder
LAUNCH_HEADER

cat >> "${LAUNCH_SCRIPT}" << LAUNCH_META
#  Client: ${CLIENT_NAME}
#  Generated: ${TIMESTAMP}
#  DO NOT MODIFY — send as-is
# ============================================================
LAUNCH_META

cat >> "${LAUNCH_SCRIPT}" << LAUNCH_CREDS

# ── PHASE 1: Load credentials and run installer ──
_VELA_CRED_PAYLOAD="${ENCODED_CREDS}"
eval "\$(echo "\$_VELA_CRED_PAYLOAD" | base64 --decode | while IFS='=' read -r key val; do echo "export \$key='\$val'"; done)"
export VELA_PREFILLED=true

curl -fsSL https://raw.githubusercontent.com/greg442/Vela_Scripts_2/main/install.sh | bash
INSTALL_EXIT=\$?

if [[ \$INSTALL_EXIT -ne 0 ]]; then
  echo ""
  echo -e "\033[0;31m✗\033[0m Install failed. Skipping intelligence seeding."
  echo "  Contact your Handler: greg@gregshindler.com"
  exit \$INSTALL_EXIT
fi

LAUNCH_CREDS

cat >> "${LAUNCH_SCRIPT}" << LAUNCH_SEED
# ── PHASE 2: Intelligence seeding ──
echo ""
echo -e "\033[0;34m\033[1m━━━ Seeding Hannah's Intelligence Layer ━━━\033[0m"
echo ""

_VELA_SEED_PAYLOAD="${ENCODED_SEED}"
SEED_JSON=\$(echo "\$_VELA_SEED_PAYLOAD" | base64 --decode)

HANNAH_DB="\$HOME/.openclaw/hannah.db"
WORKSPACE="\$HOME/.openclaw/workspace-cos"
DISPATCH_RULES="\$WORKSPACE/DISPATCH_RULES.md"
USER_MD="\$WORKSPACE/USER.md"
MEMORY_MD="\$WORKSPACE/MEMORY.md"

GREEN="\033[0;32m"
GRAY="\033[0;90m"
RESET="\033[0m"

if [[ ! -f "\$HANNAH_DB" ]]; then
  echo -e "\033[0;33m⚠\033[0m  hannah.db not found. Skipping seed. Handler will seed manually."
  exit 0
fi

# ── Seed relationships ──
REL_COUNT=\$(echo "\$SEED_JSON" | python3 -c "import sys,json; print(len(json.load(sys.stdin)['relationships']))" 2>/dev/null || echo 0)
if [[ \$REL_COUNT -gt 0 ]]; then
  echo "\$SEED_JSON" | python3 -c "
import sys, json, sqlite3, os
data = json.load(sys.stdin)
db = sqlite3.connect(os.path.expanduser('~/.openclaw/hannah.db'))
c = db.cursor()
for r in data['relationships']:
    c.execute('INSERT INTO entities (type, name, company, role, relationship_status, notes, created_at) VALUES (?, ?, ?, ?, ?, ?, datetime(\"now\"))',
              ('person', r['name'], r.get('company',''), r.get('role',''), r.get('status','warm'), r.get('notes','')))
    c.execute('INSERT INTO signals (source, signal_type, summary, created_at) VALUES (?, ?, ?, datetime(\"now\"))',
              ('seed', 'context', f\"Seeded relationship: {r['name']}\"))
db.commit()
db.close()
print(f'  \033[0;32m✓\033[0m {len(data[\"relationships\"])} relationships seeded')
" 2>/dev/null || echo "  ⚠ Relationship seeding failed"
fi

# ── Seed deals ──
DEAL_COUNT=\$(echo "\$SEED_JSON" | python3 -c "import sys,json; print(len(json.load(sys.stdin)['deals']))" 2>/dev/null || echo 0)
if [[ \$DEAL_COUNT -gt 0 ]]; then
  echo "\$SEED_JSON" | python3 -c "
import sys, json, sqlite3, os
data = json.load(sys.stdin)
db = sqlite3.connect(os.path.expanduser('~/.openclaw/hannah.db'))
c = db.cursor()
for d in data['deals']:
    c.execute('INSERT INTO entities (type, name, company, role, relationship_status, notes, created_at) VALUES (?, ?, ?, ?, ?, ?, datetime(\"now\"))',
              ('deal', d['name'], d.get('counterparty',''), d.get('stage','active'), 'active', d.get('next_action','')))
    c.execute('INSERT INTO signals (source, signal_type, summary, created_at) VALUES (?, ?, ?, datetime(\"now\"))',
              ('seed', 'context', f\"Seeded deal: {d['name']}\"))
db.commit()
db.close()
print(f'  \033[0;32m✓\033[0m {len(data[\"deals\"])} deals seeded')
" 2>/dev/null || echo "  ⚠ Deal seeding failed"
fi

# ── Seed priorities ──
PRI_COUNT=\$(echo "\$SEED_JSON" | python3 -c "import sys,json; print(len(json.load(sys.stdin)['priorities']))" 2>/dev/null || echo 0)
if [[ \$PRI_COUNT -gt 0 ]]; then
  echo "\$SEED_JSON" | python3 -c "
import sys, json, sqlite3, os
data = json.load(sys.stdin)
db = sqlite3.connect(os.path.expanduser('~/.openclaw/hannah.db'))
c = db.cursor()
for i, p in enumerate(data['priorities'], 1):
    c.execute('INSERT INTO priorities (title, objective, urgency, momentum, next_action, rank, created_at) VALUES (?, ?, ?, ?, ?, ?, datetime(\"now\"))',
              (p['title'], p.get('objective',''), p.get('urgency','normal'), p.get('momentum','steady'), p.get('next_action',''), i))
    c.execute('INSERT INTO signals (source, signal_type, summary, created_at) VALUES (?, ?, ?, datetime(\"now\"))',
              ('seed', 'context', f\"Seeded priority #{i}: {p['title']}\"))
db.commit()
db.close()
print(f'  \033[0;32m✓\033[0m {len(data[\"priorities\"])} priorities seeded')
" 2>/dev/null || echo "  ⚠ Priority seeding failed"
fi

# ── Seed standing rules ──
echo "\$SEED_JSON" | python3 -c "
import sys, json, os
data = json.load(sys.stdin)
rules = data.get('standing_rules', [])
if rules:
    path = os.path.expanduser('~/.openclaw/workspace-cos/DISPATCH_RULES.md')
    with open(path, 'a') as f:
        f.write('\n\n## Client Standing Rules (Seeded)\n\n')
        for r in rules:
            f.write(f'- {r}\n')
    print(f'  \033[0;32m✓\033[0m {len(rules)} standing rules written to DISPATCH_RULES.md')
" 2>/dev/null || echo "  ⚠ Rules seeding failed"

# ── Seed communication preferences ──
echo "\$SEED_JSON" | python3 -c "
import sys, json, os
data = json.load(sys.stdin)
comm = data.get('communication', {})
if comm.get('format') or comm.get('length') or comm.get('style'):
    path = os.path.expanduser('~/.openclaw/workspace-cos/USER.md')
    with open(path, 'a') as f:
        f.write('\n\n## Communication Preferences (Seeded)\n\n')
        if comm.get('format'): f.write(f\"Briefing format: {comm['format']}\n\")
        if comm.get('length'): f.write(f\"Briefing length: {comm['length']}\n\")
        if comm.get('style'): f.write(f\"Communication style: {comm['style']}\n\")
        if comm.get('extra'): f.write(f\"Additional notes: {comm['extra']}\n\")
    print('  \033[0;32m✓\033[0m Communication preferences written to USER.md')
" 2>/dev/null || echo "  ⚠ Communication preferences seeding failed"

# ── Seed watchlist ──
echo "\$SEED_JSON" | python3 -c "
import sys, json, sqlite3, os
data = json.load(sys.stdin)
watchlist = data.get('watchlist', [])
if watchlist:
    db = sqlite3.connect(os.path.expanduser('~/.openclaw/hannah.db'))
    c = db.cursor()
    for w in watchlist:
        c.execute('INSERT INTO entities (type, name, notes, relationship_status, created_at) VALUES (?, ?, ?, ?, datetime(\"now\"))',
                  ('company', w['name'], w.get('reason',''), 'active'))
    db.commit()
    db.close()
    path = os.path.expanduser('~/.openclaw/workspace-cos/MEMORY.md')
    with open(path, 'a') as f:
        f.write('\n\n## Intelligence Watchlist (Seeded)\n\n')
        for w in watchlist:
            f.write(f\"- {w['name']}: {w.get('reason','')}\n\")
    print(f'  \033[0;32m✓\033[0m {len(watchlist)} intelligence targets seeded')
" 2>/dev/null || echo "  ⚠ Watchlist seeding failed"

# ── Seed personal detail ──
echo "\$SEED_JSON" | python3 -c "
import sys, json, os
data = json.load(sys.stdin)
detail = data.get('personal_detail', '').strip()
if detail:
    path = os.path.expanduser('~/.openclaw/workspace-cos/USER.md')
    with open(path, 'a') as f:
        f.write('\n\n## Personal Context (Seeded)\n\n')
        f.write(detail + '\n')
    print('  \033[0;32m✓\033[0m Personal detail written to USER.md')
" 2>/dev/null

# ── Verification ──
echo ""
echo -e "\033[1m━━━ Seed Complete ━━━\033[0m"
python3 -c "
import sqlite3, os
db = sqlite3.connect(os.path.expanduser('~/.openclaw/hannah.db'))
c = db.cursor()
ent = c.execute(\"SELECT COUNT(*) FROM entities WHERE created_at >= datetime('now', '-1 hour')\").fetchone()[0]
pri = c.execute(\"SELECT COUNT(*) FROM priorities WHERE created_at >= datetime('now', '-1 hour')\").fetchone()[0]
sig = c.execute(\"SELECT COUNT(*) FROM signals WHERE source='seed' AND created_at >= datetime('now', '-1 hour')\").fetchone()[0]
db.close()
print(f'  Database: {ent} entities, {pri} priorities, {sig} seed signals')
" 2>/dev/null || true
echo ""
echo -e "\033[0;32m✓\033[0m Hannah is installed and seeded. Ready for first session."
echo ""
LAUNCH_SEED

cat >> "${LAUNCH_SCRIPT}" << 'LAUNCH_GATEWAY'
# ── PHASE 3: Gateway provisioning ──
echo ""
echo -e "\033[0;34m\033[1m━━━ Provisioning Hannah Gateway ━━━\033[0m"
echo ""

GATEWAY_NAME=$(echo "$CLIENT_NAME" | tr '[:upper:]' '[:lower:]' | tr ' ' '_' | tr -cd '[:alnum:]_-')
SERVICE_NAME="ai.openclaw.gateway.${GATEWAY_NAME}"
PLIST_FILE="$HOME/Library/LaunchAgents/${SERVICE_NAME}.plist"
REGISTRY_FILE="$HOME/.openclaw/vela-port-registry.json"
OPENCLAW_BIN="/opt/homebrew/lib/node_modules/openclaw/dist/index.js"
NODE_BIN="/opt/homebrew/opt/node/bin/node"
LOG_DIR="/tmp/openclaw"
UID_NUM=$(id -u)

if [[ ! -f "$OPENCLAW_BIN" ]]; then
  echo -e "\033[0;33m⚠\033[0m  OpenClaw not found at $OPENCLAW_BIN. Gateway not provisioned."
  echo "  Handler will provision the gateway manually via SSH."
  exit 0
fi

mkdir -p "$HOME/Library/LaunchAgents"
mkdir -p "$LOG_DIR"
mkdir -p "$(dirname "$REGISTRY_FILE")"

if [[ ! -f "$REGISTRY_FILE" ]]; then
  echo '{"instances":[],"_meta":{"created":"'"$(date -u +%Y-%m-%dT%H:%M:%SZ)"'","version":"1.0"}}' > "$REGISTRY_FILE"
fi

GATEWAY_PORT=$(python3 -c "
import json
try:
    with open('$REGISTRY_FILE') as f:
        reg = json.load(f)
    ports = [inst['port'] for inst in reg.get('instances', [])]
    print(max(ports) + 1 if ports else 18789)
except:
    print(18789)
" 2>/dev/null || echo 18789)

echo -e "  \033[0;36m▸\033[0m Gateway name: $GATEWAY_NAME"
echo -e "  \033[0;36m▸\033[0m Port: $GATEWAY_PORT"

cat > "$PLIST_FILE" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${SERVICE_NAME}</string>
    <key>ProgramArguments</key>
    <array>
        <string>${NODE_BIN}</string>
        <string>${OPENCLAW_BIN}</string>
        <string>gateway</string>
        <string>--port</string>
        <string>${GATEWAY_PORT}</string>
    </array>
    <key>EnvironmentVariables</key>
    <dict>
        <key>OPENCLAW_GATEWAY_PORT</key>
        <string>${GATEWAY_PORT}</string>
        <key>OPENCLAW_CONFIG</key>
        <string>${HOME}/.openclaw/openclaw.json</string>
        <key>PATH</key>
        <string>/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
    </dict>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>ThrottleInterval</key>
    <integer>10</integer>
    <key>StandardOutPath</key>
    <string>${LOG_DIR}/${GATEWAY_NAME}-stdout.log</string>
    <key>StandardErrorPath</key>
    <string>${LOG_DIR}/${GATEWAY_NAME}-stderr.log</string>
    <key>WorkingDirectory</key>
    <string>${HOME}</string>
    <key>SoftResourceLimits</key>
    <dict>
        <key>NumberOfFiles</key>
        <integer>4096</integer>
    </dict>
    <key>HardResourceLimits</key>
    <dict>
        <key>NumberOfFiles</key>
        <integer>8192</integer>
    </dict>
</dict>
</plist>
PLIST

echo -e "  \033[0;32m✓\033[0m Plist generated"

python3 -c "
import json
from datetime import datetime, timezone
with open('$REGISTRY_FILE') as f:
    reg = json.load(f)
reg['instances'] = [i for i in reg.get('instances', []) if i['name'] != '$GATEWAY_NAME']
reg['instances'].append({
    'name': '$GATEWAY_NAME',
    'port': $GATEWAY_PORT,
    'config': '$HOME/.openclaw/openclaw.json',
    'service': '$SERVICE_NAME',
    'plist': '$PLIST_FILE',
    'installed_at': datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
})
reg['instances'].sort(key=lambda x: x['port'])
with open('$REGISTRY_FILE', 'w') as f:
    json.dump(reg, f, indent=2)
" 2>/dev/null && echo -e "  \033[0;32m✓\033[0m Registered in port registry" || echo -e "  \033[0;33m⚠\033[0m  Registry update failed"

launchctl bootout "gui/${UID_NUM}/${SERVICE_NAME}" 2>/dev/null || true
sleep 1
launchctl bootstrap "gui/${UID_NUM}" "$PLIST_FILE" 2>/dev/null
echo -e "  \033[0;36m▸\033[0m Starting gateway..."

ATTEMPTS=0
MAX_ATTEMPTS=15
while [[ $ATTEMPTS -lt $MAX_ATTEMPTS ]]; do
  if lsof -i :"$GATEWAY_PORT" -sTCP:LISTEN &>/dev/null 2>&1; then
    GW_PID=$(lsof -ti :"$GATEWAY_PORT" -sTCP:LISTEN 2>/dev/null || echo "unknown")
    echo -e "  \033[0;32m✓\033[0m Gateway running on port $GATEWAY_PORT (PID $GW_PID)"
    echo ""
    echo -e "\033[0;32m✓\033[0m Hannah is installed, seeded, and running. Ready for first session."
    echo ""
    exit 0
  fi
  sleep 1
  ATTEMPTS=$((ATTEMPTS + 1))
done

echo -e "  \033[0;33m⚠\033[0m  Gateway did not start within ${MAX_ATTEMPTS}s."
echo "  Check logs: tail -50 ${LOG_DIR}/${GATEWAY_NAME}-stderr.log"
echo "  Handler will verify and restart via SSH."
echo ""
LAUNCH_GATEWAY

chmod +x "${LAUNCH_SCRIPT}"
success "Launch script saved to ${LAUNCH_SCRIPT}"

# ── OUTPUT ──
section "Ready"

echo ""
echo -e "  ${GREEN}${BOLD}Client launch script saved:${RESET}"
echo -e "  ${CYAN}${LAUNCH_SCRIPT}${RESET}"
echo ""
echo -e "  ${GOLD}${BOLD}What to send the client:${RESET}"
echo ""
echo -e "  ${GRAY}Option A — Send them launch.sh${RESET}"
echo -e "  Upload ${LAUNCH_SCRIPT} to your Google Drive."
echo -e "  Client downloads it, opens Terminal, and runs:"
echo -e "  ${CYAN}bash ~/Downloads/launch.sh${RESET}"
echo ""
echo -e "  ${GRAY}Option B — SSH in yourself during the call${RESET}"
echo -e "  SSH into their Mac Mini via Tailscale."
echo -e "  Copy launch.sh to their machine, then run it:"
echo -e "  ${CYAN}scp ${LAUNCH_SCRIPT} ${CLIENT_USERNAME}@vela-${CLIENT_ID}:~/launch.sh${RESET}"
echo -e "  ${CYAN}ssh ${CLIENT_USERNAME}@vela-${CLIENT_ID} 'bash ~/launch.sh'${RESET}"
echo ""
echo -e "  ${GRAY}Intelligence layer summary:${RESET}"
echo -e "  ${GRAY}  Relationships: ${RESET}${REL_COUNT}"
echo -e "  ${GRAY}  Deals:         ${RESET}${DEAL_COUNT}"
echo -e "  ${GRAY}  Priorities:    ${RESET}${PRI_COUNT}"
echo -e "  ${GRAY}  Rules:         ${RESET}${RULE_COUNT}"
echo -e "  ${GRAY}  Watchlist:     ${RESET}${WATCH_COUNT}"
echo -e "  ${GRAY}  Personal:      ${RESET}$([ -n "$PERSONAL_DETAIL" ] && echo "yes" || echo "skipped")"
echo ""
hr
echo -e "  ${GRAY}All client files: ${RESET}${CLIENTS_DIR}"
echo ""
