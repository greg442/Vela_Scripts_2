#!/usr/bin/env python3
"""
VELA License Check
------------------
Runs at session start and on daily cron.
Validates VELA_LICENSE_KEY against the license server.
Implements 24-hour grace period for network failures.
Loads tier capabilities into environment.
Sends Telegram stand-down if license is revoked.

Injected at install time:
  VELA_LICENSE_KEY  = {{VELA_LICENSE_KEY}}
  TELEGRAM_BOT_TOKEN = {{TELEGRAM_BOT_TOKEN}}
  TELEGRAM_CHAT_ID   = {{TELEGRAM_CHAT_ID}}
  CLIENT_NAME        = {{CLIENT_NAME}}
"""

import json
import os
import sys
import time
import datetime
import urllib.request
import urllib.error

# ── CONFIG ────────────────────────────────────────────────────
LICENSE_SERVER     = "https://license.vela.run/validate"
GRACE_PERIOD_HOURS = 24
STATE_FILE         = os.path.expanduser("~/.openclaw/logs/license_state.json")
LOG_FILE           = os.path.expanduser("~/.openclaw/logs/license.log")
ENV_FILE           = os.path.expanduser("~/.openclaw/.env")
CLIENT_CONF        = os.path.expanduser("~/.openclaw/vela_client.conf")

# Injected at install time
VELA_LICENSE_KEY   = "{{VELA_LICENSE_KEY}}"
TELEGRAM_BOT_TOKEN = "{{TELEGRAM_BOT_TOKEN}}"
TELEGRAM_CHAT_ID   = "{{TELEGRAM_CHAT_ID}}"
CLIENT_NAME        = "{{CLIENT_NAME}}"

# ── LOGGING ───────────────────────────────────────────────────
def log(msg, level="INFO"):
    ts = datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ")
    line = f"[{ts}] [{level}] {msg}"
    print(line)
    try:
        os.makedirs(os.path.dirname(LOG_FILE), exist_ok=True)
        with open(LOG_FILE, "a") as f:
            f.write(line + "\n")
    except Exception:
        pass

# ── STATE ─────────────────────────────────────────────────────
def load_state():
    try:
        with open(STATE_FILE) as f:
            return json.load(f)
    except Exception:
        return {}

def save_state(state):
    try:
        os.makedirs(os.path.dirname(STATE_FILE), exist_ok=True)
        with open(STATE_FILE, "w") as f:
            json.dump(state, f, indent=2)
    except Exception as e:
        log(f"Could not save state: {e}", "WARN")

# ── TELEGRAM ──────────────────────────────────────────────────
def send_telegram(message):
    if not TELEGRAM_BOT_TOKEN or not TELEGRAM_CHAT_ID or "{{" in TELEGRAM_BOT_TOKEN:
        return
    try:
        url = f"https://api.telegram.org/bot{TELEGRAM_BOT_TOKEN}/sendMessage"
        data = json.dumps({"chat_id": TELEGRAM_CHAT_ID, "text": message}).encode()
        req = urllib.request.Request(url, data=data,
                                     headers={"Content-Type": "application/json"})
        urllib.request.urlopen(req, timeout=10)
    except Exception as e:
        log(f"Telegram send failed: {e}", "WARN")

# ── LICENSE VALIDATION ────────────────────────────────────────
def validate_license(key):
    """
    Returns dict: {status, tier, message} or raises on network error.
    status: active | revoked | expired | invalid
    tier:   command | standard
    """
    payload = json.dumps({"license_key": key}).encode()
    req = urllib.request.Request(
        LICENSE_SERVER, data=payload,
        headers={"Content-Type": "application/json"},
        method="POST"
    )
    with urllib.request.urlopen(req, timeout=15) as resp:
        return json.loads(resp.read().decode())

# ── TIER CAPABILITIES ─────────────────────────────────────────
TIER_CAPABILITIES = {
    "command": {
        "agents": ["cos", "analyst", "marketing", "legal", "pm", "researcher"],
        "morning_brief": True,
        "evening_brief": True,
        "email_triage": True,
        "whatsapp": True,
        "google_drive": True,
        "max_agents": 6,
    },
    "standard": {
        "agents": ["cos", "researcher", "pm"],
        "morning_brief": True,
        "evening_brief": False,
        "email_triage": True,
        "whatsapp": False,
        "google_drive": False,
        "max_agents": 3,
    }
}

def write_tier_env(tier):
    """Write tier capabilities to ~/.openclaw/.vela_tier so Hannah can read them."""
    caps = TIER_CAPABILITIES.get(tier, TIER_CAPABILITIES["standard"])
    tier_file = os.path.expanduser("~/.openclaw/.vela_tier")
    try:
        with open(tier_file, "w") as f:
            json.dump({"tier": tier, "capabilities": caps}, f, indent=2)
        os.chmod(tier_file, 0o600)
    except Exception as e:
        log(f"Could not write tier file: {e}", "WARN")

