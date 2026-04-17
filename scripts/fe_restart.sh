#!/bin/bash
# Rebuild and restart the frontend server
set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "=== Stopping frontend ==="
kill -9 $(lsof -ti :8011) 2>/dev/null && echo "Stopped frontend" || echo "No frontend running"

echo ""
echo "=== Building frontend ==="
cd "$ROOT/frontend" && elm make src/Main.elm --output=elm.js

echo ""
echo "=== Starting frontend on :8011 ==="
cd "$ROOT/frontend"
python3 "$ROOT/frontend/serve.py" &

echo ""
echo "Done. Open http://localhost:8011"
