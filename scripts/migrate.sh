#!/bin/bash
# Run database migrations
# Usage: ./migrate.sh [up|down|status]
#
# Uses DATABASE_URL from .env (if present) or environment. Defaults to local dev DB.
# Appends ?sslmode=disable for local connections.

set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Load .env if present — essential on shared servers where the prod
# DATABASE_URL is only set in the project's .env, not exported globally.
[ -f "$ROOT/.env" ] && export $(grep -v '^#' "$ROOT/.env" | xargs)

ACTION="${1:-up}"
DATABASE_URL="${DATABASE_URL:-postgres://localhost/greppit_dev}"

# If it looks like a local connection, disable SSL (Homebrew Postgres has no SSL by default).
if echo "$DATABASE_URL" | grep -qE "localhost|127\.0\.0\.1"; then
    DATABASE_URL=$(echo "$DATABASE_URL" | sed 's/[?&]sslmode=[^&]*//')
    DATABASE_URL="${DATABASE_URL}?sslmode=disable"
fi

exec dbmate -d "$ROOT/backend/dbmate/migrations" --url "$DATABASE_URL" "$ACTION"
