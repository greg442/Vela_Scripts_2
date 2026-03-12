#!/usr/bin/env python3
"""
VELA Executive Intelligence Systems
Cost Alert Script — v1.0, March 2026

Checks Anthropic API spend against a daily threshold.
Sends Telegram alert if threshold exceeded.
Designed to run via cron at end of each business day.

Cron entry (6pm weekdays):
  0 18 * * 1-5 python3 ~/.openclaw/scripts/cost_alert.py

Reads from ~/.openclaw/.env for credentials.
Reads OpenClaw usage log for today's spend data.

Escalation levels:
  WARNING  — 50% of daily limit ($7.50 with $15 limit)
  ALERT    — 100% of daily limit ($15)
  CRITICAL — 200% of daily limit ($30) — likely a retry loop
"""

import os
import re
import json
import urllib.request
import urllib.parse
from datetime import datetime
from pathlib import Path

# ── CONFIG ──────────────────────────────────────────────────
OPENCLAW_DIR    = Path.home() / ".openclaw"
LOG_DIR         = OPENCLAW_DIR / "logs"
ALERT_LOG       = LOG_DIR / "cost-alert.log"
ENV_FILE        = OPENCLAW_DIR / ".env"

# Thresholds (USD)
DAILY_BUDGET    = 15.00   # Normal ceiling — $3-5 is healthy
WARN_THRESHOLD  = DAILY_BUDGET * 0.50   # $7.50 — worth knowing
ALERT_THRESHOLD = DAILY_BUDGET          # $15   — unusual, investigate
CRIT_THRESHOLD  = DAILY_BUDGET * 2.0   # $30   — something is wrong

# ── HELPERS ─────────────────────────────────────────────────
def ts():
    return datetime.now().strftime("%Y-%m-%d %H:%M:%S")

def log(msg):
    ALERT_LOG.parent.mkdir(parents=True, exist_ok=True)
    line = f"[{ts()}] {msg}"
    print(line)
    with open(ALERT_LOG, "a") as f:
        f.write(line + "\n")

def load_env():
    """Load .env file into os.environ."""
    if not ENV_FILE.exists():
        return
    with open(ENV_FILE) as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                key, _, val = line.partition("=")
                os.environ.setdefault(key.strip(), val.strip())

def send_telegram(message: str, token: str, chat_id: str):
    """Send a Telegram message."""
    if not token or not chat_id:
        log("WARNING: Telegram not configured — skipping notification")
        return False
    payload = json.dumps({
        "chat_id": chat_id,
        "text": message,
        "parse_mode": "Markdown"
    }).encode()
    req = urllib.request.Request(
        f"https://api.telegram.org/bot{token}/sendMessage",
        data=payload,
        headers={"Content-Type": "application/json"}
    )
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            result = json.loads(resp.read())
            return result.get("ok", False)
    except Exception as e:
        log(f"ERROR: Telegram send failed: {e}")
        return False

# ── COST EXTRACTION ─────────────────────────────────────────
def get_todays_spend() -> float:
    """
    Try multiple methods to determine today's API spend.
    Returns best estimate in USD.
    """
    today = datetime.now().strftime("%Y-%m-%d")
    total = 0.0

    # Method 1: OpenClaw daily usage log (format: cost=0.0234)
    usage_log = LOG_DIR / f"usage-{today}.log"
    if usage_log.exists():
        with open(usage_log) as f:
            content = f.read()
        matches = re.findall(r'cost=([0-9]+\.?[0-9]*)', content)
        if matches:
            total = sum(float(m) for m in matches)
            log(f"Cost from usage log: ${total:.4f} ({len(matches)} entries)")
            return total

    # Method 2: Parse OpenClaw gateway log for token counts
    # Pricing: input $3/MTok, output $15/MTok, cache-read $0.30/MTok, cache-write-5m $3.75/MTok
    INPUT_RATE      = 3.00 / 1_000_000
    OUTPUT_RATE     = 15.00 / 1_000_000
    CACHE_READ_RATE = 0.30 / 1_000_000
    CACHE_WRITE_RATE= 3.75 / 1_000_000

    gateway_log = LOG_DIR / "gateway.log"
    if gateway_log.exists():
        input_toks = output_toks = cache_read = cache_write = 0
        with open(gateway_log) as f:
            for line in f:
                if today not in line:
                    continue
                # Extract token counts from OpenClaw log format
                m_in  = re.search(r'input_tokens[=:]\s*([0-9]+)', line)
                m_out = re.search(r'output_tokens[=:]\s*([0-9]+)', line)
                m_cr  = re.search(r'cache_read[=:]\s*([0-9]+)', line)
                m_cw  = re.search(r'cache_write[=:]\s*([0-9]+)', line)
                if m_in:  input_toks  += int(m_in.group(1))
                if m_out: output_toks += int(m_out.group(1))
                if m_cr:  cache_read  += int(m_cr.group(1))
                if m_cw:  cache_write += int(m_cw.group(1))
        if input_toks + output_toks > 0:
            total = (input_toks * INPUT_RATE + output_toks * OUTPUT_RATE +
                     cache_read * CACHE_READ_RATE + cache_write * CACHE_WRITE_RATE)
            log(f"Cost from token counts: ${total:.4f} "
                f"(in={input_toks:,} out={output_toks:,} "
                f"cr={cache_read:,} cw={cache_write:,})")
            return total

    # Method 3: Check Anthropic usage API (if key available)
    api_key = os.environ.get("ANTHROPIC_API_KEY", "")
    if api_key:
        try:
            req = urllib.request.Request(
                f"https://api.anthropic.com/v1/usage?date={today}",
                headers={
                    "x-api-key": api_key,
                    "anthropic-version": "2023-06-01"
                }
            )
            with urllib.request.urlopen(req, timeout=10) as resp:
                data = json.loads(resp.read())
                # If Anthropic returns a cost field
                if "cost_usd" in data:
                    total = float(data["cost_usd"])
                    log(f"Cost from Anthropic API: ${total:.4f}")
                    return total
        except Exception:
            pass  # API may not support this endpoint — fall through

    # Method 4: Estimate from triage log activity (conservative proxy)
    triage_log = LOG_DIR / "triage.log"
    if triage_log.exists():
        with open(triage_log) as f:
            today_lines = [l for l in f if today in l]
        runs = len([l for l in today_lines if "complete" in l.lower()])
        if runs > 0:
            # Each hannah session ~ $0.50-2.00 avg; triage runs ~ $0.01 each
            estimate = runs * 0.01
            log(f"Cost estimate from triage activity: ${estimate:.4f} (proxy only — check console.anthropic.com)")
            return estimate

    log("WARNING: No cost data found for today. Check console.anthropic.com manually.")
    return 0.0

