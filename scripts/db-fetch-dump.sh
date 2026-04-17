#!/bin/bash
# Transfer the latest (or specified) dump file from the production host to
# the local machine. Run this on your local Mac.
#
# Host and remote directory come from .env. Set them before running, e.g.:
#
#   GREPPIT_PROD_HOST=root@greppit.app
#   GREPPIT_PROD_BACKUP_DIR=/root/greppit/backups
#
# Usage:
#   ./db-fetch-dump.sh                  # fetches the latest dump
#   ./db-fetch-dump.sh <filename>       # fetches a specific dump file

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
[ -f "$ROOT/.env" ] && export $(grep -v '^#' "$ROOT/.env" | xargs)

if [ -z "${GREPPIT_PROD_HOST:-}" ] || [ -z "${GREPPIT_PROD_BACKUP_DIR:-}" ]; then
    echo "Error: set GREPPIT_PROD_HOST and GREPPIT_PROD_BACKUP_DIR in .env"
    exit 1
fi

LOCAL_DIR="$ROOT/backups"
mkdir -p "$LOCAL_DIR"

if [ -n "${1:-}" ]; then
    FILENAME="$1"
else
    echo "Finding latest dump on $GREPPIT_PROD_HOST ..."
    FILENAME=$(ssh "$GREPPIT_PROD_HOST" "ls -t $GREPPIT_PROD_BACKUP_DIR/*.dump 2>/dev/null | head -1 | xargs basename")
    if [ -z "$FILENAME" ]; then
        echo "Error: no dump files found on the host. Run db-dump-do.sh on the server first."
        exit 1
    fi
fi

echo "Downloading $FILENAME ..."
scp "$GREPPIT_PROD_HOST:$GREPPIT_PROD_BACKUP_DIR/$FILENAME" "$LOCAL_DIR/$FILENAME"
echo "Done: $LOCAL_DIR/$FILENAME"
