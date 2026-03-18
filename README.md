# VELA Private Command Infrastructure
## Vela_Scripts_2 — Multi-Tenant Deployment Repository

> Your judgment. Our infrastructure.

Private repository. Do not share.

---

## For Clients

Paste this into Terminal on your Mac Mini:

```bash
curl -fsSL https://raw.githubusercontent.com/greg442/Vela_Scripts_2/main/install.sh | bash
```

You will need your **VELA License Key** — provided by your installer.

See `README_First.pdf` (delivered separately) to collect all required credentials before running this.

---

## Repository Structure

```
Vela_Scripts_2/
├── install.sh                  # Client entry point — one command
├── vela_deploy.sh              # Greg's provisioning script — run before each install
├── README.md
│
├── scripts/
│   ├── vela_install.sh         # Full system installer (called by install.sh)
│   ├── license_check.py        # License validation — runs at session start + daily cron
│   ├── email_triage.py         # Email triage pipeline
│   ├── cost_alert.py           # Daily spend alerting
│   ├── reset_sessions.sh       # Session hygiene
│   ├── backup_gdrive.sh        # Nightly Google Drive backup
│   ├── backup_local.sh         # Local archive backup
│   ├── deliver_report.py       # Agent document delivery to Drive + Telegram
│   ├── install_uptime_kuma.sh  # Uptime Kuma monitoring
│   └── monitoring/
│       ├── setup_monitoring.sh
│       ├── health_check.sh
│       └── setup_tailscale.sh
│
├── templates/                  # Workspace files — {{CLIENT_*}} injected at install
│   ├── workspace-cos/          # Hannah's workspace
│   ├── workspace-analyst/
│   ├── workspace-researcher/
│   ├── workspace-marketing/
│   ├── workspace-legal/
│   └── workspace-pm/
│
├── license_server/             # Runs on DigitalOcean droplet
│   ├── server.py               # Flask validation API
│   ├── schema.sql              # SQLite schema
│   ├── admin.py                # Your management CLI
│   └── requirements.txt
│
└── docs/
    ├── ADMIN.md                # Operator reference
    └── DEPLOY.md               # DigitalOcean setup guide
```

---

## Operator Workflow

### Before each install

```bash
bash vela_deploy.sh
```

This generates the license key, prints the SQL to activate it, creates the client manifest, and gives you the install checklist.

### During install call

- Client pastes the one-liner above into Terminal
- You watch via Tailscale SSH: `ssh [username]@vela-[client_id]`
- Install takes 30–90 minutes depending on model download speed

### Managing clients

```bash
# From your Mac, configure once:
cat > ~/.vela_admin.conf << EOF
VELA_SERVER_URL=https://license.vela.run
VELA_ADMIN_KEY=your-admin-key
EOF

# Then:
python3 license_server/admin.py list
python3 license_server/admin.py status client_id
python3 license_server/admin.py suspend client_id    # kill switch
python3 license_server/admin.py reinstate client_id
python3 license_server/admin.py ping-report          # who hasn't checked in
```

---

## License Server

Runs on a $5 DigitalOcean droplet at `license.vela.run`.

See `docs/DEPLOY.md` for full setup instructions.

---

## Tiers

| Tier | Agents | Features |
|------|--------|----------|
| command | All 6 (Hannah + 5 specialists) | Full — briefs, triage, WhatsApp, Drive |
| standard | 3 (Hannah, PM, Researcher) | Briefs + triage only |

Upgrade = one field change server-side. No reinstall.

---

*PROPRIETARY & CONFIDENTIAL — Greg Shindler / VELA Private Command Infrastructure*
*© 2026. All rights reserved.*
