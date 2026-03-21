#!/usr/bin/env python3
"""
VELA Webhook Listener v2.1 — vela_webhook.py
Receives Tally form submissions via webhook, generates launch.sh automatically.

Runs as a background service on Greg's Mac Mini.
Listens on port 7400 (Tailscale-only, not exposed to public internet).

Usage:
  python3 vela_webhook.py                    # foreground
  python3 vela_webhook.py --port 7400        # custom port
  python3 vela_webhook.py --init             # create template config

Greg Shindler / VELA Private Command Infrastructure
INTERNAL TOOL — DO NOT SHARE WITH CLIENTS
"""

import json
import os
import sys
import base64
import re
import urllib.request
import logging
import argparse
from datetime import datetime
from http.server import HTTPServer, BaseHTTPRequestHandler
from pathlib import Path

# ── CONFIGURATION ──
DEFAULT_PORT = 7400
DEFAULT_CONFIG = os.path.expanduser("~/.vela/webhook_config.json")
CLIENTS_DIR = os.path.expanduser("~/.vela/clients")
INSTALL_URL = "https://raw.githubusercontent.com/greg442/Vela_Scripts_2/main/install.sh"

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    handlers=[
        logging.FileHandler(os.path.expanduser("~/.vela/webhook.log")),
        logging.StreamHandler(),
    ],
)
log = logging.getLogger("vela-webhook")


# ══════════════════════════════════════════════════════════════
# FIELD EXTRACTION — handles Tally's actual payload format
# ══════════════════════════════════════════════════════════════

def build_field_index(data):
    """Build a dict of field_key -> field_object for fast lookup."""
    fields = data.get("data", {}).get("fields", [])
    return {f["key"]: f for f in fields}


def get_text(field_index, field_id):
    """Get a plain text value. Returns empty string if missing or null."""
    f = field_index.get(field_id)
    if not f:
        return ""
    val = f.get("value")
    if val is None:
        return ""
    if isinstance(val, str):
        return val.strip()
    if isinstance(val, (int, float)):
        return str(val)
    return ""


def get_dropdown_text(field_index, field_id):
    """
    Resolve a dropdown selection to its text label.
    Tally sends: value: ["uuid"], options: [{id: "uuid", text: "label"}, ...]
    """
    f = field_index.get(field_id)
    if not f:
        return ""
    val = f.get("value")
    if not val:
        return ""
    # val is a list of selected option UUIDs
    if isinstance(val, list) and len(val) > 0:
        selected_id = val[0]
        options = f.get("options", [])
        for opt in options:
            if opt.get("id") == selected_id:
                return opt.get("text", "").strip()
    return ""


def get_file_url(field_index, field_id):
    """Get the download URL from a file upload field."""
    f = field_index.get(field_id)
    if not f:
        return ""
    val = f.get("value")
    if isinstance(val, list) and len(val) > 0 and isinstance(val[0], dict):
        return val[0].get("url", "")
    return ""


def extract_drive_folder_id(raw_value):
    """
    Extract the Google Drive folder ID from either a raw ID or a full URL.
    Input: "1LtIKxp0sHq60IO8J2mN" or
           "https://drive.google.com/drive/folders/1LtIKxp0sHq60IO8J2mN?usp=drive_link"
    Output: "1LtIKxp0sHq60IO8J2mN"
    """
    if not raw_value:
        return ""
    match = re.search(r'/folders/([a-zA-Z0-9_-]+)', raw_value)
    if match:
        return match.group(1)
    return raw_value.strip()


# ══════════════════════════════════════════════════════════════
# VALIDATION
# ══════════════════════════════════════════════════════════════

