#!/usr/bin/env bash
# Nightly off-server copy of the database dumps on rose2 to Backblaze B2.
# Installed as /usr/local/sbin/b2-backup.sh; root's crontab runs it at
# 03:40 UTC, after the apps' own dumps at 03:00:
#
#   40 3 * * * /usr/local/sbin/b2-backup.sh >> /var/log/b2-backup.log 2>&1
#
# For each app it uploads the newest dump made in the last 24 hours to
# b2backup:jxxcarlson-rose2-backups/rose2/<app>/<file>. The key is
# write-only, so it can't list or delete: the upload doesn't check what's
# already there, and old dumps are removed by the bucket's lifecycle rule
# (hidden after 30 days, deleted a day later). Exits non-zero if any app
# had no fresh dump or an upload failed.
set -uo pipefail

BUCKET=jxxcarlson-rose2-backups
APPS="greppit:/root/greppit/backups scripta:/root/scripta-app-v4/backups cloudelog:/root/cloudelog/backups"
status=0

echo "== $(date -u +%FT%TZ) b2-backup"
for entry in $APPS; do
    app=${entry%%:*}; dir=${entry#*:}
    newest=$(find "$dir" -maxdepth 1 -type f -name '*.dump' -mmin -1440 -printf '%T@ %p\n' 2>/dev/null \
             | sort -n | tail -1 | cut -d' ' -f2-)
    if [ -z "$newest" ]; then
        echo "  $app: NO dump from the last 24 hours in $dir"
        status=1; continue
    fi
    if rclone copyto --no-check-dest --retries 3 "$newest" "b2backup:$BUCKET/rose2/$app/$(basename "$newest")"; then
        echo "  $app: uploaded $(basename "$newest") ($(du -h "$newest" | cut -f1))"
    else
        echo "  $app: upload FAILED for $newest"
        status=1
    fi
done
exit $status
