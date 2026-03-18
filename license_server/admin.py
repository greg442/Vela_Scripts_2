#!/usr/bin/env python3
"""
VELA Admin CLI
--------------
Your command-line tool for managing all VELA client licenses.

Usage:
  python3 admin.py list                          # All clients + status
  python3 admin.py list --stale 48               # Clients with no ping in 48h
  python3 admin.py status CLIENT_ID              # One client detail
  python3 admin.py suspend CLIENT_ID             # Kill switch — immediate
  python3 admin.py reinstate CLIENT_ID           # Bring back online
  python3 admin.py upgrade CLIENT_ID --tier command
  python3 admin.py add CLIENT_ID                 # Create new license key
  python3 admin.py audit CLIENT_ID               # Show change history
  python3 admin.py ping-report                   # Who hasn't checked in

Config:
  Set VELA_ADMIN_KEY and VELA_SERVER_URL as env vars
  or create ~/.vela_admin.conf:
    VELA_SERVER_URL=https://license.vela.run
    VELA_ADMIN_KEY=your-secret-admin-key
"""

import os
import sys
import json
import secrets
import string
import hashlib
import argparse
import datetime
import urllib.request
import urllib.error

# ── CONFIG ────────────────────────────────────────────────────
CONF_FILE = os.path.expanduser("~/.vela_admin.conf")

def load_conf():
    conf = {}
    if os.path.exists(CONF_FILE):
        with open(CONF_FILE) as f:
            for line in f:
                line = line.strip()
                if "=" in line and not line.startswith("#"):
                    k, v = line.split("=", 1)
                    conf[k.strip()] = v.strip().strip('"').strip("'")
    return conf

conf = load_conf()
SERVER_URL = os.environ.get("VELA_SERVER_URL", conf.get("VELA_SERVER_URL", "https://license.vela.run"))
ADMIN_KEY  = os.environ.get("VELA_ADMIN_KEY",  conf.get("VELA_ADMIN_KEY", ""))

# ── COLORS ────────────────────────────────────────────────────
GOLD   = '\033[0;33m'
GREEN  = '\033[0;32m'
RED    = '\033[0;31m'
BLUE   = '\033[0;34m'
GRAY   = '\033[0;90m'
BOLD   = '\033[1m'
RESET  = '\033[0m'

def ok(s):    print(f"{GREEN}✓{RESET} {s}")
def err(s):   print(f"{RED}✗{RESET} {s}"); sys.exit(1)
def warn(s):  print(f"{GOLD}⚠{RESET}  {s}")
def info(s):  print(f"{BLUE}▸{RESET} {s}")
def hr():     print(f"{GRAY}{'─'*60}{RESET}")

# ── HTTP ──────────────────────────────────────────────────────
def api(method, path, body=None):
    if not ADMIN_KEY:
        err("VELA_ADMIN_KEY not set. Add to ~/.vela_admin.conf or set as env var.")

    url = f"{SERVER_URL}{path}"
    data = json.dumps(body).encode() if body else None
    req = urllib.request.Request(
        url, data=data, method=method,
        headers={
            "Content-Type": "application/json",
            "X-Admin-Key": ADMIN_KEY,
        }
    )
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            return json.loads(resp.read().decode())
    except urllib.error.HTTPError as e:
        body_text = e.read().decode()
        err(f"HTTP {e.code}: {body_text}")
    except urllib.error.URLError as e:
        err(f"Cannot reach license server: {e.reason}\n  Is it running? Check {SERVER_URL}/health")

# ── KEY GENERATION ────────────────────────────────────────────
def generate_key():
    """Generate VELA-XXXX-XXXX-XXXX-XXXX format key."""
    chars = string.ascii_uppercase + string.digits
    parts = [''.join(secrets.choice(chars) for _ in range(4)) for _ in range(4)]
    return "VELA-" + "-".join(parts)

def hash_key(key):
    return hashlib.sha256(key.encode()).hexdigest()

# ── FORMATTING ────────────────────────────────────────────────
def fmt_ping(last_ping):
    if not last_ping:
        return f"{RED}never{RESET}"
    try:
        dt = datetime.datetime.fromisoformat(last_ping.replace("Z",""))
        hours = (datetime.datetime.utcnow() - dt).total_seconds() / 3600
        if hours < 25:
            return f"{GREEN}{int(hours)}h ago{RESET}"
        elif hours < 72:
            return f"{GOLD}{int(hours)}h ago{RESET}"
        else:
            return f"{RED}{int(hours/24)}d ago{RESET}"
    except Exception:
        return last_ping