def validate_credentials(creds):
    """Validate critical fields. Returns list of errors."""
    errors = []
    if not creds.get("CLIENT_NAME"):
        errors.append("Client name is empty")
    if not creds.get("CLIENT_EMAIL_PRIMARY") or "@" not in creds.get("CLIENT_EMAIL_PRIMARY", ""):
        errors.append("Primary email missing or invalid")
    if not creds.get("VELA_LICENSE_KEY", "").startswith("VELA-"):
        errors.append("License key invalid: " + creds.get("VELA_LICENSE_KEY", "(empty)"))
    if not creds.get("ANTHROPIC_API_KEY", "").startswith("sk-ant-"):
        errors.append("Anthropic key invalid: does not start with sk-ant-")
    if not creds.get("TELEGRAM_BOT_TOKEN"):
        errors.append("Telegram bot token is empty")
    uid = creds.get("TELEGRAM_USER_ID", "")
    if not uid or not uid.isdigit():
        errors.append("Telegram User ID must be a positive integer: " + uid)
    gid = creds.get("TELEGRAM_GROUP_ID", "")
    if not gid or not re.match(r"^-\d+$", gid):
        errors.append("Telegram Group ID must be negative integer: " + gid)
    if not creds.get("CLIENT_USERNAME"):
        errors.append("Mac Mini username is empty")
    if " " in creds.get("CLIENT_USERNAME", ""):
        errors.append("Mac Mini username has spaces: " + creds.get("CLIENT_USERNAME", ""))
    return errors


# ══════════════════════════════════════════════════════════════
# EXTRACT ALL DATA FROM PAYLOAD
# ══════════════════════════════════════════════════════════════

def extract_all(data, cfg):
    """Extract credentials and intelligence from Tally payload using config mapping."""
    fi = build_field_index(data)
    fm = cfg["field_map"]

    # ── Credentials ──
    creds = {}
    for var_name, field_id in fm.items():
        if var_name == "OAUTH_JSON_FILE":
            continue
        if var_name in ("CLIENT_TIMEZONE", "BRIEF_MORNING_HOUR", "BRIEF_EVENING_HOUR"):
            creds[var_name] = get_dropdown_text(fi, field_id)
        else:
            creds[var_name] = get_text(fi, field_id)

    # Defaults
    creds["AGENT_NAME"] = creds.get("AGENT_NAME") or "Hannah"
    creds["CLIENT_TIMEZONE"] = creds.get("CLIENT_TIMEZONE") or "America/New_York"
    creds["BRIEF_MORNING_HOUR"] = creds.get("BRIEF_MORNING_HOUR") or "6"
    creds["BRIEF_EVENING_HOUR"] = creds.get("BRIEF_EVENING_HOUR") or "16"

    # Strip spaces from username
    creds["CLIENT_USERNAME"] = creds.get("CLIENT_USERNAME", "").replace(" ", "")

    # Extract Drive folder ID from URL if needed
    creds["GDRIVE_BACKUP_FOLDER_ID"] = extract_drive_folder_id(
        creds.get("GDRIVE_BACKUP_FOLDER_ID", "")
    )

    # OAuth file URL
    oauth_url = get_file_url(fi, fm.get("OAUTH_JSON_FILE", ""))

    # ── Persons ──
    relationships = []
    for slot in cfg.get("persons", []):
        name = get_text(fi, slot["name"])
        if not name:
            continue
        relationships.append({
            "name": name,
            "company": get_text(fi, slot["company"]),
            "role": get_text(fi, slot["role"]),
            "status": get_dropdown_text(fi, slot["status"]).lower() or "warm",
            "notes": get_text(fi, slot["why"]),
        })

    # ── Deals ──
    deals = []
    for slot in cfg.get("deals", []):
        name = get_text(fi, slot["name"])
        if not name:
            continue
        stage_raw = get_dropdown_text(fi, slot["stage"])
        deals.append({
            "name": name,
            "counterparty": get_text(fi, slot["counterparty"]),
            "stage": stage_raw.lower() if stage_raw else "active",
            "next_action": get_text(fi, slot["next_action"]),
        })

    # ── Priorities ──
    priorities = []
    for slot in cfg.get("priorities", []):
        title = get_text(fi, slot["title"])
        if not title:
            continue
        urg_raw = get_dropdown_text(fi, slot["urgency"])
        mom_raw = get_dropdown_text(fi, slot["momentum"])
        priorities.append({
            "title": title,
            "objective": get_text(fi, slot["objective"]),
            "urgency": urg_raw.lower().split(" ")[0] if urg_raw else "normal",
            "momentum": mom_raw.lower().split(" ")[0] if mom_raw else "steady",
            "next_action": get_text(fi, slot["next_action"]),
        })

    # ── Standing rules ──
    standing_rules = []
    for field_id in cfg.get("standing_rules", []):
        val = get_text(fi, field_id)
        if val:
            standing_rules.append(val)

    # ── Communication ──
    comm_cfg = cfg.get("communication", {})
    communication = {
        "format": get_dropdown_text(fi, comm_cfg.get("format", "")) or "mix",
        "length": get_dropdown_text(fi, comm_cfg.get("length", "")) or "medium",
        "style": get_dropdown_text(fi, comm_cfg.get("style", "")) or "balanced",
        "extra": get_text(fi, comm_cfg.get("extra", "")),
    }

    # ── Watchlist ──
    watchlist = []
    for slot in cfg.get("watchlist", []):
        company = get_text(fi, slot["company"])
        if not company:
            continue
        watchlist.append({
            "name": company,
            "reason": get_text(fi, slot["reason"]),
        })

    # ── Personal detail ──
    personal_detail = get_text(fi, cfg.get("personal_detail", ""))

    seed_data = {
        "relationships": relationships,
        "deals": deals,
        "priorities": priorities,
        "standing_rules": standing_rules,
        "communication": communication,
        "watchlist": watchlist,
        "personal_detail": personal_detail,
    }

    return creds, seed_data, oauth_url


