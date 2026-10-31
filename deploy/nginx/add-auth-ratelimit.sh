#!/usr/bin/env bash
# Add the /api/auth/ rate limit (login, signup: 5 per minute per client)
# to the installed nginx config on the droplet, in place, keeping
# certbot's HTTPS section. Run from your Mac at the repo root:
#
#   ssh root@161.35.125.40 'bash -s' < deploy/nginx/add-auth-ratelimit.sh
#
# Backs up the config to /root/nginx-backups/ first. If `nginx -t` fails,
# the backup is restored and nginx is not reloaded. Running it twice is
# safe: the second run sees greppit_auth and stops.
set -euo pipefail

F=/etc/nginx/sites-available/greppit.app.conf
B=/root/nginx-backups/greppit.app.conf.$(date +%Y-%m-%d-%H%M%S)-pre-ratelimit

if grep -q greppit_auth "$F"; then
    echo "Already has the greppit_auth rate limit; nothing to do."
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

top = """# Rate limit for /api/auth/ (login, signup): 5 per minute per client.
# Behind Cloudflare, $remote_addr is Cloudflare's address, so key on the
# header Cloudflare sets; requests without it (direct to the droplet) use
# the connecting address, so they are limited too.
map $http_cf_connecting_ip $greppit_client {
    ""      $binary_remote_addr;
    default $http_cf_connecting_ip;
}
limit_req_zone $greppit_client zone=greppit_auth:10m rate=5r/m;

"""
anchor = "server {\n    server_name greppit.app www.greppit.app;\n"
assert t.count(anchor) == 1, "HTTPS server block not found as expected"
t = t.replace(anchor, top + anchor, 1)

loc_anchor = "    # API passthrough to the Haskell backend. Match GREPPIT_BACKEND_PORT in .env.\n    location /api/ {\n"
assert t.count(loc_anchor) == 1, "location /api/ not found as expected"
loc = """    # Login and signup, rate limited (see greppit_auth above). Over the
    # limit: 429 Too Many Requests.
    location /api/auth/ {
        limit_req zone=greppit_auth burst=5 nodelay;
        limit_req_status 429;
        proxy_pass http://127.0.0.1:8086;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $greppit_client;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 60s;
    }

"""
t = t.replace(loc_anchor, loc + loc_anchor, 1)
open(p, "w", encoding="utf-8").write(t)
PY

if nginx -t; then
    systemctl reload nginx
    echo "OK: nginx reloaded with the rate limit."
    diff -u "$B" "$F" || true
else
    cp -p "$B" "$F"
    echo "nginx -t failed: backup restored, nginx not reloaded."
    exit 1
fi