# ── MAIN ────────────────────────────────────────────────────
def main():
    load_env()
    telegram_token   = os.environ.get("TELEGRAM_BOT_TOKEN", "")
    telegram_chat_id = os.environ.get("TELEGRAM_USER_CHAT_ID", "")
    today_str = datetime.now().strftime("%A, %B %-d")

    log("── Cost Alert Check Starting ──")

    # Test mode — forces a mock alert to verify Telegram delivery
    if os.environ.get("VELA_TEST_ALERT") == "1":
        log("TEST MODE — sending mock alert to verify Telegram...")
        message = (
            f"🧪 *VELA Cost Alert — TEST*\n\n"
            f"📅 {today_str}\n"
            f"💸 Mock spend: *$18.50*\n"
            f"📊 Daily budget: ${DAILY_BUDGET:.2f}\n"
            f"📈 Usage: 123% of limit\n\n"
            f"⚡ This is a test message. Telegram alerting is working correctly.\n\n"
            f"_VELA Cost Monitor TEST — {ts()}_"
        )
        sent = send_telegram(message, telegram_token, telegram_chat_id)
        if sent:
            log("✓ Test alert sent successfully — Telegram is configured correctly.")
        else:
            log("✗ Test alert failed — check TELEGRAM_BOT_TOKEN and TELEGRAM_USER_CHAT_ID in ~/.openclaw/.env")
        return

    spend = get_todays_spend()
    log(f"Today's spend: ${spend:.4f}")

    # Determine alert level
    if spend >= CRIT_THRESHOLD:
        level   = "🚨 CRITICAL"
        emoji   = "🚨"
        urgency = f"This is {spend/DAILY_BUDGET:.0f}x your daily budget. A retry loop or runaway agent is likely."
        should_alert = True
    elif spend >= ALERT_THRESHOLD:
        level   = "🔴 ALERT"
        emoji   = "🔴"
        urgency = "Unusual usage. Review Hannah's session log and check for long sessions or retry loops."
        should_alert = True
    elif spend >= WARN_THRESHOLD:
        level   = "🟡 WARNING"
        emoji   = "🟡"
        urgency = "Elevated usage. Normal if you had a heavy task day. Monitor tomorrow."
        should_alert = True
    else:
        level   = "✅ NORMAL"
        log(f"Spend ${spend:.2f} is within normal range (limit: ${DAILY_BUDGET:.2f}). No alert needed.")
        log("── Cost Alert Check Complete ──")
        return

    # Build message
    message = (
        f"{emoji} *VELA Cost Alert — {level}*\n\n"
        f"📅 {today_str}\n"
        f"💸 Today's spend: *${spend:.2f}*\n"
        f"📊 Daily budget: ${DAILY_BUDGET:.2f}\n"
        f"📈 Usage: {(spend/DAILY_BUDGET)*100:.0f}% of limit\n\n"
        f"⚡ {urgency}\n\n"
        f"🔗 Review: console.anthropic.com\n"
        f"💡 Fix: Send /new to Hannah, check cron logs, restart gateway if needed.\n\n"
        f"_VELA Cost Monitor — {ts()}_"
    )

    log(f"Sending {level} alert via Telegram...")
    sent = send_telegram(message, telegram_token, telegram_chat_id)
    if sent:
        log(f"Alert sent successfully: {level} — ${spend:.2f}")
    else:
        log(f"Alert send failed — check Telegram config in .env")

    log("── Cost Alert Check Complete ──")

if __name__ == "__main__":
    main()
