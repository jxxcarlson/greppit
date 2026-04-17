#!/bin/bash
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
[ -f "$ROOT/.env" ] && export $(grep -v '^#' "$ROOT/.env" | xargs)

BE_PORT="${GREPPIT_BACKEND_PORT:-8085}"
FE_PORT="${GREPPIT_FRONTEND_PORT:-8011}"

kill -9 $(lsof -ti :$BE_PORT) 2>/dev/null && echo "Stopped backend ($BE_PORT)" || echo "No backend running on $BE_PORT"
kill -9 $(lsof -ti :$FE_PORT) 2>/dev/null && echo "Stopped frontend ($FE_PORT)" || echo "No frontend running on $FE_PORT"
