#!/usr/bin/env bash
# Store the Backblaze B2 key for the nightly off-server backup on rose2.
# Run it in your own terminal (it asks for the key and doesn't echo it):
#
#   ssh -t root@147.182.143.224 /usr/local/sbin/b2-set-key.sh
#
# The key should be the write-only application key "rose2-backup", limited
# to the bucket jxxcarlson-rose2-backups (never the master key). It's saved
# in /root/.config/rclone/rclone.conf (mode 600), as the rclone remote
# "b2backup", and then tested with a small upload.
set -euo pipefail

BUCKET=jxxcarlson-rose2-backups
CONF=/root/.config/rclone/rclone.conf

read -r -p "B2 keyID: " KEYID
read -r -s -p "B2 applicationKey (not shown): " APPKEY; echo
[ -n "$KEYID" ] && [ -n "$APPKEY" ] || { echo "Both values are needed."; exit 1; }

umask 077
mkdir -p "$(dirname "$CONF")"
# Keep any other remotes; replace only [b2backup].
if [ -f "$CONF" ]; then
    python3 - "$CONF" <<'PY'
import sys, re
p = sys.argv[1]
t = open(p).read()
t = re.sub(r"(?ms)^\[b2backup\]\n.*?(?=^\[|\Z)", "", t)
open(p, "w").write(t.rstrip("\n") + ("\n" if t.strip() else ""))
PY
fi
cat >> "$CONF" <<EOF
[b2backup]
type = b2
account = $KEYID
key = $APPKEY
hard_delete = false
EOF
chmod 600 "$CONF"
echo "Saved to $CONF (mode $(stat -c %a "$CONF"))."

echo "Testing an upload..."
T=$(mktemp)
echo "b2 key test from $(hostname) at $(date -u +%FT%TZ)" > "$T"
if rclone copyto --no-check-dest "$T" "b2backup:$BUCKET/rose2/key-test.txt"; then
    echo "OK: uploaded rose2/key-test.txt. It will expire with the lifecycle rule."
else
    echo "Upload FAILED: check the keyID/applicationKey and that the key allows writing to $BUCKET."
    rm -f "$T"; exit 1
fi
rm -f "$T"