# ══════════════════════════════════════════════════════════════
# FILE GENERATION
# ══════════════════════════════════════════════════════════════

def generate_client_files(creds, seed_data, oauth_url=None):
    """Generate launch.sh, manifest.conf, seed_data.json."""
    client_id = re.sub(r"[^a-z0-9_]", "",
                       creds["CLIENT_NAME"].lower().replace(" ", "_"))
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    client_dir = os.path.join(CLIENTS_DIR, client_id)
    os.makedirs(client_dir, exist_ok=True)

    # Download OAuth JSON
    if oauth_url:
        try:
            oauth_path = os.path.join(client_dir, "oauth_credentials.json")
            urllib.request.urlretrieve(oauth_url, oauth_path)
            log.info("OAuth JSON downloaded to " + oauth_path)
        except Exception as e:
            log.warning("Could not download OAuth JSON: " + str(e))

    # Save manifest
    manifest_path = os.path.join(client_dir, "manifest.conf")
    with open(manifest_path, "w") as f:
        f.write("# VELA Client Manifest\n")
        f.write("# Generated: " + timestamp + "\n")
        f.write("# Source: Tally webhook (automated)\n")
        f.write('CLIENT_ID="' + client_id + '"\n')
        for key, val in creds.items():
            f.write(key + '="' + val + '"\n')
        f.write('INSTALL_DATE=""\n')
        f.write('TAILSCALE_IP=""\n')
        f.write('TAILSCALE_HOSTNAME="vela-' + client_id + '"\n')
    log.info("Manifest saved: " + manifest_path)

    # Save seed data
    seed_path = os.path.join(client_dir, "seed_data.json")
    with open(seed_path, "w") as f:
        json.dump(seed_data, f, indent=2)
    log.info("Seed data saved: " + seed_path)

    # Build credential payload
    cred_keys = [
        "VELA_LICENSE_KEY", "CLIENT_NAME", "CLIENT_COMPANY", "CLIENT_ROLE",
        "AGENT_NAME", "CLIENT_EMAIL_PRIMARY", "CLIENT_EMAIL_COS",
        "CLIENT_USERNAME", "CLIENT_TIMEZONE", "BRIEF_MORNING_HOUR",
        "BRIEF_EVENING_HOUR", "TELEGRAM_BOT_TOKEN", "TELEGRAM_USER_ID",
        "TELEGRAM_GROUP_ID", "ANTHROPIC_API_KEY", "GDRIVE_BACKUP_FOLDER_ID",
    ]
    cred_payload = "\n".join(k + "=" + creds.get(k, "") for k in cred_keys)
    encoded_creds = base64.b64encode(cred_payload.encode()).decode()
    encoded_seed = base64.b64encode(json.dumps(seed_data).encode()).decode()

    # Build launch.sh
    launch_path = os.path.join(client_dir, "launch.sh")

    phase1 = (
        '#!/usr/bin/env bash\n'
        '# VELA Unified Installation + Intelligence Seeder\n'
        '# Client: ' + creds.get('CLIENT_NAME', 'Unknown') + '\n'
        '# Generated: ' + timestamp + '\n'
        '# Source: Tally webhook (automated)\n'
        '# DO NOT MODIFY\n\n'
        '_VELA_CRED_PAYLOAD="' + encoded_creds + '"\n'
        "eval \"$(echo \"$_VELA_CRED_PAYLOAD\" | base64 --decode | while IFS='=' read -r key val; do echo \"export $key='$val'\"; done)\"\n"
        'export VELA_PREFILLED=true\n\n'
        'curl -fsSL ' + INSTALL_URL + ' | bash\n'
        'INSTALL_EXIT=$?\n\n'
        'if [[ $INSTALL_EXIT -ne 0 ]]; then\n'
        '  echo ""\n'
        '  echo -e "\\033[0;31m✗\\033[0m Install failed. Skipping intelligence seeding."\n'
        '  echo "  Contact your Handler: greg@gregshindler.com"\n'
        '  exit $INSTALL_EXIT\n'
        'fi\n\n'
    )

    phase2 = (
        'echo ""\n'
        'echo -e "\\033[0;34m\\033[1m━━━ Seeding Hannah\'s Intelligence Layer ━━━\\033[0m"\n'
        'echo ""\n\n'
        '_VELA_SEED_PAYLOAD="' + encoded_seed + '"\n'
        'SEED_JSON=$(echo "$_VELA_SEED_PAYLOAD" | base64 --decode)\n\n'
        'HANNAH_DB="$HOME/.openclaw/hannah.db"\n\n'
        'if [[ ! -f "$HANNAH_DB" ]]; then\n'
        '  echo -e "\\033[0;33m⚠\\033[0m  hannah.db not found. Skipping seed."\n'
        '  exit 0\n'
        'fi\n\n'
    )

    # Seeder uses the actual schema:
    # entities: id TEXT PK, type, name, status, priority, context, tags,
    #           last_updated, stage, next_action, strategic_val, owner,
    #           risk, deal_type, category, momentum, last_contact
    # priorities: rank INTEGER PK, entity_id, objective, next_action,
    #             owner, deadline, urgency, momentum, updated
    # signals: id AUTOINCREMENT, ts, source, entity_id, signal_type,
    #          ium_score, summary, action_taken
    seeder_py = r'''echo "$SEED_JSON" | python3 -c "
import sys, json, sqlite3, os, uuid, re
from datetime import datetime, timezone

data = json.load(sys.stdin)
db_path = os.path.expanduser('~/.openclaw/hannah.db')
ws = os.path.expanduser('~/.openclaw/workspace-cos')
now = datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')

db = sqlite3.connect(db_path)
db.row_factory = sqlite3.Row
c = db.cursor()

def make_id(prefix, name):
    slug = re.sub(r'[^a-z0-9]', '_', name.lower())[:24].strip('_')
    return prefix + '_' + slug

# ── Relationships ──
rel_count = 0
for r in data.get('relationships', []):
    name = r.get('name', '').strip()
    if not name:
        continue
    eid = make_id('person', name)
    context_parts = []
    if r.get('company'): context_parts.append('Company: ' + r['company'])
    if r.get('role'):    context_parts.append('Role: ' + r['role'])
    if r.get('notes'):   context_parts.append(r['notes'])
    context = ' | '.join(context_parts)
    c.execute(
        'INSERT OR REPLACE INTO entities '
        '(id, type, name, status, priority, context, last_updated, momentum) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
        (eid, 'person', name, r.get('status', 'warm'), 3, context, now, 'steady')
    )
    c.execute(
        'INSERT INTO signals (ts, source, entity_id, signal_type, summary) '
        'VALUES (?, ?, ?, ?, ?)',
        (now, 'seed', eid, 'context', 'Seeded relationship: ' + name)
    )
    rel_count += 1

db.commit()
if rel_count:
    print('  \033[0;32m✓\033[0m ' + str(rel_count) + ' relationships seeded')

# ── Deals ──
deal_count = 0
for d in data.get('deals', []):
    name = d.get('name', '').strip()
    if not name:
        continue
    eid = make_id('deal', name)
    context_parts = []
    if d.get('counterparty'): context_parts.append('Counterparty: ' + d['counterparty'])
    if d.get('next_action'):  context_parts.append('Next: ' + d['next_action'])
    context = ' | '.join(context_parts)
    c.execute(
        'INSERT OR REPLACE INTO entities '
        '(id, type, name, status, priority, context, stage, next_action, last_updated, momentum) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        (eid, 'deal', name, 'active', 2, context,
         d.get('stage', 'active'), d.get('next_action', ''), now, 'steady')
    )
    c.execute(
        'INSERT INTO signals (ts, source, entity_id, signal_type, summary) '
        'VALUES (?, ?, ?, ?, ?)',
        (now, 'seed', eid, 'context', 'Seeded deal: ' + name)
    )
    deal_count += 1

db.commit()
if deal_count:
    print('  \033[0;32m✓\033[0m ' + str(deal_count) + ' deals seeded')

# ── Priorities ──
# Get current max rank to avoid PK collision
existing_ranks = [row[0] for row in c.execute('SELECT rank FROM priorities').fetchall()]
base_rank = max(existing_ranks) + 1 if existing_ranks else 1

pri_count = 0
for i, p in enumerate(data.get('priorities', []), 0):
    title = p.get('title', '').strip()
    if not title:
        continue
    rank = base_rank + i
    eid = make_id('priority', title)
    # Also insert as an entity so priorities table entity_id resolves
    c.execute(
        'INSERT OR REPLACE INTO entities '
        '(id, type, name, status, priority, context, next_action, last_updated, urgency, momentum) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        (eid, 'priority', title, 'active', rank,
         p.get('objective', ''), p.get('next_action', ''), now,
         p.get('urgency', 'normal'), p.get('momentum', 'steady'))
    ) if False else None  # entities table has no urgency col — skip
    c.execute(
        'INSERT OR REPLACE INTO priorities '
        '(rank, entity_id, objective, next_action, owner, urgency, momentum, updated) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
        (rank, eid,
         title + ((' — ' + p['objective']) if p.get('objective') else ''),
         p.get('next_action', ''),
         'Greg',
         p.get('urgency', 'normal'),
         p.get('momentum', 'steady'),
         now)
    )
    c.execute(
        'INSERT INTO signals (ts, source, entity_id, signal_type, summary) '
        'VALUES (?, ?, ?, ?, ?)',
        (now, 'seed', eid, 'context', 'Seeded priority #' + str(rank) + ': ' + title)
    )
    pri_count += 1

db.commit()
if pri_count:
    print('  \033[0;32m✓\033[0m ' + str(pri_count) + ' priorities seeded')

# ── Watchlist ──
watch_count = 0
for w in data.get('watchlist', []):
    company = w.get('name', '').strip()
    if not company:
        continue
    eid = make_id('company', company)
    c.execute(
        'INSERT OR REPLACE INTO entities '
        '(id, type, name, status, context, last_updated, momentum) '
        'VALUES (?, ?, ?, ?, ?, ?, ?)',
        (eid, 'company', company, 'active', w.get('reason', ''), now, 'steady')
    )
    c.execute(
        'INSERT INTO signals (ts, source, entity_id, signal_type, summary) '
        'VALUES (?, ?, ?, ?, ?)',
        (now, 'seed', eid, 'intel', 'Watchlist: ' + company + ' — ' + w.get('reason', ''))
    )
    watch_count += 1

db.commit()
db.close()

# ── Watchlist -> MEMORY.md ──
if watch_count:
    mem_path = os.path.join(ws, 'MEMORY.md')
    with open(mem_path, 'a') as f:
        f.write('\n\n## Intelligence Watchlist (Seeded)\n\n')
        for w in data.get('watchlist', []):
            if w.get('name'):
                f.write('- ' + w['name'] + ': ' + w.get('reason', '') + '\n')
    print('  \033[0;32m✓\033[0m ' + str(watch_count) + ' intelligence targets seeded')

# ── Standing rules -> DISPATCH_RULES.md ──
rules = data.get('standing_rules', [])
rules = [r for r in rules if r.strip()]
if rules:
    rules_path = os.path.join(ws, 'DISPATCH_RULES.md')
    with open(rules_path, 'a') as f:
        f.write('\n\n## Client Standing Rules (Seeded)\n\n')
        for r in rules:
            f.write('- ' + r + '\n')
    print('  \033[0;32m✓\033[0m ' + str(len(rules)) + ' standing rules written')

# ── Communication preferences -> USER.md ──
comm = data.get('communication', {})
if any(v for v in comm.values() if v):
    user_path = os.path.join(ws, 'USER.md')
    with open(user_path, 'a') as f:
        f.write('\n\n## Communication Preferences (Seeded)\n\n')
        if comm.get('format'): f.write('Briefing format: ' + comm['format'] + '\n')
        if comm.get('length'): f.write('Briefing length: ' + comm['length'] + '\n')
        if comm.get('style'):  f.write('Communication style: ' + comm['style'] + '\n')
        if comm.get('extra'):  f.write('Additional notes: ' + comm['extra'] + '\n')
    print('  \033[0;32m✓\033[0m Communication preferences written')

# ── Personal detail -> USER.md ──
detail = data.get('personal_detail', '').strip()
if detail:
    user_path = os.path.join(ws, 'USER.md')
    with open(user_path, 'a') as f:
        f.write('\n\n## Personal Context (Seeded)\n\n')
        f.write(detail + '\n')
    print('  \033[0;32m✓\033[0m Personal detail written')

# ── Verification ──
db2 = sqlite3.connect(db_path)
c2 = db2.cursor()
ent  = c2.execute(\"SELECT COUNT(*) FROM entities WHERE source='seed' OR last_updated >= datetime('now', '-1 hour')\").fetchone()[0]
pri2 = c2.execute(\"SELECT COUNT(*) FROM priorities WHERE updated >= datetime('now', '-1 hour')\").fetchone()[0]
sig  = c2.execute(\"SELECT COUNT(*) FROM signals WHERE source='seed' AND ts >= datetime('now', '-1 hour')\").fetchone()[0]
db2.close()
print('\n  Database: ' + str(ent) + ' entities, ' + str(pri2) + ' priorities, ' + str(sig) + ' seed signals')
print('\n\033[0;32m✓\033[0m Hannah is installed and seeded. Ready for first session.')
" 2>/dev/null || echo "  ⚠ Seeding encountered errors. Handler will verify."

echo ""
'''

    # Phase 3: Gateway provisioning
    phase3 = r'''# ── PHASE 3: Gateway provisioning ──
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

# Check OpenClaw exists
if [[ ! -f "$OPENCLAW_BIN" ]]; then
  echo -e "\033[0;33m⚠\033[0m  OpenClaw not found at $OPENCLAW_BIN. Gateway not provisioned."
  echo "  Handler will provision the gateway manually via SSH."
  exit 0
fi

mkdir -p "$HOME/Library/LaunchAgents"
mkdir -p "$LOG_DIR"
mkdir -p "$(dirname "$REGISTRY_FILE")"

# Initialize port registry if it does not exist
if [[ ! -f "$REGISTRY_FILE" ]]; then
  echo '{"instances":[],"_meta":{"created":"'"$(date -u +%Y-%m-%dT%H:%M:%SZ)"'","version":"1.0"}}' > "$REGISTRY_FILE"
fi

# Get next available port (base 18789)
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

# Generate plist
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

echo -e "  \033[0;32m✓\033[0m Plist generated: $PLIST_FILE"

# Register in port registry
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

# Unload if already loaded (idempotent)
launchctl bootout "gui/${UID_NUM}/${SERVICE_NAME}" 2>/dev/null || true
sleep 1

# Load and start
launchctl bootstrap "gui/${UID_NUM}" "$PLIST_FILE" 2>/dev/null
echo -e "  \033[0;36m▸\033[0m Starting gateway..."

# Wait for startup
ATTEMPTS=0
MAX_ATTEMPTS=15
while [[ $ATTEMPTS -lt $MAX_ATTEMPTS ]]; do
  if lsof -i :"$GATEWAY_PORT" -sTCP:LISTEN &>/dev/null 2>&1; then
    GW_PID=$(lsof -ti :"$GATEWAY_PORT" -sTCP:LISTEN 2>/dev/null || echo "unknown")
    echo -e "  \033[0;32m✓\033[0m Gateway is running on port $GATEWAY_PORT (PID $GW_PID)"
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
'''

    with open(launch_path, "w") as f:
        f.write(phase1 + phase2 + seeder_py + phase3)

    os.chmod(launch_path, 0o755)
    log.info("launch.sh saved: " + launch_path)
    return client_id, client_dir


