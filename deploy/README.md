# greppit deployment runbook

One droplet, nginx in front, Haskell backend under systemd, frontend
served as static files. TLS terminated at the droplet with a Cloudflare
Origin Certificate; Cloudflare proxies in front ("Full (strict)" mode).

This runbook assumes a single DigitalOcean droplet running as `root`.
Adjust `User=` and paths if you run greppit as a non-root user.

## Where greppit runs now

- **Droplet:** **rose2**, `root@147.182.143.224`. It's a DigitalOcean
  NYC1 droplet: Ubuntu 24.04, 4 vCPU, 8 GB of memory, 160 GB of disk,
  with weekly DigitalOcean backups. It has run greppit since 2026-11-01,
  replacing **rose** (161.35.125.40, Ubuntu 18.04).
- **Also on it:** cloudelog, scripta (x-scripta.app), pdfServer and the
  stopped kv-store. Each is in its own folder under `/root`.
- **DNS:** greppit.app and www (a CNAME to greppit.app) are proxied by
  Cloudflare, with SSL/TLS mode Full (strict).
- **What's installed:**
  - Postgres 16, nginx 1.24, certbot (apt);
  - GHC 9.6.6 and 9.6.7, cabal and Stack, via ghcup in `/root/.ghcup`;
    `stack` is symlinked into `/usr/local/bin`;
  - Elm 0.19.2 (npm), and 4 GB of swap.
- **How it was built:** `docs/superpowers/specs/2026-11-01-server-migration-design.md`.
- **Already applied on rose2:** the scripts in `deploy/nginx/` (rate
  limit, no-cache, security headers) and key-only SSH. `harden-ssh.sh`
  was for rose; rose2 uses `/etc/ssh/sshd_config.d/00-hardening.conf`.
- **GitHub access:** rose2 pulls from GitHub with its own key,
  `root@rose2`, which is on James's GitHub account.

---

## Phase 1 — Prerequisites (once per droplet)

```
apt update
apt install -y build-essential libpq-dev postgresql postgresql-contrib \
  nginx jq curl python3 git

# GHC + Stack via ghcup (as on rose2). greppit's resolver lts-22.43 uses
# GHC 9.6.6; build with `stack --system-ghc` so Stack uses this one.
curl --proto '=https' --tlsv1.2 -sSf https://get-ghcup.haskell.org | \
  BOOTSTRAP_HASKELL_NONINTERACTIVE=1 BOOTSTRAP_HASKELL_GHC_VERSION=9.6.6 \
  BOOTSTRAP_HASKELL_INSTALL_STACK=1 sh
ln -sf /root/.ghcup/bin/stack /usr/local/bin/stack

# nginx (user www-data) serves the frontend from /root/greppit/frontend,
# so it must be able to pass through /root (but not list it):
chmod 711 /root

# Elm 0.19.2 + elm-test
apt install -y npm
npm install -g elm@latest-0.19.2 elm-test

# dbmate
curl -fsSL https://github.com/amacneil/dbmate/releases/latest/download/dbmate-linux-amd64 \
  -o /usr/local/bin/dbmate && chmod +x /usr/local/bin/dbmate
```

Firewall: open 22, 80, 443 only. The backend and frontend ports bind to
`127.0.0.1` via systemd + nginx, so they're never reachable from outside.

## Phase 2 — Postgres

```
sudo -u postgres createuser greppit
sudo -u postgres createdb -O greppit greppit_prod
sudo -u postgres psql -c "ALTER USER greppit WITH PASSWORD 'PICK-A-STRONG-ONE';"
```

## Phase 3 — Repo + `.env`

```
cd ~ && git clone git@github.com:jxxcarlson/greppit.git  # or https URL
cd greppit
cp .env.example .env
```

Edit `~/greppit/.env` (see `.env.example` for all knobs). Minimum:

```
DATABASE_URL=postgres://greppit:STRONG-PASS@localhost/greppit_prod
GREPPIT_BACKEND_PORT=8086
PORT=8086                     # mirror of GREPPIT_BACKEND_PORT, read by the backend directly
JWT_SECRET=<output of: openssl rand -base64 48>
JWT_EXPIRY_DAYS=7
```

Pick any unused port for `GREPPIT_BACKEND_PORT` (avoiding 8000-8010 and
anything another project on the same host uses). Set `PORT` to the same
value so the systemd unit and the dev scripts agree.

## Phase 4 — First smoke test

```
cd ~/greppit
./scripts/migrate.sh up
./scripts/restart.sh --all
```

Verify:

```
curl -s  http://localhost:8086/api/health              # "ok"
bash backend/test-api.sh                                # should pass every section
```

If green, tear down the dev servers — nginx + systemd will run them in
production:

```
./scripts/stop.sh
```

## Phase 5 — Production build of frontend

```
cd ~/greppit/frontend
elm make src/Main.elm --optimize --output=elm.js
```

nginx will serve these static files: `index.html`, `elm.js`,
`codemirror-element.js`. No `serve.py` in production.

## Phase 6 — systemd unit for the backend

First, install the compiled binary to a stable path. The systemd unit
calls `/usr/local/bin/greppit-backend` directly, which avoids a
"binary not found under this snapshot hash" trap that `stack exec`
produces when run from systemd:

```
cd /root/greppit/backend
stack install --local-bin-path /usr/local/bin
ls -l /usr/local/bin/greppit-backend
```

