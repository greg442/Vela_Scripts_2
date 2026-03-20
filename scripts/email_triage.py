#!/usr/bin/env python3
"""
VELA Executive Intelligence Systems
Email Triage Script — v1.0, March 2026

Runs every 15 minutes weekdays 8am-6pm via cron.
Classifies emails using local Ollama (zero Anthropic cost).
Sends Telegram alert for ACTION_REQUIRED items only.

Cron entry (installed by vela_install.sh):
  */15 8-18 * * 1-5  python3 ~/.openclaw/scripts/email_triage.py
"""

import subprocess, json, urllib.request, os, sys
from datetime import datetime
from pathlib import Path

OPENCLAW_DIR = Path.home() / ".openclaw"
LOG_FILE     = OPENCLAW_DIR / "logs" / "triage.log"
ENV_FILE     = OPENCLAW_DIR / ".env"

def load_env():
    if not ENV_FILE.exists(): return
    with open(ENV_FILE) as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, _, v = line.partition("=")
                os.environ.setdefault(k.strip(), v.strip())

load_env()

OLLAMA_URL   = os.environ.get("OLLAMA_URL", "http://127.0.0.1:11434")
OLLAMA_MODEL = os.environ.get("OLLAMA_MODEL", "qwen2.5:7b")
ACCOUNTS     = [a for a in [
    os.environ.get("GMAIL_PRIMARY",""),
    os.environ.get("GMAIL_SECONDARY","")
] if a]

def ts():
    return datetime.now().strftime("%Y-%m-%d %H:%M:%S")

def log(msg):
    LOG_FILE.parent.mkdir(parents=True, exist_ok=True)
    line = f"[{ts()}] {msg}"
    print(line)
    with open(LOG_FILE, "a") as f:
        f.write(line + "\n")

def fetch_emails(account):
    try:
        result = subprocess.run(
            ["gog", "gmail", "list", "--account", account, "--unread", "--limit", "20"],
            capture_output=True, text=True, timeout=60
        )
        return result.stdout.strip() if result.returncode == 0 else ""
    except Exception as e:
        return f"[Error: {e}]"

def classify(email_text):
    if not email_text or len(email_text) < 10:
        return None
    prompt = f"""Classify this email as ACTION_REQUIRED or NOISE.

ACTION_REQUIRED: real human asking to decide, reply, or act urgently.
NOISE: newsletters, marketing, automated, receipts, social, noreply.

Email:
{email_text[:1500]}

Reply with only: ACTION_REQUIRED or NOISE"""

    payload = json.dumps({
        "model": OLLAMA_MODEL,
        "prompt": prompt,
        "stream": False,
        "options": {"temperature": 0, "num_predict": 10}
    }).encode()

    req = urllib.request.Request(
        f"{OLLAMA_URL}/api/generate",
        data=payload,
        headers={"Content-Type": "application/json"}
    )
    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            result = json.loads(resp.read())
            return result.get("response", "").strip().upper()
    except Exception as e:
        log(f"Ollama error: {e}")
        return None

def send_telegram(message):
    token   = os.environ.get("TELEGRAM_BOT_TOKEN", "")
    chat_id = os.environ.get("TELEGRAM_USER_CHAT_ID", "")
    if not token or not chat_id:
        log("Telegram not configured — skipping")
        return
    payload = json.dumps({"chat_id": chat_id, "text": message}).encode()
    req = urllib.request.Request(
        f"https://api.telegram.org/bot{token}/sendMessage",
        data=payload,
        headers={"Content-Type": "application/json"}
    )
    try:
        urllib.request.urlopen(req, timeout=15)
    except Exception as e:
        log(f"Telegram error: {e}")

# ── MAIN ──────────────────────────────────────────────────────
now = datetime.now()
action_items = []

for account in ACCOUNTS:
    emails_raw = fetch_emails(account)
    if not emails_raw or "Error" in emails_raw:
        log(f"Could not fetch {account}")
        continue
    lines = [l.strip() for l in emails_raw.split("\n") if l.strip()]
    if not lines:
        log("Inbox clear.")
        continue
    for line in lines[:10]:
        if classify(line) == "ACTION_REQUIRED":
            action_items.append(f"• {line[:120]}")

if action_items:
    msg = "📬 Action Required:\n" + "\n".join(action_items[:5])
    send_telegram(msg)
    log(f"Sent alert: {len(action_items)} item(s).")
else:
    log("Inbox clear — nothing pending.")
