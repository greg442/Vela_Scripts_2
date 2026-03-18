#!/usr/bin/env python3
"""
momentum.py — Hannah's Intelligence Trend Engine.
Analyzes signals table over a configurable window.

Usage:
    python3 momentum.py [--days N] [--output text|json] [--entity ENTITY_ID]
"""

import sys, os, sqlite3, json
from datetime import datetime, timezone, timedelta

DB_PATH = os.path.expanduser("~/.openclaw/hannah.db")

def get_conn():
    if not os.path.exists(DB_PATH):
        print(f"ERROR: Database not found at {DB_PATH}")
        print("Run: python3 intelligence.py init")
        sys.exit(1)
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn

def now_iso():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

def window_start(days):
    dt = datetime.now(timezone.utc) - timedelta(days=days)
    return dt.strftime("%Y-%m-%dT%H:%M:%SZ")

def hot_entities(conn, since, limit=5):
    sql = """
        SELECT e.id, e.name, e.type, e.status,
            COUNT(s.id) AS signal_count,
            AVG(s.ium_score) AS avg_ium,
            MAX(s.ium_score) AS peak_ium,
            MAX(s.ts) AS last_signal,
            GROUP_CONCAT(DISTINCT s.signal_type) AS signal_types
        FROM signals s
        JOIN entities e ON s.entity_id = e.id
        WHERE s.ts >= ? AND s.ium_score IS NOT NULL
        GROUP BY s.entity_id
        ORDER BY avg_ium DESC, signal_count DESC
        LIMIT ?"""
    return conn.execute(sql, (since, limit)).fetchall()

def rising_risks(conn, since):
    sql = """
        SELECT s.id, s.ts, s.summary, s.ium_score, s.action_taken,
            e.name AS entity_name, e.type AS entity_type
        FROM signals s
        LEFT JOIN entities e ON s.entity_id = e.id
        WHERE s.ts >= ? AND s.signal_type = 'risk'
        ORDER BY s.ium_score DESC, s.ts DESC LIMIT 10"""
    return conn.execute(sql, (since,)).fetchall()

def stalled_priorities(conn, since):
    sql = """
        SELECT p.rank, p.objective, p.next_action, p.owner,
            p.urgency, p.momentum, p.deadline, e.name AS entity_name,
            COALESCE(MAX(s.ts), 'never') AS last_signal
        FROM priorities p
        LEFT JOIN entities e ON p.entity_id = e.id
        LEFT JOIN signals s ON s.entity_id = p.entity_id AND s.ts >= ?
        GROUP BY p.rank
        HAVING last_signal = 'never' OR MAX(s.ts) IS NULL
        ORDER BY p.rank ASC LIMIT 10"""
    return conn.execute(sql, (since,)).fetchall()

def signal_volume(conn, since):
    sql = """
        SELECT signal_type, COUNT(*) AS count, AVG(ium_score) AS avg_ium
        FROM signals WHERE ts >= ?
        GROUP BY signal_type ORDER BY count DESC"""
    return conn.execute(sql, (since,)).fetchall()

def opportunities_in_window(conn, since):
    sql = """
        SELECT s.ts, s.summary, s.ium_score, e.name AS entity_name
        FROM signals s
        LEFT JOIN entities e ON s.entity_id = e.id
        WHERE s.ts >= ? AND s.signal_type = 'opportunity'
        ORDER BY s.ium_score DESC, s.ts DESC LIMIT 5"""
    return conn.execute(sql, (since,)).fetchall()

def entity_timeline(conn, entity_id, days=30):
    since = window_start(days)
    sql = """
        SELECT s.ts, s.signal_type, s.ium_score, s.source, s.summary, s.action_taken
        FROM signals s
        WHERE s.entity_id = ? AND s.ts >= ?
        ORDER BY s.ts DESC"""
    return conn.execute(sql, (entity_id, since)).fetchall()

def total_signal_count(conn, since):
    row = conn.execute("SELECT COUNT(*) AS c FROM signals WHERE ts >= ?", (since,)).fetchone()
    return row["c"] if row else 0

def open_decisions(conn):
    return conn.execute(
        "SELECT id, ts, title, revisit_date FROM decisions WHERE status = 'active' ORDER BY ts DESC LIMIT 10"
    ).fetchall()