def fmt_status(status):
    colors = {"active": GREEN, "suspended": GOLD, "revoked": RED, "expired": RED}
    c = colors.get(status, GRAY)
    return f"{c}{BOLD}{status}{RESET}"

def fmt_tier(tier):
    return f"{GOLD}{tier}{RESET}" if tier == "command" else f"{GRAY}{tier}{RESET}"

# ── COMMANDS ──────────────────────────────────────────────────
def cmd_list(args):
    clients = api("GET", "/clients")
    if not clients:
        info("No clients found.")
        return

    stale_hours = getattr(args, 'stale', None)

    hr()
    print(f"  {BOLD}{'CLIENT ID':25} {'STATUS':12} {'TIER':10} {'LAST PING':15} {'PINGS':8} {'EXPIRY'}{RESET}")
    hr()

    shown = 0
    for c in clients:
        last_ping = c.get("last_ping", "")

        if stale_hours:
            if last_ping:
                try:
                    dt = datetime.datetime.fromisoformat(last_ping.replace("Z",""))
                    hours = (datetime.datetime.utcnow() - dt).total_seconds() / 3600
                    if hours < stale_hours:
                        continue
                except Exception:
                    pass
            # No ping at all counts as stale

        print(f"  {c['client_id']:25} {fmt_status(c['status']):20} {fmt_tier(c['tier']):18} {fmt_ping(last_ping):25} {c.get('ping_count',0):<8} {c.get('expiry') or '—'}")
        shown += 1

    hr()
    print(f"  {GRAY}{shown} client(s){RESET}")
    print()


def cmd_status(args):
    clients = api("GET", "/clients")
    match = [c for c in clients if c["client_id"] == args.client_id]
    if not match:
        err(f"Client not found: {args.client_id}")

    c = match[0]
    hr()
    print(f"  {BOLD}{c['client_id']}{RESET}")
    hr()
    print(f"  Status      {fmt_status(c['status'])}")
    print(f"  Tier        {fmt_tier(c['tier'])}")
    print(f"  Last ping   {fmt_ping(c.get('last_ping'))}")
    print(f"  Ping count  {c.get('ping_count', 0)}")
    print(f"  Created     {c.get('created_at', '—')}")
    print(f"  Expiry      {c.get('expiry') or 'none'}")
    if c.get("notes"):
        print(f"  Notes       {GRAY}{c['notes']}{RESET}")
    print()


def cmd_suspend(args):
    client_id = args.client_id
    print(f"\n  {RED}{BOLD}SUSPEND {client_id}{RESET}")
    print(f"  {GRAY}This will stand down their system within one session (~24h max).{RESET}")
    confirm = input(f"\n  Type '{client_id}' to confirm: ")
    if confirm.strip() != client_id:
        print("  Cancelled.")
        return

    result = api("POST", f"/suspend/{client_id}")
    if result.get("ok"):
        ok(f"Suspended: {client_id}")
        print(f"  {GRAY}Hannah will stand down at next session start or within 24h.{RESET}")
    else:
        err(result.get("message", "Unknown error"))


def cmd_reinstate(args):
    result = api("POST", f"/reinstate/{args.client_id}")
    if result.get("ok"):
        ok(f"Reinstated: {args.client_id} — system will resume at next license check")
    else:
        err(result.get("message", "Unknown error"))


def cmd_upgrade(args):
    result = api("POST", f"/upgrade/{args.client_id}", {"tier": args.tier})
    if result.get("ok"):
        ok(f"Upgraded {args.client_id} → tier: {args.tier}")
        print(f"  {GRAY}New capabilities load at client's next session start.{RESET}")
    else:
        err(result.get("message", "Unknown error"))


def cmd_add(args):
    """
    Generate a new license key for a client.
    Since this writes directly to the DB (not via API for security),
    you run this on the server itself, or via SSH.
    This prints the SQL to run.
    """
    client_id = args.client_id
    tier = getattr(args, 'tier', 'command')
    expiry = getattr(args, 'expiry', None)
    key = generate_key()
    key_hash = hash_key(key)

    print()
    hr()
    print(f"  {BOLD}New License Key for: {client_id}{RESET}")
    hr()
    print(f"\n  {GOLD}{BOLD}License Key:{RESET}")
    print(f"  {BOLD}{key}{RESET}")
    print(f"\n  {GRAY}(Send this to the client — it is not stored anywhere after this screen){RESET}")
    print()
    print(f"  {GOLD}Run this SQL on the license server:{RESET}")
    print()

    expiry_val = f"'{expiry}'" if expiry else "NULL"
    sql = (
        f"INSERT INTO licenses (client_id, key_hash, status, tier, expiry) "
        f"VALUES ('{client_id}', '{key_hash}', 'active', '{tier}', {expiry_val});"
    )
    print(f"  {BLUE}{sql}{RESET}")
    print()
    print(f"  {GRAY}Or via SSH: ssh root@your-droplet 'sqlite3 /opt/vela/licenses.db \"{sql}\"'{RESET}")
    print()
    hr()

    # Update deploy manifest
    manifest_path = os.path.expanduser("~/.vela_keys.log")
    with open(manifest_path, "a") as f:
        f.write(f"{datetime.datetime.utcnow().isoformat()} | {client_id} | {tier} | {key}\n")
    print(f"  {GRAY}Key logged to: {manifest_path}{RESET}")
    print(f"  {RED}⚠️  Protect this file — it contains plaintext keys.{RESET}")
    print()


