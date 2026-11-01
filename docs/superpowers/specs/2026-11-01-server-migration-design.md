# Moving rose to a new Ubuntu 24.04 droplet

Design, 2026-11-01. Status: agreed in chat; work starts when James says
so (around 2026-11-02 or 11-03).

## Why

The droplet **rose** (161.35.125.40, DigitalOcean NYC1) runs Ubuntu
18.04.6. Its standard support ended in 2023. Ubuntu Pro now provides
security updates until 2028 (see `docs/changelog.md`, 2026-11-01), but
the system is still old:

- OpenSSH 7.6: no post-quantum key exchange, so every login warns.
- Postgres 10, Python 3.6 and Node 16.
- PostgreSQL's own apt repository has dropped 18.04.

The fix is a fresh Ubuntu 24.04 droplet with everything moved across.

## Who it's for

Only James uses these apps, so a few minutes of downtime per app during
its switch-over is fine.

## What moves

| Site | App (repo) | Port | Database | Notes |
|---|---|---|---|---|
| greppit.app (+ www) | greppit (`jxxcarlson/greppit`) | 8086 | `greppit_prod` (8 MB) | setup written up in `deploy/README.md` |
| x-scripta.app | scripta-app-v4 (`jxxcarlson/scripta-app-v4`) | 8085 | `scripta_v4` (123 MB) | nginx proxies `/api/` and a websocket at `/ws` |
| cloudelog.app | cloudelog (`jxxcarlson/cloudelog`) | 8087 | `cloudelog_prod` (8 MB) | |
| pdfserv.app | pdfServer (`jxxcarlson/pdfServer2`) | 3000 | none | needs TeX Live: pdflatex, xelatex, lualatex (11 texlive packages on rose); one nginx path proxies to 3001 |
| dataserv.app | kv-store-app (`jxxcarlson/-kv-store-app`) | 3001 | `kvstore` (19 MB) | **moves as it is today: code, database and nginx site copied, app NOT started.** It isn't running on rose either. As today, its nginx site stays enabled, with its certificate: the static frontend is served and `/api/` gives 502. Its DNS moves to the new server like the others (Claude's call, matching today). |

For each app that runs, move:

