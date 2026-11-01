#!/usr/bin/env bash
# Add security headers to greppit.app's installed nginx config on the
# droplet, in place, keeping certbot's HTTPS section. Also gives /app.js
# the same no-cache rule as elm.js. Run from your Mac at the repo root:
#
#   ssh root@147.182.143.224 'bash -s' < deploy/nginx/add-security-headers.sh
#
# Writes /etc/nginx/snippets/greppit-security-headers.conf (same content
# as deploy/nginx/greppit-security-headers.conf) and includes it in the
# server block and in each location with its own add_header.
#
# Backs up the config to /root/nginx-backups/ first. If `nginx -t` fails,
# the backup is restored, the snippet removed, and nginx is not reloaded.
# Running it twice is safe: the second run sees the include and stops.
set -euo pipefail

F=/etc/nginx/sites-available/greppit.app.conf
S=/etc/nginx/snippets/greppit-security-headers.conf
B=/root/nginx-backups/greppit.app.conf.$(date +%Y-%m-%d-%H%M%S)-pre-headers

if grep -q 'greppit-security-headers.conf' "$F"; then
    echo "Already includes the security headers; nothing to do."
    exit 0
fi

mkdir -p /root/nginx-backups
cp -p "$F" "$B"
echo "Backup: $B"

cat > "$S" <<'CONF'
# Security headers for greppit.app (deploy/nginx/greppit-security-headers.conf
# in the greppit repo). Included in the server block AND in every location
# that has its own add_header: nginx drops inherited add_header lines there.
add_header Strict-Transport-Security "max-age=31536000" always;
add_header X-Content-Type-Options "nosniff" always;
add_header X-Frame-Options "DENY" always;
add_header Content-Security-Policy "frame-ancestors 'none'" always;
add_header Referrer-Policy "strict-origin-when-cross-origin" always;
CONF

python3 - "$F" <<'PY'
import sys
p = sys.argv[1]
# UTF-8 explicitly: the server's Python 3.6 defaults to ASCII, and the
# config has non-ASCII characters in its comments.
t = open(p, encoding="utf-8").read()
inc = "include snippets/greppit-security-headers.conf;"

a = "    root /root/greppit/frontend;\n    index index.html;\n"
assert t.count(a) == 1, "root/index lines not found as expected"
t = t.replace(a, a + """
    # Security headers. Repeated in each location below that has its own
    # add_header, because nginx drops inherited add_header lines there.
    """ + inc + "\n", 1)

nc = '        add_header Cache-Control "no-cache";\n'
assert t.count(nc) == 3, "expected 3 no-cache locations"
t = t.replace(nc, nc + "        " + inc + "\n")

e = "    location = /elm.js {\n"
assert t.count(e) == 1, "location = /elm.js not found"
t = t.replace(e, """    location = /app.js {
        add_header Cache-Control "no-cache";
        """ + inc + """
    }
""" + e, 1)

open(p, "w", encoding="utf-8").write(t)
PY

if nginx -t; then
    systemctl reload nginx
    echo "OK: nginx reloaded with the security headers."
    diff -u "$B" "$F" || true
else
    cp -p "$B" "$F"
    rm -f "$S"
    echo "nginx -t failed: backup restored, nginx not reloaded."
    exit 1
fi
