# VELA Operator Reference
## Internal Use Only — Do Not Share

This document is for Greg Shindler / VELA operations only.

---

## What vela_deploy.sh Is and Who It's For

`vela_deploy.sh` is **your provisioning script** — not a client tool.

You run it on **your Mac Mini** before every new client installation call.
Clients never see it, run it, or know it exists.

**What it does:**
1. Prompts you for the client's details (name, company, email, tier)
2. Generates a unique VELA license key for that client
3. Prints the SQL to add the key to your license server
4. Creates a client manifest at `~/.vela/deployments/[client_id].conf`
5. Gives you the pre-install checklist and install call materials

**When to run it:** The day before every install call.

```bash
bash vela_deploy.sh
```

---

## Repo Structure — What Each File Is For

| File | For | Purpose |
|------|-----|---------|
| `install.sh` | Clients | The one-liner they paste into Terminal |
| `vela_deploy.sh` | You only | Generates license key, client manifest, checklist |
| `README.md` | Clients | Clean, no internal details |
| `OPERATOR.md` | You only | This file |
| `scripts/vela_install.sh` | Automation | Called by install.sh — full 18-step installer |
| `scripts/license_check.py` | Automation | License ping at session start + daily cron |
| `scripts/email_triage.py` | Automation | Email triage pipeline |
| `scripts/cost_alert.py` | Automation | Daily spend alert via Telegram |
| `scripts/backup_gdrive.sh` | Automation | Nightly Google Drive backup |
| `templates/workspace-cos/` | Installer | Hannah's 9 workspace files with placeholders |
| `license_server/server.py` | Your droplet | Flask validation API — clients never hit this directly |
| `license_server/admin.py` | You only | Your management CLI |

---

## Operator Workflow — Every New Client

### Step 1 — Provision (day before the call)

```bash
bash vela_deploy.sh
```

Generates license key, prints SQL, creates client manifest, gives you the checklist.

### Step 2 — Add key to license server

```bash
ssh root@165.22.36.184
sqlite3 /opt/vela/licenses.db "INSERT INTO licenses ..."
```

### Step 3 — Test validation before the call

```bash
curl -s -X POST http://165.22.36.184:8080/validate \
  -H "Content-Type: application/json" \
  -d '{"license_key": "VELA-XXXX-XXXX-XXXX-XXXX"}'
# Should return: {"status":"active","tier":"command",...}
```

### Step 4 — The install call

Client pastes the one-liner into Terminal. You watch via Tailscale SSH.
Install takes 30-90 minutes.

### Step 5 — Post-install (run on their machine via SSH)

```bash
bash ~/.openclaw/scripts/monitoring/setup_monitoring.sh
bash ~/.openclaw/scripts/monitoring/setup_tailscale.sh
```

---

## Managing Clients (admin.py)

Configure once on your Mac:

```bash
cat > ~/.vela_admin.conf << EOF
VELA_SERVER_URL=http://165.22.36.184:8080
VELA_ADMIN_KEY=vela-admin-d2724b0584e53dafe7dd35c37393f484
EOF
```

Then:

```bash
python3 license_server/admin.py list
python3 license_server/admin.py status CLIENT_ID
python3 license_server/admin.py suspend CLIENT_ID      # kill switch
python3 license_server/admin.py reinstate CLIENT_ID
python3 license_server/admin.py ping-report            # who hasn't checked in
```

---

## License Server

- **IP:** 165.22.36.184
- **SSH:** `ssh root@165.22.36.184`
- **Database:** `/opt/vela/licenses.db`
- **Service:** `systemctl status vela-license`
- **Admin key:** stored in `/opt/vela/.env` on the droplet

---

## Pricing (Internal Reference)

Single tier — full system, everything included:
- **$1,500/month** subscription
- **$2,500** one-time turnkey install fee
- **$500** DIY install option + $1,500/month

---

## Client Manifests

Stored at `~/.vela/deployments/[client_id].conf`.
Fill in after each install: TAILSCALE_IP, INSTALL_DATE, ANTHROPIC_ACCOUNT,
TELEGRAM_BOT, TELEGRAM_GROUP_ID.

---

*INTERNAL — VELA Private Command Infrastructure — Greg Shindler*