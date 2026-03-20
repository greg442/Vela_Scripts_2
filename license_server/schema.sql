-- VELA License Server Schema
-- SQLite — runs on DigitalOcean droplet
-- Apply: sqlite3 /opt/vela/licenses.db < schema.sql

CREATE TABLE IF NOT EXISTS licenses (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    client_id   TEXT NOT NULL UNIQUE,          -- e.g. "john_smith" — your internal ID
    key_hash    TEXT NOT NULL UNIQUE,          -- SHA-256 of the raw license key
    status      TEXT NOT NULL DEFAULT 'active', -- active | suspended | revoked | expired
    tier        TEXT NOT NULL DEFAULT 'command', -- command | standard
    expiry      TEXT,                           -- ISO date, NULL = no expiry
    created_at  TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
    last_ping   TEXT,                           -- last validation ping from client
    ping_count  INTEGER NOT NULL DEFAULT 0,     -- total pings received
    notes       TEXT                            -- internal notes, not sent to client
);

-- Index for fast key lookup
CREATE INDEX IF NOT EXISTS idx_key_hash   ON licenses(key_hash);
CREATE INDEX IF NOT EXISTS idx_client_id  ON licenses(client_id);
CREATE INDEX IF NOT EXISTS idx_status     ON licenses(status);

-- Audit log — every status change recorded
CREATE TABLE IF NOT EXISTS audit_log (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    client_id   TEXT NOT NULL,
    action      TEXT NOT NULL,   -- created | suspended | reinstated | upgraded | revoked
    old_value   TEXT,
    new_value   TEXT,
    performed_by TEXT DEFAULT 'admin',
    timestamp   TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
    notes       TEXT
);

CREATE INDEX IF NOT EXISTS idx_audit_client ON audit_log(client_id);
CREATE INDEX IF NOT EXISTS idx_audit_ts     ON audit_log(timestamp);

-- Trigger: auto-log status changes
CREATE TRIGGER IF NOT EXISTS log_status_change
AFTER UPDATE OF status ON licenses
WHEN OLD.status != NEW.status
BEGIN
    INSERT INTO audit_log(client_id, action, old_value, new_value)
    VALUES (NEW.client_id, 'status_change', OLD.status, NEW.status);
END;

-- Trigger: auto-log tier changes
CREATE TRIGGER IF NOT EXISTS log_tier_change
AFTER UPDATE OF tier ON licenses
WHEN OLD.tier != NEW.tier
BEGIN
    INSERT INTO audit_log(client_id, action, old_value, new_value)
    VALUES (NEW.client_id, 'tier_change', OLD.tier, NEW.tier);
END;
