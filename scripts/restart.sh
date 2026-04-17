#!/bin/bash
# Rebuild and restart backend, frontend, or both
set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "ROOT=${ROOT}"

# Load .env if present (for machine-specific config)
[ -f "$ROOT/.env" ] && export $(grep -v '^#' "$ROOT/.env" | xargs)

: "${DATABASE_URL:=postgres://localhost/greppit_dev?sslmode=disable}"
BE_PORT="${GREPPIT_BACKEND_PORT:-8085}"
FE_PORT="${GREPPIT_FRONTEND_PORT:-8011}"

usage() {
    echo "Usage: $0 [--backend | --frontend | --all | --help] [--opt]"
    echo ""
    echo "Options:"
    echo "  --backend   Rebuild and restart backend only (stays in foreground)"
    echo "  --frontend  Rebuild and restart frontend only (stays in foreground)"
    echo "  --all       Rebuild and restart both (default, both backgrounded)"
    echo "  --opt       Use --optimize flag for elm make"
    echo "  --help      Show this help"
    echo ""
    echo "Ports come from .env (GREPPIT_BACKEND_PORT, GREPPIT_FRONTEND_PORT)."
    echo "Current: backend=$BE_PORT frontend=$FE_PORT"
}

stop_backend() {
    kill -9 $(lsof -ti :$BE_PORT) 2>/dev/null && echo "Stopped backend ($BE_PORT)" || echo "No backend running on $BE_PORT"
}

stop_frontend() {
    kill -9 $(lsof -ti :$FE_PORT) 2>/dev/null && echo "Stopped frontend ($FE_PORT)" || echo "No frontend running on $FE_PORT"
}

build_backend() {
    echo "=== Building backend ==="
    cd "$ROOT/backend" && stack build
}

build_frontend() {
    echo "=== Building frontend ==="
    if [ "$ELM_OPTIMIZE" = "1" ]; then
        echo "(with --optimize)"
        cd "$ROOT/frontend" && elm make src/Main.elm --optimize --output=elm.js
    else
        cd "$ROOT/frontend" && elm make src/Main.elm --output=elm.js
    fi
}

start_backend_fg() {
    cd "$ROOT/backend"
    echo "=== Starting backend on :$BE_PORT (foreground) ==="
    echo "=== Directory: $(pwd) ==="
    echo ""
    PORT="$BE_PORT" DATABASE_URL="$DATABASE_URL" exec stack exec greppit-backend
}

start_backend_bg() {
    echo "=== Starting backend on :$BE_PORT ==="
    cd "$ROOT/backend"
    PORT="$BE_PORT" DATABASE_URL="$DATABASE_URL" stack exec greppit-backend &
    sleep 1
}

start_frontend_fg() {
    cd "$ROOT/frontend"
    echo "=== Starting frontend on :$FE_PORT (foreground) ==="
    echo "=== Directory: $(pwd) ==="
    echo ""
    exec env PORT="$FE_PORT" python3 "$ROOT/frontend/serve.py"
}

start_frontend_bg() {
    echo "=== Starting frontend on :$FE_PORT ==="
    cd "$ROOT/frontend"
    PORT="$FE_PORT" python3 "$ROOT/frontend/serve.py" &
}

# Parse arguments
MODE="--all"
ELM_OPTIMIZE=0
for arg in "$@"; do
    case "$arg" in
        --opt) ELM_OPTIMIZE=1 ;;
        --backend|--frontend|--all|--help) MODE="$arg" ;;
        *) MODE="$arg" ;;
    esac
done

case "$MODE" in
    --backend)
        stop_backend
        echo ""
        build_backend
        echo ""
        start_backend_fg
        ;;
    --frontend)
        stop_frontend
        echo ""
        build_frontend
        echo ""
        start_frontend_fg
        ;;
    --all)
        stop_backend
        stop_frontend
        echo ""
        build_backend
        echo ""
        build_frontend
        echo ""
        start_backend_bg
        start_frontend_bg
        echo ""
        echo "Done. Open http://localhost:$FE_PORT"
        ;;
    --help)
        usage
        ;;
    *)
        echo "Unknown option: $MODE"
        usage
        exit 1
        ;;
esac