# ── STAND DOWN ────────────────────────────────────────────────
def stand_down(reason):
    """
    Write stand-down flag. Hannah reads this at session start and
    refuses to process requests, sending the client to contact VELA support.
    """
    flag_file = os.path.expanduser("~/.openclaw/.vela_standdown")
    try:
        with open(flag_file, "w") as f:
            json.dump({
                "standdown": True,
                "reason": reason,
                "timestamp": datetime.datetime.utcnow().isoformat()
            }, f)
        os.chmod(flag_file, 0o600)
    except Exception as e:
        log(f"Could not write stand-down flag: {e}", "WARN")

    msg = (
        f"⚠️ VELA license inactive.\n\n"
        f"Reason: {reason}\n\n"
        f"Contact greg@gregshindler.com to resolve.\n\n"
        f"System standing down."
    )
    send_telegram(msg)
    log(f"Stand-down issued: {reason}", "WARN")

def clear_stand_down():
    flag_file = os.path.expanduser("~/.openclaw/.vela_standdown")
    if os.path.exists(flag_file):
        os.remove(flag_file)
        log("Stand-down cleared — license active")

# ── MAIN ──────────────────────────────────────────────────────
def main():
    log(f"License check starting for {CLIENT_NAME}")

    # Load key from env file if not injected
    key = VELA_LICENSE_KEY
    if "{{" in key:
        # Try reading from .env
        try:
            with open(ENV_FILE) as f:
                for line in f:
                    if line.startswith("VELA_LICENSE_KEY="):
                        key = line.split("=", 1)[1].strip().strip('"').strip("'")
                        break
        except Exception:
            pass

    if not key or "{{" in key:
        log("No license key found", "ERROR")
        stand_down("No license key configured")
        sys.exit(1)

    state = load_state()

    # Try to validate against server
    try:
        result = validate_license(key)
        status = result.get("status", "invalid")
        tier   = result.get("tier", "command")
        msg    = result.get("message", "")

        log(f"Server response: status={status} tier={tier}")

        if status == "active":
            state["last_valid"] = datetime.datetime.utcnow().isoformat()
            state["last_status"] = "active"
            state["tier"] = tier
            save_state(state)
            write_tier_env(tier)
            clear_stand_down()
            log(f"License ACTIVE — tier: {tier}")
            return 0

        elif status == "revoked":
            save_state({**state, "last_status": "revoked"})
            stand_down("License revoked")
            sys.exit(2)

        elif status == "expired":
            save_state({**state, "last_status": "expired"})
            stand_down("License expired — contact greg@gregshindler.com to renew")
            sys.exit(2)

        else:
            save_state({**state, "last_status": "invalid"})
            stand_down(f"Invalid license key: {msg}")
            sys.exit(2)

    except (urllib.error.URLError, urllib.error.HTTPError, TimeoutError, OSError) as e:
        # Network failure — check grace period
        log(f"License server unreachable: {e}", "WARN")

        last_valid_str = state.get("last_valid")
        if last_valid_str:
            last_valid = datetime.datetime.fromisoformat(last_valid_str)
            hours_since = (datetime.datetime.utcnow() - last_valid).total_seconds() / 3600
            log(f"Hours since last valid check: {hours_since:.1f} (grace: {GRACE_PERIOD_HOURS}h)")

            if hours_since < GRACE_PERIOD_HOURS:
                tier = state.get("tier", "command")
                write_tier_env(tier)
                log(f"Within grace period — continuing with tier: {tier}")
                return 0
            else:
                stand_down(f"License server unreachable for {hours_since:.0f} hours (grace period exceeded)")
                sys.exit(2)
        else:
            # No prior valid check on record — first install on unreachable server
            # Allow 24h from install date
            install_date_str = None
            try:
                with open(CLIENT_CONF) as f:
                    for line in f:
                        if "VELA_INSTALL_DATE" in line:
                            install_date_str = line.split("=", 1)[1].strip().strip('"')
                            break
            except Exception:
                pass

            if install_date_str:
                install_date = datetime.datetime.fromisoformat(install_date_str.replace("Z",""))
                hours_since_install = (datetime.datetime.utcnow() - install_date).total_seconds() / 3600
                if hours_since_install < GRACE_PERIOD_HOURS:
                    log(f"New install, server unreachable — 24h install grace period active ({hours_since_install:.1f}h elapsed)")
                    write_tier_env("command")
                    return 0

            stand_down("License server unreachable and no prior validation on record")
            sys.exit(2)

if __name__ == "__main__":
    sys.exit(main() or 0)