- the code and built program;
- the frontend files nginx serves;
- the database;
- the `.env` secrets;
- the nginx site;
- the HTTPS certificate;
- the systemd service;
- the nightly 3 a.m. database dump with 14-day cleanup (greppit, scripta
  and cloudelog have one; see root's crontab on rose).

The services run binaries from these paths:

- greppit: `/usr/local/bin/greppit-backend`
- cloudelog: `/usr/local/bin/cloudelog-backend`
- scripta: `/root/scripta-app-v4/backend/scripta-backend.bin`
- pdfServer: `/root/pdfServer/pdfServer`

## Which code to build (checked on rose, 2026-11-01)

"Behaves as it does today" means building exactly what rose runs:

- **greppit, scripta-app-v4:** rose is one commit behind GitHub `main`,
  and that commit is docs only. Either is fine.
- **cloudelog:** rose runs one commit behind `main`. Build what rose
  runs. Origin's `d6ea514` ("frontend: add per-metric Total and Avg")
  isn't deployed; deploy it after the move, not during. rose also has
  one uncommitted change, `db/schema.sql`, which looks like a
  regenerated schema file. Copy it across as it is.
- **pdfServer:** branch `V3` in `/root/pdfServer`, with
  `/root/pdfServer/pdfServer2` on `master`. Both match origin.
- **kv-store-app:** matches origin.
- **Getting the code (Claude's call):** copy the working trees from rose
  with `rsync`, leaving out `.stack-work`, `elm-stuff` and
  `node_modules`. This keeps each checkout's exact commit and local
  changes, and the new droplet needs no GitHub credentials.
- **Code changes forced by GHC, libpq or Postgres (Claude's call):**
  commit them on a branch in the app's repo and push, so the repo stays
  the source of truth.

## Facts checked on rose

- **Apps calling each other:** no app's `.env` points at another app.
  The `localhost:8085` / `localhost:3000` strings are in the frontends'
  development defaults. So the apps can move in any order.
- **IPv6:** rose has no global IPv6 address, so no AAAA records can point
  at it. Cloudflare's own AAAA records for proxied hostnames are
  Cloudflare's, and follow the A record.
- **pdfserv.app `/a/`:** this path proxies to 3001 (kv-store), which is
  stopped, so it's dead today. Copy it as it is.

## What stays behind (James's call)

- the `forscotty` database;
- anything to do with shoobox.io (rose has a certificate for it, but no
  site);
- leftover folders: `analyticsServer`, `docserver`, `file_server`,
  `xnginx`, `dataServer/snap-server`.

## The new server

- **Droplet:** Ubuntu 24.04 LTS, NYC1, Basic 2 CPUs / 8 GB, the same as
  rose. James creates it, with this Mac's SSH key
  (`carlson@jxxM3.local`, SHA256:FLVdx44U…), and sends the IP address.
- **Safeguards from rose, carried over:**
  - key-only root SSH (`PermitRootLogin prohibit-password`,
    `PasswordAuthentication no`);
  - ufw allowing only 22, 80 and 443;
  - the greppit nginx no-cache rules, `/api/auth/` rate limit and
    security-headers snippet (`deploy/nginx/`);
  - `.env` files mode 600.
- **Software:** Postgres from Ubuntu 24.04 (16), nginx, certbot, Stack /
  GHC for the Haskell apps, Elm 0.19.2 for greppit's frontend, TeX Live
  for pdfServer.
- **Backend addresses:** bind the backends to 127.0.0.1 where the app
  allows it; on rose they listen on all addresses.

## How each app switches (one at a time)

Order: greppit first (best documented), then cloudelog, pdfServer and
scripta. kv-store's files and database can come over at any point.

1. **Prepare:** on the new server, build and configure the app, and
   start it on its port. Test it locally there (`curl` with the right
   `Host`, or `--resolve`) before any real traffic arrives.
2. **Move the data:** stop the app on rose, dump its database
   (`pg_dump --format=custom`), and restore it on the new server.
3. **Switch:** in Cloudflare, James first looks at the domain's full DNS
   list for anything else that points at 161.35.125.40. Then he changes
   every such A record (apex, `www` and any other) to the new IP.
   Proxying stays on.
4. **Check:** the site works through Cloudflare, logins work, and data is
   present. James also tries it in his browser.
5. **Rollback** if needed: point the DNS records back at rose and start
   the app there again. Writes made on the new server in between would
   have to be copied back by hand, which matters little with one user.

rose keeps running until every app has worked on the new server for a
while (James decides how long). James then deletes rose and its leftover
snapshots.

## Who does what

- **James:**
  - creates the droplet;
  - changes DNS records in Cloudflare;
  - tries each app in the browser;
  - deletes rose at the end;
  - runs any step that Claude Code's auto-mode safety check refuses to
    let Claude run. Alternatively, he turns auto mode off, so that
    Claude's commands come to him as permission prompts.
- **Claude:** everything on the servers (setup, builds, data moves,
  configs) and the checks.

## Success

- Every app listed above behaves as it does today; kv-store sits there,
  stopped.
- No data is lost: database row counts match before and after each move.
- The new server has current OpenSSH, Postgres and Python, gets standard
  Ubuntu security updates, and the post-quantum SSH warning is gone.
- The setup is written down well enough to repeat. That means updating
  `deploy/README.md` for greppit; the other apps' notes go in their own
  repos or in one migration doc.

## Not part of this

- Changing any app's behaviour or code, except what a newer Postgres,
  GHC or fresh build forces.
- Reviving kv-store / dataserv.app.
- Reviewing the security of the other apps.

## Left to the builder

- **Certificates:** copy `/etc/letsencrypt` from rose, or issue new
  ones after each switch. Either way, certbot renewal must work on the
  new server.
- **Build method:** build on the server, or copy binaries. On 24.04
  they'll almost certainly need a rebuild, because the glibc and
  libpq versions differ.
- **Swap:** rose has none. Adding some helps GHC builds on 8 GB.
- **Exact order of setup steps,** and how to script them.
- **Off-server backups:** settled. rose2 has DigitalOcean weekly backups
  turned on. A nightly copy of the dumps somewhere else can come later.

## Progress

- **2026-11-01:** rose2 created (147.182.143.224; Ubuntu 24.04.5; 4 vCPU,
  8 GB, 160 GB; weekly backups).
- **2026-11-01, base setup:**
  - key-only SSH, ufw, updates;
  - Postgres 16, nginx 1.24, certbot;
  - 4 GB swap, TeX Live 2023, Node 18;
  - ghcup with GHC 9.6.6, cabal 3.16 and Stack 3.11; Elm 0.19.2;
  - `/root` set to 711;
  - `/etc/letsencrypt` copied from rose.
- **2026-11-01, greppit moved:** its DNS points at rose2. The data was
  identical, 97 snippets. On rose, greppit is stopped and disabled.
  `www.greppit.app` got its first DNS record (a CNAME to greppit.app).
- **2026-11-01, cloudelog moved:**
  - Its DNS points at rose2; the data was identical (67 entries, 8 users).
  - On rose, cloudelog is stopped and disabled.
  - The frontend files were copied as built on rose.
  - The backend took about 2 minutes to build, since the libraries were
    already compiled.
- **2026-11-01, pdfServer moved:**
  - The live program was already a GHC 9.6 build: the `pdfServer2`
    checkout (master `e9f8bc2`, `lts-22.44`), installed by its
    `deploy.sh`. The `V3` checkout was a red herring.
  - It was built the same way on rose2. The version is `c2f9a74` on both,
    and a test PDF typesets.
  - **pdfserv.app's DNS is at Squarespace Domains** (formerly Google
    Domains), not Cloudflare. It isn't proxied, with a one-hour TTL.
  - Stop pdfServer on rose once old answers have expired.
- **Next:** scripta, then kv-store.