def cmd_audit(args):
    # Audit log is DB-side — print guidance to query it
    print()
    print(f"  {BOLD}Audit log for: {args.client_id}{RESET}")
    print(f"  {GRAY}Query directly on the server:{RESET}")
    print()
    sql = f"SELECT * FROM audit_log WHERE client_id = '{args.client_id}' ORDER BY timestamp DESC LIMIT 50;"
    print(f"  {BLUE}sqlite3 /opt/vela/licenses.db \"{sql}\"{RESET}")
    print()


def cmd_ping_report(args):
    clients = api("GET", "/clients")
    silent = [c for c in clients if not c.get("last_ping") and c["status"] == "active"]
    stale  = []
    for c in clients:
        lp = c.get("last_ping")
        if lp and c["status"] == "active":
            try:
                dt = datetime.datetime.fromisoformat(lp.replace("Z",""))
                hours = (datetime.datetime.utcnow() - dt).total_seconds() / 3600
                if hours > 25:
                    stale.append((c, hours))
            except Exception:
                pass

    print()
    if silent:
        print(f"  {RED}{BOLD}Never pinged ({len(silent)}):{RESET}")
        for c in silent:
            print(f"  {RED}  {c['client_id']}{RESET}")
        print()

    if stale:
        print(f"  {GOLD}{BOLD}Stale — no ping in >25h ({len(stale)}):{RESET}")
        for c, hours in sorted(stale, key=lambda x: -x[1]):
            print(f"  {GOLD}  {c[0]['client_id']:30}{RESET} last seen {int(hours)}h ago")
        print()

    if not silent and not stale:
        ok("All active clients have pinged in the last 25 hours")

    print()

# ── MAIN ──────────────────────────────────────────────────────
def main():
    parser = argparse.ArgumentParser(
        prog="admin.py",
        description="VELA License Admin CLI"
    )
    sub = parser.add_subparsers(dest="command")

    # list
    p_list = sub.add_parser("list", help="List all clients")
    p_list.add_argument("--stale", type=int, help="Show only clients with no ping in N hours")

    # status
    p_status = sub.add_parser("status", help="Show one client's details")
    p_status.add_argument("client_id")

    # suspend
    p_suspend = sub.add_parser("suspend", help="Kill switch — suspend a client")
    p_suspend.add_argument("client_id")

    # reinstate
    p_reinstate = sub.add_parser("reinstate", help="Reinstate a suspended client")
    p_reinstate.add_argument("client_id")

    # upgrade
    p_upgrade = sub.add_parser("upgrade", help="Change client tier")
    p_upgrade.add_argument("client_id")
    p_upgrade.add_argument("--tier", choices=["command", "standard"], default="command")

    # add
    p_add = sub.add_parser("add", help="Generate a new license key")
    p_add.add_argument("client_id")
    p_add.add_argument("--tier", choices=["command", "standard"], default="command")
    p_add.add_argument("--expiry", help="Expiry date ISO format e.g. 2027-01-01")

    # audit
    p_audit = sub.add_parser("audit", help="Show change history for a client")
    p_audit.add_argument("client_id")

    # ping-report
    sub.add_parser("ping-report", help="Show clients who haven't checked in recently")

    args = parser.parse_args()

    commands = {
        "list":        cmd_list,
        "status":      cmd_status,
        "suspend":     cmd_suspend,
        "reinstate":   cmd_reinstate,
        "upgrade":     cmd_upgrade,
        "add":         cmd_add,
        "audit":       cmd_audit,
        "ping-report": cmd_ping_report,
    }

    if args.command in commands:
        print()
        commands[args.command](args)
    else:
        parser.print_help()

if __name__ == "__main__":
    main()