(Repeat this `stack install` whenever you rebuild the backend after a
pull.)

Then install and start the service:

```
cp /root/greppit/deploy/greppit-backend.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now greppit-backend
systemctl status greppit-backend         # active (running)
journalctl -u greppit-backend -f         # tail logs (Ctrl-C to stop)
```

From here on, restart the backend with `systemctl restart greppit-backend`,
not with `scripts/restart.sh`.

## Phase 7 — nginx (HTTP only, cert arrives in Phase 8)

The config in `deploy/nginx/greppit.app.conf` is intentionally HTTP-only.
Certbot adds the TLS listener + redirect on first run (same pattern as
the existing scripta site on this droplet).

```
cp /root/greppit/deploy/nginx/greppit.app.conf /etc/nginx/sites-available/
ln -sf /etc/nginx/sites-available/greppit.app.conf /etc/nginx/sites-enabled/
nginx -t
systemctl reload nginx
```

`nginx -t` should pass cleanly — no cert references yet.

## Phase 8 — TLS cert (Let's Encrypt via certbot)

Matches scripta's setup on this droplet.

### DNS first

In the Cloudflare dashboard, add an `A` record:

- `greppit.app → <droplet IP>`
- **Proxy status: DNS only** (grey cloud) *temporarily*, so Let's
  Encrypt's HTTP-01 challenge reaches your droplet directly.

(Optional: also `A` record for `www.greppit.app` to the same IP.)

Give DNS a minute, then verify resolution:

```
dig +short greppit.app
```

### Issue the cert

```
apt install -y python3-certbot-nginx       # if not installed
certbot --nginx -d greppit.app -d www.greppit.app
```

Follow the prompts (email, ToS). Certbot will:

1. Verify domain control via HTTP-01.
2. Write the cert to `/etc/letsencrypt/live/greppit.app/`.
3. Patch `/etc/nginx/sites-available/greppit.app.conf` in place to add
   `listen 443 ssl`, the cert paths, and an HTTP → HTTPS redirect
   (you'll see `# managed by Certbot` comments, same as scripta).
4. Reload nginx.

Verify the patched config:

```
grep -n 'managed by Certbot' /etc/nginx/sites-available/greppit.app.conf
nginx -t
curl -sI http://greppit.app/     # 301 redirect to https
curl -sI https://greppit.app/    # 200
```

**Auto-renewal:** certbot installs a systemd timer (`certbot.timer`). It
renews every cert on the box — scripta's and greppit's both get picked
up automatically. `systemctl list-timers certbot.timer` to confirm.

## Phase 9 — Cloudflare proxy + SSL mode

Now flip Cloudflare's proxy on:

- DNS → set the `greppit.app` record to **Proxied** (orange cloud).
- SSL/TLS → Overview → **Full (strict)**. Let's Encrypt is trusted by
  Cloudflare, so Full (strict) works immediately. Never use "Flexible"
  — it's plaintext between Cloudflare and your droplet.
- SSL/TLS → Edge Certificates → **Always Use HTTPS: On**, **Min TLS 1.2**.

## Phase 10 — Verify

From a machine other than the droplet:

```
curl -sI https://greppit.app/                    # HTTP/2 200
curl -s  https://greppit.app/api/health          # "ok"
```

Open `https://greppit.app/` in a browser and sign up.

---

## Ongoing operations

- **Schema change:** push the migration to git, pull on the server,
  `scripts/migrate.sh up`, then `systemctl restart greppit-backend`.
- **Frontend update:** pull on the server, `elm make src/Main.elm
  --optimize --output=elm.js` in `frontend/`. No service restart needed —
  nginx serves the new file on the next request.
- **Backend update:** pull on the server, then
  `cd backend && stack --system-ghc install --local-bin-path /usr/local/bin`,
  then `systemctl restart greppit-backend`. Afterwards, check that
  `systemctl is-active greppit-backend` says `active`. `/api/health`
  alone can be answered by a stray process: on rose a hand-started
  backend from June held the port until 2026-11-01.
  Note: `stack build` alone is NOT enough — it only updates the binary
  inside `.stack-work/`. The systemd unit runs `/usr/local/bin/greppit-backend`,
  so you must `stack install` to refresh that path. If the service fails
  to bind the port after restart, check for an orphaned backend process:
  `ss -tlnp | grep <port>` and `kill` it before trying again.
- **Backups:** `scripts/db-dump-do.sh` dumps to `~/greppit/backups/`.
  Cron suggestion: `0 3 * * * /root/greppit/scripts/db-dump-do.sh`.
  Pull dumps to your Mac with `scripts/db-fetch-dump.sh` after setting
  `GREPPIT_PROD_HOST` and `GREPPIT_PROD_BACKUP_DIR` in your *local* `.env`.

## Things that must never change after launch

- `JWT_SECRET` — changing it invalidates every issued token.
- The `users.id` and `snippets.id` columns (both are client/server-generated
  UUIDs that JWTs and snippet references depend on).

## Things to revisit later

- Run greppit as a dedicated non-root user (`adduser greppit`, then
  `User=greppit` in the systemd unit and `chown -R greppit:greppit` on the
  checkout).
- Add a real logging / metrics pipeline (journald + Grafana Loki is
  lightweight; Honeycomb or equivalent if you want tracing later).
- `fail2ban` for ssh + nginx.
