#!/usr/bin/env python3
"""
intelligence.py — Hannah's SQLite Intelligence Layer.

Replaces notion_tool.py. Same CLI interface. No network required.

Usage:
    python3 intelligence.py <command> <database> [options]

Commands:
    query       Query/list entries (with optional filters)
    get         Get a single entry by ID
    create      Create a new entry
    update      Update an existing entry by ID
    schema      Show database schema/properties
    init        Initialize the database (run once)

Databases (aliases):
    relationships | rel      Relationship Intelligence
    decisions     | dec      Decision Log
    dealflow      | deal     Deal Flow
    worldstate    | world    World State (priorities)
    signals       | event    Signal / Event Log
    priorities    | pri      Current Priority Stack
    memory        | mem      Persistent Facts and Corrections

Database location: ~/.openclaw/hannah.db

Examples:
    python3 intelligence.py query rel --filter "status=Strong"
    python3 intelligence.py create rel --props 'name=Paul Soanes' 'status=Strong' 'type=Investor'
    python3 intelligence.py update deal --id 3 --props 'status=Closing' 'next_action=Send term sheet'
    python3 intelligence.py query world --filter "priority=Now"
    python3 intelligence.py schema rel
    python3 intelligence.py init
"""

import sys, os, sqlite3, json, re
from datetime import datetime, timezone

DB_PATH = os.path.expanduser("~/.openclaw/hannah.db")

SCHEMAS = {
    "entities": {
        "description": "People, deals, companies, projects",
        "aliases": ["relationships", "rel", "dealflow", "deal"],
        "columns": {
            "id":           ("TEXT PRIMARY KEY", "Unique slug: paul-soanes, colel-palmilla"),
            "type":         ("TEXT",             "person | deal | company | project"),
            "name":         ("TEXT NOT NULL",    "Display name"),
            "status":       ("TEXT",             "active | dormant | closed | watching | strong | warm | cold"),
            "priority":     ("INTEGER DEFAULT 3","1=critical 2=high 3=normal 4=low 5=someday"),
            "context":      ("TEXT",             "Free-form notes"),
            "tags":         ("TEXT",             "Comma-separated tags"),
            "last_updated": ("TEXT",             "ISO timestamp"),
        }
    },
    "signals": {
        "description": "Every signal Hannah evaluates — the Event Log",
        "aliases": ["signals", "event", "eventlog"],
        "columns": {
            "id":           ("INTEGER PRIMARY KEY AUTOINCREMENT", "Auto ID"),
            "ts":           ("TEXT NOT NULL",    "ISO timestamp"),
            "source":       ("TEXT",             "email | telegram | cron | manual | notion"),
            "entity_id":    ("TEXT",             "FK → entities.id (nullable)"),
            "signal_type":  ("TEXT",             "momentum | risk | opportunity | pattern | noise"),
            "ium_score":    ("INTEGER",          "1-10: Importance x Urgency x Momentum"),
            "summary":      ("TEXT",             "What happened"),
            "action_taken": ("TEXT",             "What Hannah did with it"),
        }
    },
    "decisions": {
        "description": "Strategic decisions with full context",
        "aliases": ["decisions", "dec"],
        "columns": {
            "id":           ("INTEGER PRIMARY KEY AUTOINCREMENT", "Auto ID"),
            "ts":           ("TEXT NOT NULL",    "ISO timestamp"),
            "title":        ("TEXT NOT NULL",    "Decision title"),
            "context":      ("TEXT",             "Background and situation"),
            "decision":     ("TEXT",             "What was decided"),
            "rationale":    ("TEXT",             "Why"),
            "assumptions":  ("TEXT",             "Key assumptions"),
            "revisit_date": ("TEXT",             "ISO date to revisit"),
            "outcome":      ("TEXT",             "Filled in later"),
            "status":       ("TEXT DEFAULT 'active'", "active | resolved | reversed"),
            "entity_id":    ("TEXT",             "FK → entities.id (nullable)"),
        }
    },
    "priorities": {
        "description": "Current priority stack — replaces LIVE_PRIORITY_MAP.md",
        "aliases": ["priorities", "pri", "worldstate", "world"],
        "pk": "rank",
        "columns": {
            "rank":         ("INTEGER PRIMARY KEY", "1 = most important"),
            "entity_id":    ("TEXT",             "FK → entities.id"),
            "objective":    ("TEXT NOT NULL",    "What we're trying to accomplish"),
            "next_action":  ("TEXT",             "Immediate next step"),
            "owner":        ("TEXT DEFAULT 'Greg'", "Who is responsible"),
            "deadline":     ("TEXT",             "ISO date"),
            "urgency":      ("TEXT DEFAULT 'normal'", "now | soon | normal | someday"),
            "momentum":     ("TEXT DEFAULT 'steady'", "rising | steady | stalling | blocked"),
            "updated":      ("TEXT",             "ISO timestamp of last change"),
        }
    },
    "memory": {
        "description": "Persistent facts and corrections — survives session resets",
        "aliases": ["memory", "mem"],
        "columns": {
            "id":       ("INTEGER PRIMARY KEY AUTOINCREMENT", "Auto ID"),
            "ts":       ("TEXT NOT NULL",    "ISO timestamp when learned"),
            "category": ("TEXT",             "rule | fact | correction | preference"),
            "key":      ("TEXT NOT NULL",    "Short identifier"),
            "value":    ("TEXT NOT NULL",    "The fact or rule"),
            "source":   ("TEXT",             "Where this came from"),
        }
    },
}