def format_text(report):
    lines = []
    days = report["window_days"]
    generated = report["generated"]
    lines.append(f"=======================================")
    lines.append(f"  MOMENTUM REPORT — {generated[:10]}")
    lines.append(f"  Window: last {days} days")
    lines.append(f"  Signals analyzed: {report['total_signals']}")
    lines.append(f"=======================================\n")

    lines.append("HOT ENTITIES")
    if report["hot_entities"]:
        for e in report["hot_entities"]:
            lines.append(f"  [{e['avg_ium']:.1f} avg IUM | {e['signal_count']} signals] {e['name']} ({e['type']}) — last: {e['last_signal'][:10]}")
    else:
        lines.append("  No entity signal activity in window.")
    lines.append("")

    lines.append("OPPORTUNITIES")
    if report["opportunities"]:
        for o in report["opportunities"]:
            entity = f" [{o['entity_name']}]" if o["entity_name"] else ""
            lines.append(f"  IUM {o['ium_score']:>2}  {o['ts'][:10]}{entity}")
            lines.append(f"    {o['summary']}")
    else:
        lines.append("  No opportunity signals in window.")
    lines.append("")

    lines.append("RISING RISKS")
    if report["rising_risks"]:
        for r in report["rising_risks"]:
            entity = f" [{r['entity_name']}]" if r["entity_name"] else ""
            lines.append(f"  IUM {r['ium_score']:>2}  {r['ts'][:10]}{entity}")
            lines.append(f"    {r['summary']}")
            if r["action_taken"]:
                lines.append(f"    -> Action: {r['action_taken']}")
    else:
        lines.append("  No risk signals in window.")
    lines.append("")

    lines.append("STALLED PRIORITIES (no signal in window)")
    if report["stalled_priorities"]:
        for p in report["stalled_priorities"]:
            entity = f" — {p['entity_name']}" if p["entity_name"] else ""
            lines.append(f"  #{p['rank']} [{p['urgency']}]{entity}: {p['objective']}")
            if p["next_action"]:
                lines.append(f"    Next: {p['next_action']}")
    else:
        lines.append("  All priorities have recent signal activity.")
    lines.append("")

    lines.append("OPEN DECISIONS")
    if report["open_decisions"]:
        for d in report["open_decisions"]:
            revisit = f" (revisit: {d['revisit_date']})" if d["revisit_date"] else ""
            lines.append(f"  [{d['ts'][:10]}] {d['title']}{revisit}")
    else:
        lines.append("  No open decisions.")
    lines.append("")

    lines.append("SIGNAL VOLUME BY TYPE")
    if report["signal_volume"]:
        for sv in report["signal_volume"]:
            avg = f"{sv['avg_ium']:.1f}" if sv["avg_ium"] else "n/a"
            lines.append(f"  {sv['signal_type']:15s}  {sv['count']:>3} signals  avg IUM: {avg}")
    else:
        lines.append("  No signals logged in window.")
    lines.append("\n=======================================")
    return "\n".join(lines)

def main():
    args = sys.argv[1:]
    days = 7
    output_format = "text"
    entity_id = None
    i = 0
    while i < len(args):
        if args[i] == "--days":
            i += 1; days = int(args[i]) if i < len(args) else 7
        elif args[i] == "--output":
            i += 1; output_format = args[i] if i < len(args) else "text"
        elif args[i] == "--entity":
            i += 1; entity_id = args[i] if i < len(args) else None
        i += 1

    since = window_start(days)
    conn = get_conn()

    if entity_id:
        rows = entity_timeline(conn, entity_id, days)
        conn.close()
        if not rows:
            print(f"No signals found for '{entity_id}' in last {days} days.")
            return
        print(f"Signal timeline for '{entity_id}' — last {days} days:\n")
        for r in rows:
            print(f"  [{r['ts'][:10]}] {r['signal_type']} (IUM {r['ium_score']}) via {r['source']}")
            print(f"    {r['summary']}")
            if r["action_taken"]:
                print(f"    -> {r['action_taken']}")
            print()
        return

    report = {
        "generated":          now_iso(),
        "window_days":        days,
        "total_signals":      total_signal_count(conn, since),
        "hot_entities":       [dict(r) for r in hot_entities(conn, since)],
        "opportunities":      [dict(r) for r in opportunities_in_window(conn, since)],
        "rising_risks":       [dict(r) for r in rising_risks(conn, since)],
        "stalled_priorities": [dict(r) for r in stalled_priorities(conn, since)],
        "open_decisions":     [dict(r) for r in open_decisions(conn)],
        "signal_volume":      [dict(r) for r in signal_volume(conn, since)],
    }
    conn.close()

    if output_format == "json":
        print(json.dumps(report, indent=2))
    else:
        print(format_text(report))

if __name__ == "__main__":
    main()
