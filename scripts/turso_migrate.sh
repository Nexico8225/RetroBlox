#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# RetroBlox → Turso (libSQL) migration
# Copies the local SQLite database (schema + ALL data) into a Turso database.
#
# Prerequisites (one-time):
#   1. Turso CLI installed + logged in:
#        curl -sSfL https://get.tur.so/install.sh | bash     (macOS/Linux)
#        turso auth login
#   2. A database created:
#        turso db create retroblox
#
# Usage:
#   bash scripts/turso_migrate.sh retroblox
#      (or pass the full libsql:// url instead of the name)
#
# After it succeeds, set in Vercel (Settings → Environment Variables):
#   DATABASE_URL      = turso db show retroblox --url      (libsql://…)
#   LIBSQL_AUTH_TOKEN = turso db tokens create retroblox
# then redeploy.
# ---------------------------------------------------------------------------
set -euo pipefail
cd "$(dirname "$0")/.."

DB_NAME_OR_URL="${1:?Usage: bash scripts/turso_migrate.sh <turso-db-name-or-url>}"
LOCAL_DB="db/custom.db"
DUMP="/tmp/retroblox-dump.sql"

command -v sqlite3 >/dev/null || { echo "sqlite3 is required (brew install sqlite3 / apt install sqlite3)"; exit 1; }
command -v turso   >/dev/null || { echo "turso CLI is required (curl -sSfL https://get.tur.so/install.sh | bash)"; exit 1; }
[ -f "$LOCAL_DB" ] || { echo "$LOCAL_DB not found — run from the project root copy that has your data"; exit 1; }

echo "== dumping $LOCAL_DB =="
sqlite3 "$LOCAL_DB" ".dump" > "$DUMP"
echo "   $(grep -c 'INSERT INTO' "$DUMP" || true) insert statements, $(du -h "$DUMP" | cut -f1)"

echo "== importing into Turso: $DB_NAME_OR_URL =="
# -bail so a half-applied dump never looks like success; strips the WAL pragma
# lines that only make sense for local files.
grep -v -E "^PRAGMA (foreign_keys|journal_mode|wal)" "$DUMP" | turso db shell "$DB_NAME_OR_URL"

echo
echo "== done =="
echo "Now set these in Vercel and redeploy:"
echo "  DATABASE_URL      $(turso db show "$DB_NAME_OR_URL" --url 2>/dev/null || echo '<libsql url from: turso db show <name> --url>')"
echo "  LIBSQL_AUTH_TOKEN $(turso db tokens create "$DB_NAME_OR_URL" 2>/dev/null || echo '<token from: turso db tokens create <name>')"