ALIAS_MAP = {}
for table, info in SCHEMAS.items():
    for alias in info["aliases"]:
        ALIAS_MAP[alias.lower()] = table
for table in SCHEMAS:
    ALIAS_MAP[table] = table

def get_conn():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("PRAGMA foreign_keys=ON")
    return conn

def cmd_init():
    os.makedirs(os.path.dirname(DB_PATH), exist_ok=True)
    ddl = {
        "entities": """CREATE TABLE IF NOT EXISTS entities (
                id TEXT PRIMARY KEY, type TEXT, name TEXT NOT NULL,
                status TEXT, priority INTEGER DEFAULT 3,
                context TEXT, tags TEXT, last_updated TEXT)""",
        "signals": """CREATE TABLE IF NOT EXISTS signals (
                id INTEGER PRIMARY KEY AUTOINCREMENT, ts TEXT NOT NULL,
                source TEXT, entity_id TEXT, signal_type TEXT,
                ium_score INTEGER, summary TEXT, action_taken TEXT)""",
        "decisions": """CREATE TABLE IF NOT EXISTS decisions (
                id INTEGER PRIMARY KEY AUTOINCREMENT, ts TEXT NOT NULL,
                title TEXT NOT NULL, context TEXT, decision TEXT,
                rationale TEXT, assumptions TEXT, revisit_date TEXT,
                outcome TEXT, status TEXT DEFAULT 'active', entity_id TEXT)""",
        "priorities": """CREATE TABLE IF NOT EXISTS priorities (
                rank INTEGER PRIMARY KEY, entity_id TEXT,
                objective TEXT NOT NULL, next_action TEXT,
                owner TEXT DEFAULT 'Greg', deadline TEXT,
                urgency TEXT DEFAULT 'normal', momentum TEXT DEFAULT 'steady',
                updated TEXT)""",
        "memory": """CREATE TABLE IF NOT EXISTS memory (
                id INTEGER PRIMARY KEY AUTOINCREMENT, ts TEXT NOT NULL,
                category TEXT, key TEXT NOT NULL, value TEXT NOT NULL, source TEXT)""",
    }
    indexes = [
        "CREATE INDEX IF NOT EXISTS idx_entities_type     ON entities(type)",
        "CREATE INDEX IF NOT EXISTS idx_entities_status   ON entities(status)",
        "CREATE INDEX IF NOT EXISTS idx_entities_priority ON entities(priority)",
        "CREATE INDEX IF NOT EXISTS idx_signals_ts        ON signals(ts)",
        "CREATE INDEX IF NOT EXISTS idx_signals_entity    ON signals(entity_id)",
        "CREATE INDEX IF NOT EXISTS idx_signals_type      ON signals(signal_type)",
        "CREATE INDEX IF NOT EXISTS idx_decisions_status  ON decisions(status)",
        "CREATE INDEX IF NOT EXISTS idx_priorities_rank   ON priorities(rank)",
        "CREATE INDEX IF NOT EXISTS idx_memory_key        ON memory(key)",
    ]
    conn = get_conn()
    with conn:
        for sql in ddl.values():
            conn.execute(sql)
        for idx in indexes:
            conn.execute(idx)
    conn.close()
    print(f"Database initialized: {DB_PATH}")
    print(f"Tables: {', '.join(ddl.keys())}")

def resolve_table(alias):
    table = ALIAS_MAP.get(alias.lower())
    if not table:
        print(f"ERROR: Unknown database '{alias}'.")
        print(f"Valid: {', '.join(sorted(ALIAS_MAP.keys()))}")
        sys.exit(1)
    return table

def now_iso():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

