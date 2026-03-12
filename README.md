# VELA Executive Intelligence Systems
### Private AI Executive Team — Installation Scripts

> **PROPRIETARY & CONFIDENTIAL**  
> This repository is private. Unauthorized access, distribution, or reproduction is prohibited.  
> © 2026 Greg Shindler. All rights reserved.

---

## One-Line Install

Open Terminal on your Mac Mini and paste this:

```bash
curl -fsSL https://raw.githubusercontent.com/greg442/vela_scripts/main/install.sh | bash
```

That's it. The installer downloads everything it needs and walks you through the rest.

**Estimated time:** 20–40 minutes (Ollama model downloads are the slow part).

---

## Before You Run This

You need credentials ready before the install begins. Read the **README First** document provided with your VELA package — it tells you exactly what to collect and where to get it.

**Required before install:**
- Anthropic API key — [console.anthropic.com](https://console.anthropic.com/settings/keys)
- Telegram Bot Token — [t.me/BotFather](https://t.me/BotFather)
- Telegram User ID + Group ID — [t.me/userinfobot](https://t.me/userinfobot)
- Gmail address(es) you want monitored
- Google OAuth credentials — [console.cloud.google.com](https://console.cloud.google.com/apis/credentials)
- Tailscale account — [tailscale.com](https://tailscale.com)
- Google Drive backup folder ID

---

## What Gets Installed

| Script | Purpose |
|--------|---------|
| `vela_install.sh` | Full system install — Homebrew, Node, Python, Ollama, OpenClaw, all agents |
| `install_uptime_kuma.sh` | Service monitoring dashboard on port 3001 |
| `backup_gdrive.sh` | Nightly Google Drive backup with Telegram confirmation |
| `cost_alert.py` | Daily Anthropic spend check with Telegram escalation alerts |
| `email_triage.py` | Email classification via local Ollama — runs every 15 min |
| `reset_sessions.sh` | Clears bloated session files — runs 2x daily via cron |
| `backup_local.sh` | Local archive backup — runs nightly, keeps 7 days |

---

## Running Individual Scripts

After initial install, scripts live at `~/.openclaw/scripts/`. You can also run them directly from this repo:

```bash
# Install or update Uptime Kuma
curl -fsSL https://raw.githubusercontent.com/greg442/vela_scripts/main/scripts/install_uptime_kuma.sh | bash

# Set up Google Drive backup (first time)
curl -fsSL https://raw.githubusercontent.com/greg442/vela_scripts/main/scripts/backup_gdrive.sh -o ~/backup_gdrive.sh
chmod +x ~/backup_gdrive.sh && ~/backup_gdrive.sh --setup

# Run a manual backup
curl -fsSL https://raw.githubusercontent.com/greg442/vela_scripts/main/scripts/backup_gdrive.sh | bash

# Test cost alerting
curl -fsSL https://raw.githubusercontent.com/greg442/vela_scripts/main/scripts/cost_alert.py | python3
```

---

## System Requirements

- Mac Mini M4 — 16 GB RAM minimum, 32 GB recommended
- macOS 14 (Sonoma) or newer
- Ethernet connection (not WiFi)
- 50 GB free disk space
- Admin account

---

## Repository Structure

```
vela-scripts/
├── install.sh                  ← Entry point — the one-line install
├── scripts/
│   ├── vela_install.sh         ← Full system installer
│   ├── install_uptime_kuma.sh  ← Monitoring dashboard
│   ├── backup_gdrive.sh        ← Google Drive backup
│   ├── backup_local.sh         ← Local archive backup
│   ├── cost_alert.py           ← Daily spend alerting
│   ├── email_triage.py         ← Email classification
│   └── reset_sessions.sh       ← Session hygiene
└── docs/
    └── (documentation PDFs — not stored in repo)
```

---

## Support

This system is maintained by VELA Executive Intelligence Systems.  
Contact: Greg Shindler — [your email here]

For remote support, ensure Tailscale is running on your Mac Mini.
