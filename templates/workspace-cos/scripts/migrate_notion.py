#!/usr/bin/env python3
"""
migrate_notion.py — One-time migration from Notion to hannah.db (SQLite).
Non-destructive. Idempotent — safe to re-run.

Usage:
    python3 migrate_notion.py [--dry-run] [--db rel|deal|dec|world|all]
"""

import sys, os, sqlite3, subprocess
from datetime import datetime, timezone

DB_PATH = os.path.expanduser("~/.openclaw/hannah.db")
NOTION_TOOL = os.path.expanduser("~/.openclaw/workspace-cos/scripts/notion_tool.py")

def log(msg): print(f"[{datetime.now().strftime('%H:%M:%S')}] {msg}")
def now_iso(): return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

def get_conn():
    if not os.path.exists(DB_PATH):
        print(f"ERROR: {DB_PATH} not found. Run: python3 intelligence.py init")
        sys.exit(1)
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn

def query_notion(db_alias):
    try:
        result = subprocess.run(
            [sys.executable, NOTION_TOOL, "query", db_alias],
            capture_output=True, text=True, timeout=30)
        if result.returncode != 0:
            log(f"WARNING: notion query {db_alias} failed: {result.stderr[:200]}")
            return []
        return parse_notion_output(result.stdout)
    except Exception as e:
        log(f"WARNING: Could not query Notion {db_alias}: {e}")
        return []

def parse_notion_output(output):
    records = []
    current = {}
    for line in output.splitlines():
        line = line.rstrip()
        if line.startswith("[") and line.endswith("]"):
            if current:
                records.append(current)
            current = {}
        elif line.startswith("  ") and ":" in line:
            key, _, val = line.strip().partition(": ")
            key = key.strip().lower().replace(" ", "_")
            val = val.strip()
            if val:
                current[key] = val
    if current:
        records.append(current)
    return records

def slugify(text):
    import re
    text = text.lower().replace(" ", "-").replace(".", "")
    return re.sub(r"[^a-z0-9\-]", "", text)[:80]

def migrate_rel(conn, records, dry_run):
    log(f"  Migrating {len(records)} relationship records -> entities")
    count = 0
    for r in records:
        name = r.get("name", r.get("page_id", "unknown"))
        slug = slugify(name)
        status = r.get("relationship_status") or r.get("attention_level") or "active"
        context_parts = []
        if r.get("open_thread"): context_parts.append(f"Open thread: {r['open_thread']}")
        if r.get("next_suggested_move"): context_parts.append(f"Next move: {r['next_suggested_move']}")
        if r.get("last_meaningful_contact"): context_parts.append(f"Last contact: {r['last_meaningful_contact']}")
        context = " | ".join(context_parts) if context_parts else None
        tags_parts = []
        if r.get("category"): tags_parts.append(r["category"])
        if r.get("strategic_value"): tags_parts.append(f"sv:{r['strategic_value']}")
        if r.get("attention_level"): tags_parts.append(f"attn:{r['attention_level']}")
        tags = ",".join(tags_parts) if tags_parts else None
        if dry_run:
            print(f"    [DRY RUN] entities: id={slug} name={name} status={status}")
        else:
            conn.execute(
                "INSERT OR IGNORE INTO entities (id, type, name, status, context, tags, last_updated) VALUES (?, 'person', ?, ?, ?, ?, ?)",
                (slug, name, status, context, tags, now_iso()))
        count += 1
    return count

def migrate_deal(conn, records, dry_run):
    log(f"  Migrating {len(records)} deal records -> entities")
    count = 0
    for r in records:
        name = r.get("deal", r.get("name", r.get("page_id", "unknown")))
        slug = slugify(name)
        status = r.get("status", "active").lower()
        context_parts = []
        if r.get("stage"): context_parts.append(f"Stage: {r['stage']}")
        if r.get("next_move"): context_parts.append(f"Next: {r['next_move']}")
        if r.get("hannah_recommendation"): context_parts.append(f"Hannah: {r['hannah_recommendation']}")
        if r.get("risk_signal"): context_parts.append(f"Risk: {r['risk_signal']}")
        if r.get("last_movement"): context_parts.append(f"Last moved: {r['last_movement']}")
        context = " | ".join(context_parts) if context_parts else None
        tags_parts = []
        if r.get("deal_type"): tags_parts.append(r["deal_type"])
        if r.get("strategic_value"): tags_parts.append(f"sv:{r['strategic_value']}")
        if r.get("owner"): tags_parts.append(f"owner:{r['owner']}")
        tags = ",".join(tags_parts) if tags_parts else None
        if dry_run:
            print(f"    [DRY RUN] entities: id={slug} name={name} type=deal status={status}")
        else:
            conn.execute(
                "INSERT OR IGNORE INTO entities (id, type, name, status, context, tags, last_updated) VALUES (?, 'deal', ?, ?, ?, ?, ?)",
                (slug, name, status, context, tags, now_iso()))
        count += 1
    return count