def format_row(row, table):
    keys = row.keys()
    lines = []
    if "id" in keys:
        lines.append(f"  ID: {row['id']}")
    for name_col in ("name", "title", "objective", "key"):
        if name_col in keys and row[name_col]:
            lines.append(f"  {name_col}: {row[name_col]}")
            break
    for k in keys:
        if k in ("id", "name", "title", "objective", "key"):
            continue
        v = row[k]
        if v is not None and v != "":
            lines.append(f"  {k}: {v}")
    return "\n".join(lines)


def cmd_schema(alias):
    table = resolve_table(alias)
    info = SCHEMAS[table]
    print(f"Table: {table}")
    print(f"Description: {info['description']}")
    print(f"Aliases: {', '.join(info['aliases'])}")
    print("Columns:")
    for col, (col_def, desc) in info["columns"].items():
        print(f"  {col:20s} {col_def:35s} # {desc}")

def cmd_query(alias, filters=None, sort_spec=None, limit=None):
    table = resolve_table(alias)
    conn = get_conn()
    where_clauses = []
    params = []
    if filters:
        for f in filters:
            if "=" not in f:
                continue
            col, _, val = f.partition("=")
            col, val = col.strip().lower(), val.strip()
            where_clauses.append(f"LOWER({col}) LIKE LOWER(?)")
            params.append(f"%{val}%")
    sql = f"SELECT * FROM {table}"
    if where_clauses:
        sql += " WHERE " + " AND ".join(where_clauses)
    if sort_spec:
        col, _, direction = sort_spec.partition(":")
        col = col.strip()
        direction = "DESC" if direction.strip().lower() in ("desc", "descending") else "ASC"
        sql += f" ORDER BY {col} {direction}"
    else:
        defaults = {
            "priorities": "ORDER BY rank ASC",
            "signals":    "ORDER BY ts DESC",
            "decisions":  "ORDER BY ts DESC",
            "entities":   "ORDER BY priority ASC, last_updated DESC",
            "memory":     "ORDER BY ts DESC",
        }
        sql += " " + defaults.get(table, "")
    if limit:
        sql += f" LIMIT {int(limit)}"
    rows = conn.execute(sql, params).fetchall()
    conn.close()
    if not rows:
        print("No results found.")
        return
    print(f"Found {len(rows)} entries:\n")
    for i, row in enumerate(rows):
        print(f"[{i+1}]")
        print(format_row(row, table))
        print()

def cmd_get(alias, record_id):
    table = resolve_table(alias)
    conn = get_conn()
    try:
        int_id = int(record_id)
        row = conn.execute(f"SELECT * FROM {table} WHERE id = ?", (int_id,)).fetchone()
    except ValueError:
        row = conn.execute(f"SELECT * FROM {table} WHERE id = ?", (record_id,)).fetchone()
    conn.close()
    if not row:
        print(f"No entry found with ID '{record_id}' in {table}.")
        return
    print(format_row(row, table))

def cmd_create(alias, prop_pairs):
    table = resolve_table(alias)
    schema_cols = SCHEMAS[table]["columns"]
    props = {}
    for pair in prop_pairs:
        if "=" not in pair:
            continue
        col, _, val = pair.partition("=")
        props[col.strip().lower()] = val.strip()
    if not props:
        print("ERROR: No properties provided.")
        sys.exit(1)
    ts = now_iso()
    if "ts" in schema_cols and "ts" not in props:
        props["ts"] = ts
    if "last_updated" in schema_cols:
        props["last_updated"] = ts
    if "updated" in schema_cols:
        props["updated"] = ts
    if table == "entities" and "id" not in props:
        name = props.get("name", "unknown")
        slug = name.lower().replace(" ", "-").replace(".", "")
        slug = re.sub(r"[^a-z0-9\-]", "", slug)
        props["id"] = slug
    cols = list(props.keys())
    values = [props[c] for c in cols]
    sql = f"INSERT INTO {table} ({', '.join(cols)}) VALUES ({', '.join(['?' for _ in cols])})"
    conn = get_conn()
    try:
        with conn:
            cursor = conn.execute(sql, values)
            record_id = cursor.lastrowid or props.get("id", "?")
        print(f"Created entry in {table}: ID={record_id}")
        row = conn.execute(f"SELECT * FROM {table} WHERE rowid = ?", (cursor.lastrowid,)).fetchone()
        if row:
            print(format_row(row, table))
    except sqlite3.IntegrityError as e:
        print(f"ERROR: {e}")
        sys.exit(1)
    finally:
        conn.close()

