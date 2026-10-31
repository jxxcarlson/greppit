#!/usr/bin/env bash
# Make browsers and Cloudflare revalidate index.html, elm.js and
# codemirror-element.js on every load (Cache-Control: no-cache), in the
# installed nginx config on the droplet, keeping certbot's HTTPS section.
# Run from your Mac at the repo root:
#
#   ssh root@161.35.125.40 'bash -s' < deploy/nginx/add-no-cache.sh
#
# Then purge Cloudflare once (dashboard: Caching → Configuration → Purge
# Everything) so the copies cached under the old rules go away.
#
# Backs up the config to /root/nginx-backups/ first. If `nginx -t` fails,
# the backup is restored and nginx is not reloaded. Running it twice is
# safe: the second run sees the change and stops.
set -euo pipefail

F=/etc/nginx/sites-available/greppit.app.conf
B=/root/nginx-backups/greppit.app.conf.$(date +%Y-%m-%d-%H%M%S)-pre-no-cache

if grep -q 'location = /index.html' "$F"; then
    echo "Already has the no-cache rules; nothing to do."
    exit 0
fi

mkdir -p /root/nginx-backups
cp -p "$F" "$B"
echo "Backup: $B"

python3 - "$F" <<'PY'
import sys
p = sys.argv[1]
# UTF-8 explicitly: the server's Python 3.6 defaults to ASCII, and the
# config has non-ASCII characters in its comments.
t = open(p, encoding="utf-8").read()

old = """    # Cache long for the elm bundle and the vendored CodeMirror; bust
    # with a query string when you ship a new build.
    location = /elm.js {
        add_header Cache-Control "public, max-age=3600";
    }
    location = /codemirror-element.js {
        add_header Cache-Control "public, max-age=31536000";
    }
"""
new = """    # The app files keep the same URLs across deploys, so browsers and
    # Cloudflare must revalidate them on every load (a cheap 304 when
    # unchanged); otherwise a new build stays hidden behind cached copies
    # for hours. Cloudflare always honours no-cache. index.html is also
    # reached by the `index` directive and the SPA fallback below.
    location = /index.html {
        add_header Cache-Control "no-cache";
    }
    location = /elm.js {
        add_header Cache-Control "no-cache";
    }
    location = /codemirror-element.js {
        add_header Cache-Control "no-cache";
    }
"""
assert t.count(old) == 1, "cache blocks not found as expected"
t = t.replace(old, new, 1)
open(p, "w", encoding="utf-8").write(t)
PY

if nginx -t; then
    systemctl reload nginx
    echo "OK: nginx reloaded with the no-cache rules."
    diff -u "$B" "$F" || true
else
    cp -p "$B" "$F"
    echo "nginx -t failed: backup restored, nginx not reloaded."
    exit 1
fi
