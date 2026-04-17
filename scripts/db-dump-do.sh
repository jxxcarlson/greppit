#!/bin/bash
# Dump the greppit database on the production host.
# Run this ON the production droplet. Reads DATABASE_URL from .env in the
# project root.
#
# Usage: ./db-dump-do.sh
# Output: backups/greppit_YYYYMMDD_HHMMSS.dump

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
[ -f "$ROOT/.env" ] && export $(grep -v '^#' "$ROOT/.env" | xargs)

if [ -z "${DATABASE_URL:-}" ]; then
    echo "Error: DATABASE_URL not set (check .env)"
    exit 1
fi

mkdir -p "$ROOT/backups"
FILENAME="greppit_$(date +%Y%m%d_%H%M%S).dump"
FILEPATH="$ROOT/backups/$FILENAME"

echo "Dumping database to $FILEPATH ..."
pg_dump "$DATABASE_URL" --format=custom --no-owner --no-acl -f "$FILEPATH"
echo "Done: $FILEPATH ($(du -h "$FILEPATH" | cut -f1))"
