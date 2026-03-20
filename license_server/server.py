#!/usr/bin/env python3
"""
VELA License Server
-------------------
Runs on your $5 DigitalOcean droplet.
Validates license keys, enforces tiers, logs heartbeats.

Deploy:
  pip install flask gunicorn
  gunicorn -w 2 -b 0.0.0.0:8080 server:app

Nginx reverse proxy recommended (see docs/ADMIN.md).
"""

import os
import json
import secrets
import hashlib
import datetime
from flask import Flask, request, jsonify
import sqlite3

app = Flask(__name__)

DB_PATH = os.environ.get("VELA_DB", "/opt/vela/licenses.db")

# ── DB ────────────────────────────────────────────────────────
def get_db():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn

# ── HELPERS ───────────────────────────────────────────────────
def hash_key(key: str) -> str:
    """Store hashed keys — never plaintext."""
    return hashlib.sha256(key.encode()).hexdigest()

def now_iso():
    return datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ")

# ── ROUTES ────────────────────────────────────────────────────

@app.route("/health", methods=["GET"])
def health():
    return jsonify({"status": "ok", "service": "vela-license-server"})


@app.route("/validate", methods=["POST"])
def validate():
    """
    Client sends: {"license_key": "VELA-XXXX-XXXX-XXXX-XXXX"}
    Returns:      {"status": "active|revoked|expired|invalid", "tier": "command|standard", "message": ""}
    """
    data = request.get_json(silent=True)
    if not data or "license_key" not in data:
        return jsonify({"status": "invalid", "tier": "standard", "message": "No license key provided"}), 400

    raw_key = data["license_key"].strip()
    key_hash = hash_key(raw_key)

    db = get_db()
    row = db.execute(
        "SELECT * FROM licenses WHERE key_hash = ?", (key_hash,)
    ).fetchone()

    if not row:
        app.logger.warning(f"Unknown key attempt: {raw_key[:12]}...")
        return jsonify({"status": "invalid", "tier": "standard", "message": "License key not found"}), 200

    client_id = row["client_id"]
    status    = row["status"]       # active | revoked | suspended | expired
    tier      = row["tier"]         # command | standard
    expiry    = row["expiry"]       # ISO date or null

    # Update heartbeat
    db.execute(
        "UPDATE licenses SET last_ping = ?, ping_count = ping_count + 1 WHERE key_hash = ?",
        (now_iso(), key_hash)
    )
    db.commit()
    db.close()

    # Check expiry
    if expiry:
        exp_date = datetime.datetime.fromisoformat(expiry)
        if datetime.datetime.utcnow() > exp_date:
            app.logger.info(f"Expired key: {client_id}")
            return jsonify({"status": "expired", "tier": tier, "message": f"License expired {expiry}"}), 200

    if status == "active":
        return jsonify({"status": "active", "tier": tier, "message": "License valid", "client_id": client_id}), 200
    elif status in ("revoked", "suspended"):
        app.logger.info(f"Revoked/suspended key: {client_id}")
        return jsonify({"status": "revoked", "tier": tier, "message": f"License {status}. Contact greg@gregshindler.com."}), 200
    else:
        return jsonify({"status": "invalid", "tier": "standard", "message": f"Unknown status: {status}"}), 200


@app.route("/clients", methods=["GET"])
def list_clients():
    """Admin endpoint — protected by API key header."""
    _require_admin(request)
    db = get_db()
    rows = db.execute(
        "SELECT client_id, tier, status, expiry, last_ping, ping_count, created_at FROM licenses ORDER BY created_at DESC"
    ).fetchall()
    db.close()
    return jsonify([dict(r) for r in rows])


@app.route("/suspend/<client_id>", methods=["POST"])
def suspend(client_id):
    """Suspend a client instantly."""
    _require_admin(request)
    db = get_db()
    db.execute("UPDATE licenses SET status = 'suspended' WHERE client_id = ?", (client_id,))
    db.commit()
    affected = db.execute("SELECT changes()").fetchone()[0]
    db.close()
    if affected:
        return jsonify({"ok": True, "client_id": client_id, "status": "suspended"})
    return jsonify({"ok": False, "message": "Client not found"}), 404


@app.route("/reinstate/<client_id>", methods=["POST"])
def reinstate(client_id):
    """Reinstate a suspended client."""
    _require_admin(request)
    db = get_db()
    db.execute("UPDATE licenses SET status = 'active' WHERE client_id = ?", (client_id,))
    db.commit()
    affected = db.execute("SELECT changes()").fetchone()[0]
    db.close()
    if affected:
        return jsonify({"ok": True, "client_id": client_id, "status": "active"})
    return jsonify({"ok": False, "message": "Client not found"}), 404


@app.route("/upgrade/<client_id>", methods=["POST"])
def upgrade(client_id):
    """Change tier for a client. Body: {"tier": "command"}"""
    _require_admin(request)
    data = request.get_json(silent=True) or {}
    new_tier = data.get("tier", "command")
    if new_tier not in ("command", "standard"):
        return jsonify({"ok": False, "message": "Invalid tier"}), 400
    db = get_db()
    db.execute("UPDATE licenses SET tier = ? WHERE client_id = ?", (new_tier, client_id))
    db.commit()
    db.close()
    return jsonify({"ok": True, "client_id": client_id, "tier": new_tier})


# ── ADMIN AUTH ────────────────────────────────────────────────
def _require_admin(req):
    admin_key = os.environ.get("VELA_ADMIN_KEY", "")
    if not admin_key:
        raise RuntimeError("VELA_ADMIN_KEY not set on server")
    provided = req.headers.get("X-Admin-Key", "")
    if not secrets.compare_digest(admin_key, provided):
        from flask import abort
        abort(403)


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080, debug=False)
