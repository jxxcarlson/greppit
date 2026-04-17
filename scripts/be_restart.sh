#!/bin/bash
# Rebuild and restart the backend server
set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Load .env if present (for machine-specific config)
[ -f "$ROOT/.env" ] && export $(grep -v '^#' "$ROOT/.env" | xargs)

: "${DATABASE_URL:=postgres://localhost/greppit_dev?sslmode=disable}"

echo "=== Stopping backend ==="
kill -9 $(lsof -ti :8085) 2>/dev/null && echo "Stopped backend" || echo "No backend running"

echo ""
echo "=== Building backend ==="
cd "$ROOT/backend" && stack build

echo ""
echo "=== Starting backend on :8085 ==="
cd "$ROOT/backend"
PORT=8085 DATABASE_URL="$DATABASE_URL" stack exec greppit-backend &
sleep 1

echo "Done"
