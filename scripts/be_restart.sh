#!/bin/bash
# Rebuild and restart the backend server
set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Load .env if present (for machine-specific config)
[ -f "$ROOT/.env" ] && export $(grep -v '^#' "$ROOT/.env" | xargs)

: "${DATABASE_URL:=postgres://localhost/greppit_dev?sslmode=disable}"
BE_PORT="${GREPPIT_BACKEND_PORT:-8085}"

echo "=== Stopping backend (port $BE_PORT) ==="
kill -9 $(lsof -ti :$BE_PORT) 2>/dev/null && echo "Stopped backend" || echo "No backend running"

echo ""
echo "=== Building backend ==="
cd "$ROOT/backend" && stack build

echo ""
echo "=== Starting backend on :$BE_PORT ==="
cd "$ROOT/backend"
PORT="$BE_PORT" DATABASE_URL="$DATABASE_URL" stack exec greppit-backend &
sleep 1

echo "Done"
