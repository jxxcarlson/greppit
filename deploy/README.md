# greppit deployment runbook

One droplet, nginx in front, Haskell backend under systemd, frontend
served as static files. TLS terminated at the droplet with a Cloudflare
Origin Certificate; Cloudflare proxies in front ("Full (strict)" mode).

This runbook assumes a single DigitalOcean droplet running as `root`.
Adjust `User=` and paths if you run greppit as a non-root user.

---

## Phase 1 — Prerequisites (once per droplet)

```
apt update
apt install -y build-essential libpq-dev postgresql postgresql-contrib \
  nginx jq curl python3 git

# Stack (GHC)
curl -sSL https://get.haskellstack.org/ | sh

# Elm 0.19.1 + elm-test
apt install -y npm
npm install -g elm@latest-0.19.1 elm-test

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

```
cp /root/greppit/deploy/greppit-backend.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now greppit-backend
systemctl status greppit-backend         # active (running)
journalctl -u greppit-backend -f         # tail logs (Ctrl-C to stop)
```

From here on, restart the backend with `systemctl restart greppit-backend`,
not with `scripts/restart.sh`.

## Phase 7 — nginx

```
cp /root/greppit/deploy/nginx/greppit.app.conf /etc/nginx/sites-available/
ln -s /etc/nginx/sites-available/greppit.app.conf /etc/nginx/sites-enabled/
nginx -t
systemctl reload nginx
```

If `nginx -t` complains about the TLS cert files, do Phase 8 first then
come back.

## Phase 8 — TLS cert (Cloudflare Origin, simplest)

1. Cloudflare dashboard → greppit.app → SSL/TLS → Origin Server →
   **Create Certificate**.
2. Key type: RSA (2048). Hostnames: `greppit.app, *.greppit.app`.
   Validity: 15 years.
3. Cloudflare shows two blobs (cert + private key). Save them:

```
mkdir -p /etc/ssl/greppit && chmod 700 /etc/ssl/greppit
# paste CF's "Origin Certificate" into:
vim /etc/ssl/greppit/origin.pem
# paste CF's private key into:
vim /etc/ssl/greppit/origin.key
chmod 600 /etc/ssl/greppit/origin.key
nginx -t && systemctl reload nginx
```

## Phase 9 — Cloudflare DNS + SSL mode

- DNS → add `A` record `greppit.app → <droplet IP>`, **proxied** (orange cloud).
  Same for `www` if you want it to resolve.
- SSL/TLS → Overview → **Full (strict)**. This requires the origin cert
  from Phase 8. Never use "Flexible" — it's plaintext between Cloudflare
  and your droplet.
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
- **Backend update:** pull on the server, `cd backend && stack build`,
  then `systemctl restart greppit-backend`.
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
- Rate-limit `/api/auth/*` in nginx to slow brute-force login attempts.
- Add a real logging / metrics pipeline (journald + Grafana Loki is
  lightweight; Honeycomb or equivalent if you want tracing later).
- `fail2ban` for ssh + nginx.