# ══════════════════════════════════════════════════════════════
# TELEGRAM NOTIFICATION
# ══════════════════════════════════════════════════════════════

def send_telegram(bot_token, chat_id, message):
    if not bot_token or not chat_id:
        return
    try:
        url = "https://api.telegram.org/bot" + bot_token + "/sendMessage"
        payload = json.dumps({
            "chat_id": chat_id, "text": message, "parse_mode": "HTML"
        }).encode()
        req = urllib.request.Request(
            url, data=payload, headers={"Content-Type": "application/json"}
        )
        urllib.request.urlopen(req, timeout=10)
        log.info("Telegram notification sent.")
    except Exception as e:
        log.warning("Telegram notification failed: " + str(e))


# ══════════════════════════════════════════════════════════════
# WEBHOOK HANDLER
# ══════════════════════════════════════════════════════════════

class VelaWebhookHandler(BaseHTTPRequestHandler):
    config = None

    def log_message(self, format, *args):
        log.info("HTTP: " + (format % args))

    def do_POST(self):
        if self.path != "/webhook/tally":
            self.send_response(404)
            self.end_headers()
            return

        content_length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(content_length)

        # Log raw payload for debugging
        try:
            raw = json.loads(body)
            log.info("Received submission from: " +
                     raw.get("data", {}).get("fields", [{}])[0].get("value", "unknown"))
        except:
            pass

        try:
            data = json.loads(body)
        except json.JSONDecodeError:
            self.send_response(400)
            self.end_headers()
            return

        # Acknowledge immediately
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(b'{"status":"received"}')

        # Process
        try:
            self.process_submission(data)
        except Exception as e:
            log.error("Processing failed: " + str(e), exc_info=True)
            send_telegram(
                self.config.get("telegram_bot_token_for_notifications", ""),
                self.config.get("telegram_chat_id_for_notifications", ""),
                "⚠ VELA webhook error: " + str(e),
            )

    def do_GET(self):
        if self.path == "/health":
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(b'{"status":"ok","service":"vela-webhook"}')
            return
        self.send_response(404)
        self.end_headers()

    def process_submission(self, data):
        cfg = self.config
        creds, seed_data, oauth_url = extract_all(data, cfg)

        log.info("Extracted: " + creds.get("CLIENT_NAME", "Unknown"))
        log.info("  Relationships: " + str(len(seed_data["relationships"])) +
                 ", Deals: " + str(len(seed_data["deals"])) +
                 ", Priorities: " + str(len(seed_data["priorities"])) +
                 ", Rules: " + str(len(seed_data["standing_rules"])) +
                 ", Watchlist: " + str(len(seed_data["watchlist"])))

        # Validate
        errors = validate_credentials(creds)
        if errors:
            error_msg = "\n".join("  - " + e for e in errors)
            log.error("Validation failed:\n" + error_msg)
            send_telegram(
                cfg.get("telegram_bot_token_for_notifications", ""),
                cfg.get("telegram_chat_id_for_notifications", ""),
                "⚠ VELA Tally submission from <b>" +
                creds.get("CLIENT_NAME", "Unknown") +
                "</b> has errors:\n" + error_msg + "\n\nReview manually.",
            )
            # Still generate files so you can fix and re-run
            log.info("Generating files despite validation errors...")

        # Generate
        client_id, client_dir = generate_client_files(creds, seed_data, oauth_url)

        # Notify
        sd = seed_data
        msg = (
            "✓ <b>Tally submission processed</b>\n\n"
            "Client: " + creds["CLIENT_NAME"] + "\n"
            "Company: " + creds["CLIENT_COMPANY"] + "\n"
            "Agent: " + creds["AGENT_NAME"] + "\n\n"
            "Intelligence:\n"
            "  Relationships: " + str(len(sd["relationships"])) + "\n"
            "  Deals: " + str(len(sd["deals"])) + "\n"
            "  Priorities: " + str(len(sd["priorities"])) + "\n"
            "  Rules: " + str(len(sd["standing_rules"])) + "\n"
            "  Watchlist: " + str(len(sd["watchlist"])) + "\n"
            "  Personal: " + ("yes" if sd["personal_detail"] else "no") + "\n\n"
            "Files: " + client_dir + "\n"
            "launch.sh ready to send."
        )
        if errors:
            msg += "\n\n⚠ Validation warnings:\n" + "\n".join("  - " + e for e in errors)

        send_telegram(
            cfg.get("telegram_bot_token_for_notifications", ""),
            cfg.get("telegram_chat_id_for_notifications", ""),
            msg,
        )
        log.info("Complete: " + client_id)


