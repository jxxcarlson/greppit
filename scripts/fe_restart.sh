#!/bin/bash
# Rebuild and restart the frontend server
set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Load .env if present
[ -f "$ROOT/.env" ] && export $(grep -v '^#' "$ROOT/.env" | xargs)

FE_PORT="${GREPPIT_FRONTEND_PORT:-8011}"

echo "=== Stopping frontend (port $FE_PORT) ==="
kill -9 $(lsof -ti :$FE_PORT) 2>/dev/null && echo "Stopped frontend" || echo "No frontend running"

echo ""
echo "=== Building frontend ==="
cd "$ROOT/frontend" && elm make src/Main.elm --output=elm.js

echo ""
echo "=== Starting frontend on :$FE_PORT ==="
cd "$ROOT/frontend"
PORT="$FE_PORT" python3 "$ROOT/frontend/serve.py" &

echo ""
echo "Done. Open http://localhost:$FE_PORT"
