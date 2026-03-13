# VELA Executive Intelligence Systems
### Private AI Executive Team

> PROPRIETARY AND CONFIDENTIAL
> This repository is private. Unauthorized access or distribution is prohibited.
> 2026 Greg Shindler. All rights reserved.

## One-Line Install

Open Terminal on your Mac Mini:

    curl -fsSL https://raw.githubusercontent.com/greg442/vela_scripts/main/install.sh | bash

Estimated time: 20-40 minutes.

## Before You Run This

Required credentials:
- Anthropic API key: console.anthropic.com/settings/keys
- Telegram Bot Token (Hannah): t.me/BotFather
- Telegram User ID + Group ID: t.me/userinfobot
- Gmail address to monitor
- Google OAuth credentials: console.cloud.google.com

Turnkey clients (provided by installer):
- VELA Monitor bot token
- VELA Monitor chat ID
- Tailscale auth key

## Agent Roster

All agents run on claude-sonnet-4-6 with 1-hour cache and 200k context window.

| Agent | Role |
|-------|------|
| cos | Hannah - Chief of Staff |
| researcher | Deep research and intelligence briefs |
| analyst | Financial models, data analysis |
| legal | Contract review, risk flagging |
| marketing | Copy, positioning, campaigns |
| pm | Project tracking, deadlines, blockers |
| cos-triage | Lightweight local triage (Ollama) |

## Post-Install: Monitoring Setup (Turnkey)

Step 1 - Health checks and client config:

    bash ~/.openclaw/scripts/monitoring/setup_monitoring.sh

Prompts for client name and VELA Monitor credentials.
Installs a 15-minute health check cron. Alerts your installer via Telegram if anything breaks.

Step 2 - Remote access:

    bash ~/.openclaw/scripts/monitoring/setup_tailscale.sh

Connects Mac Mini to VELA remote monitoring network.

## AI Operating Costs

Paid directly to Anthropic - not to VELA.

| Usage Level | Monthly Cost |
|-------------|-------------|
| Light | 75-100 USD |
| Active daily use | 200-350 USD |
| Heavy power user | Up to 500 USD |

## Useful Commands

    # Gateway
    openclaw gateway status
    openclaw gateway stop && openclaw gateway install && openclaw gateway start

    # Check context size
    openclaw agent --agent cos --message "What is your current context size in tokens?" --local

    # Health check manual run
    bash ~/.openclaw/scripts/monitoring/health_check.sh

    # Logs
    tail -50 ~/.openclaw/logs/health_check.log
    tail -50 ~/.openclaw/logs/gateway.log

    # Tailscale
    tailscale status

## Pricing

| Tier | Price | Includes |
|------|-------|---------|
| Done For You | 10000 USD one-time | Mac Mini M4 configured and shipped, full install, all agents briefed, Telegram + WhatsApp + Gmail + Drive connected, 12 months remote monitoring |
| Done With You | 5000 USD one-time | GitHub access, install scripts, guided session, 30 days support. Monitoring: 250 USD/month. |

## Repository Structure

    vela-scripts/
    ├── install.sh
    ├── scripts/
    │   ├── vela_install.sh
    │   ├── reset_sessions.sh
    │   ├── backup_gdrive.sh
    │   ├── backup_local.sh
    │   ├── cost_alert.py
    │   ├── email_triage.py
    │   └── monitoring/
    │       ├── setup_monitoring.sh
    │       ├── health_check.sh
    │       ├── setup_tailscale.sh
    │       └── vela_client.conf.template
    └── templates/
        ├── workspace-cos/
        ├── workspace-researcher/
        ├── workspace-analyst/
        ├── workspace-legal/
        ├── workspace-marketing/
        └── workspace-pm/

## Support

VELA Executive Intelligence Systems
greg@gregshindler.com
By introduction only

For remote support ensure Tailscale is running: tailscale status