# ══════════════════════════════════════════════════════════════
# MAIN
# ══════════════════════════════════════════════════════════════

def load_config(path):
    if not os.path.exists(path):
        log.error("Config not found: " + path)
        log.error("Run: python3 vela_webhook.py --init")
        sys.exit(1)
    with open(path) as f:
        return json.load(f)


def main():
    parser = argparse.ArgumentParser(description="VELA Webhook Listener")
    parser.add_argument("--port", type=int, default=DEFAULT_PORT)
    parser.add_argument("--config", default=DEFAULT_CONFIG)
    parser.add_argument("--init", action="store_true")
    args = parser.parse_args()

    os.makedirs(CLIENTS_DIR, exist_ok=True)
    os.makedirs(os.path.dirname(args.config), exist_ok=True)

    if args.init:
        print("Use the pre-built webhook_config.json from your VELA session.")
        print("Copy it to: " + args.config)
        return

    config = load_config(args.config)
    VelaWebhookHandler.config = config

    server = HTTPServer(("0.0.0.0", args.port), VelaWebhookHandler)
    log.info("VELA Webhook Listener v2.1 started on port " + str(args.port))
    log.info("Endpoint: http://localhost:" + str(args.port) + "/webhook/tally")
    log.info("Health: http://localhost:" + str(args.port) + "/health")

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        log.info("Shutting down.")
        server.server_close()


if __name__ == "__main__":
    main()