def migrate_dec(conn, records, dry_run):
    log(f"  Migrating {len(records)} decision records -> decisions")
    count = 0
    for r in records:
        title = r.get("decision", r.get("name", r.get("page_id", "unknown")))
        ts = r.get("date") or now_iso()
        if len(ts) == 10: ts = ts + "T00:00:00Z"
        status_map = {"pending": "active", "decided": "resolved", "active": "active", "resolved": "resolved", "reversed": "reversed"}
        status = status_map.get(r.get("decision_status", "active").lower(), "active")
        if dry_run:
            print(f"    [DRY RUN] decisions: title={title} ts={ts} status={status}")
        else:
            conn.execute(
                "INSERT OR IGNORE INTO decisions (ts, title, context, assumptions, revisit_date, status) VALUES (?, ?, ?, ?, ?, ?)",
                (ts, title, r.get("context"), r.get("assumptions"), r.get("revisit_date"), status))
        count += 1
    return count

def migrate_world(conn, records, dry_run):
    log(f"  Migrating {len(records)} world state records -> priorities")
    count = 0
    rank = 1
    urgency_map = {"now": "now", "soon": "soon", "later": "normal", "someday": "someday"}
    momentum_map = {"rising": "rising", "steady": "steady", "stalling": "stalling", "blocked": "blocked"}
    for r in records:
        objective = r.get("item", r.get("name", r.get("page_id", "unknown")))
        urgency = urgency_map.get(r.get("priority", "normal").lower(), "normal")
        momentum = momentum_map.get(r.get("momentum", "steady").lower(), "steady")
        owner = r.get("owner", "Greg")
        if dry_run:
            print(f"    [DRY RUN] priorities: rank={rank} objective={objective} urgency={urgency}")
        else:
            conn.execute(
                "INSERT OR IGNORE INTO priorities (rank, objective, next_action, owner, urgency, momentum, updated) VALUES (?, ?, ?, ?, ?, ?, ?)",
                (rank, objective, r.get("next_action"), owner, urgency, momentum, now_iso()))
        rank += 1
        count += 1
    return count

MIGRATIONS = {
    "rel":   ("Relationship Intelligence", migrate_rel),
    "deal":  ("Deal Flow",                 migrate_deal),
    "dec":   ("Decision Log",              migrate_dec),
    "world": ("World State",               migrate_world),
}

def main():
    args = sys.argv[1:]
    dry_run = "--dry-run" in args
    target_db = None
    for i, arg in enumerate(args):
        if arg == "--db" and i + 1 < len(args):
            target_db = args[i + 1]
    if dry_run:
        log("DRY RUN — no changes will be written")
    dbs_to_migrate = {target_db: MIGRATIONS[target_db]} if target_db and target_db in MIGRATIONS else MIGRATIONS
    conn = get_conn() if not dry_run else None
    total = 0
    for alias, (label, handler) in dbs_to_migrate.items():
        log(f"Querying Notion: {label} ({alias})")
        records = query_notion(alias)
        if not records:
            log(f"  No records returned from Notion for {alias} — skipping")
            continue
        if not dry_run:
            with conn:
                count = handler(conn, records, dry_run=False)
        else:
            count = handler(None, records, dry_run=True)
        log(f"  -> {count} records processed")
        total += count
    if conn:
        conn.close()
    log(f"Migration complete. Total records processed: {total}")
    if not dry_run:
        log(f"Database: {DB_PATH}")
        log("Notion remains live — verify SQLite data before cutting over")

if __name__ == "__main__":
    main()
