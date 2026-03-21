# BOOT.md — {{AGENT_NAME}} Startup Manifest

Execute in this exact order on every session start.

## 1. Identity
Read: SOUL.md
Purpose: who I am, how I think, what I protect

## 2. User Context
Read: USER.md
Purpose: who I serve, his businesses, his priorities, his communication style

## 3. Operating System
Read: CORE.md
Purpose: all procedures, formats, proactive behaviors, rules

## 4. Routing
Read: AGENTS.md
Purpose: agent roster, spawn rules, cost rules, signal engine pointer

## 5. Memory
Read: memory/[TODAY].md (today's date)
Read: memory/[YESTERDAY].md (yesterday's date)
Read: MEMORY.md (main sessions only — not subagent sessions)
Purpose: recent context, learned rules, corrections

## 6. Live State — hannah.db
Run: sqlite3 ~/.openclaw/hannah.db "SELECT rank, objective, urgency, momentum, deadline FROM priorities ORDER BY rank;"
Run: sqlite3 ~/.openclaw/hannah.db "SELECT name, type, status, next_action, last_contact FROM entities WHERE status NOT IN ('closed','dormant') ORDER BY type, priority;"
Purpose: current priorities and active entities before first response

## 7. Commitments
Read: COMMITMENT_TRACKER.md
Purpose: every open commitment {{CLIENT_NAME}} has made — check deadlines against today's date
Rules:
- Anything due within 72 hours: surface immediately in first response
- Anything overdue: flag immediately regardless of what {{CLIENT_NAME}} asked
- Status Open + deadline passed = Overdue — update the entry and flag it

## 8. Confirm Ready
- Telegram channel active
- Today's date registered
- Live state loaded from hannah.db
- Commitments checked against today's date
- No errors in startup sequence

## Startup Complete
{{AGENT_NAME}} is ready. Do not proceed until all steps are complete.

## Notes
- Subagent sessions skip steps 5, 6, 7 — load task-specific context only after steps 1-4
- If a memory file for today does not exist yet, skip it silently
- Notion is disabled — do not reference or query it
- Source of truth for priorities and entities is hannah.db only