def cmd_update(alias, record_id, prop_pairs):
    table = resolve_table(alias)
    schema_cols = SCHEMAS[table]["columns"]
    props = {}
    for pair in prop_pairs:
        if "=" not in pair:
            continue
        col, _, val = pair.partition("=")
        props[col.strip().lower()] = val.strip()
    if not props:
        print("ERROR: No properties provided.")
        sys.exit(1)
    ts = now_iso()
    if "last_updated" in schema_cols:
        props["last_updated"] = ts
    if "updated" in schema_cols:
        props["updated"] = ts
    set_clauses = [f"{col} = ?" for col in props]
    values = list(props.values())
    # priorities table uses rank as PK, not id
    pk_col = "rank" if table == "priorities" else "id"

    try:
        id_val = int(record_id)
    except ValueError:
        id_val = record_id
    values.append(id_val)
    sql = f"UPDATE {table} SET {', '.join(set_clauses)} WHERE {pk_col} = ?"
    conn = get_conn()
    with conn:
        cursor = conn.execute(sql, values)
        if cursor.rowcount == 0:
            print(f"ERROR: No entry found with {pk_col} '{record_id}' in {table}.")
            conn.close()
            sys.exit(1)
        print(f"Updated entry in {table}: {pk_col}={record_id}")
        row = conn.execute(f"SELECT * FROM {table} WHERE {pk_col} = ?", (id_val,)).fetchone()
        if row:
            print(format_row(row, table))
    conn.close()

def cmd_delete(alias, record_id):
    table = resolve_table(alias)
    pk = SCHEMAS[table].get("pk", "id")
    try:
        id_val = int(record_id)
    except ValueError:
        id_val = record_id
    conn = get_conn()
    with conn:
        cursor = conn.execute(f"DELETE FROM {table} WHERE {pk} = ?", (id_val,))
        if cursor.rowcount == 0:
            print(f"ERROR: No entry found with {pk}='{record_id}' in {table}.")
            conn.close()
            sys.exit(1)
        print(f"Deleted entry from {table}: {pk}={record_id}")
    conn.close()

def main():
    args = sys.argv[1:]
    if len(args) < 1:
        print(__doc__)
        sys.exit(0)
    command = args[0].lower()
    if command == "init":
        cmd_init()
        return
    if len(args) < 2:
        print(__doc__)
        sys.exit(0)
    db_alias = args[1]
    rest = args[2:]
    if command == "schema":
        cmd_schema(db_alias)
    elif command == "query":
        filters, sort_spec, limit = [], None, None
        i = 0
        while i < len(rest):
            if rest[i] == "--filter":
                i += 1
                while i < len(rest) and not rest[i].startswith("--"):
                    filters.append(rest[i]); i += 1
            elif rest[i] == "--sort":
                i += 1; sort_spec = rest[i] if i < len(rest) else None; i += 1
            elif rest[i] == "--limit":
                i += 1; limit = rest[i] if i < len(rest) else None; i += 1
            else:
                filters.append(rest[i]); i += 1
        cmd_query(db_alias, filters or None, sort_spec, limit)
    elif command == "get":
        if not rest:
            print("ERROR: get requires an ID"); sys.exit(1)
        cmd_get(db_alias, rest[0])
    elif command == "create":
        props = []; i = 0
        while i < len(rest):
            if rest[i] == "--props":
                i += 1
                while i < len(rest) and not rest[i].startswith("--"):
                    props.append(rest[i]); i += 1
            else:
                props.append(rest[i]); i += 1
        if not props:
            print("ERROR: create requires --props"); sys.exit(1)
        cmd_create(db_alias, props)
    elif command == "update":
        record_id = None; props = []; i = 0
        while i < len(rest):
            if rest[i] == "--id":
                i += 1; record_id = rest[i] if i < len(rest) else None; i += 1
            elif rest[i] == "--page-id":
                i += 1; record_id = rest[i] if i < len(rest) else None; i += 1
            elif rest[i] == "--props":
                i += 1
                while i < len(rest) and not rest[i].startswith("--"):
                    props.append(rest[i]); i += 1
            else:
                props.append(rest[i]); i += 1
        if not record_id:
            print("ERROR: update requires --id"); sys.exit(1)
        if not props:
            print("ERROR: update requires --props"); sys.exit(1)
        cmd_update(db_alias, record_id, props)
    elif command == "delete":
        record_id = None; i = 0
        while i < len(rest):
            if rest[i] == "--id":
                i += 1; record_id = rest[i] if i < len(rest) else None; i += 1
            else:
                i += 1
        if not record_id:
            print("ERROR: delete requires --id"); sys.exit(1)
        cmd_delete(db_alias, record_id)
    else:
        print(f"ERROR: Unknown command '{command}'")
        sys.exit(1)

if __name__ == "__main__":
    main()
