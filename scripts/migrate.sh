#!/bin/bash
# Run database migrations
# Usage: ./migrate.sh [up|down|status]
#
# Uses DATABASE_URL from environment. Defaults to local dev DB.
# Appends ?sslmode=disable for local dev (no SSL).
# In production, set DATABASE_URL with SSL params already included.

ACTION="${1:-up}"
DATABASE_URL="${DATABASE_URL:-postgres://localhost/greppit_dev}"

# If it looks like a local connection, disable SSL
if echo "$DATABASE_URL" | grep -qE "localhost|127\.0\.0\.1"; then
    DATABASE_URL=$(echo "$DATABASE_URL" | sed 's/[?&]sslmode=[^&]*//')
    DATABASE_URL="${DATABASE_URL}?sslmode=disable"
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
exec dbmate -d "$ROOT/backend/dbmate/migrations" --url "$DATABASE_URL" "$ACTION"
