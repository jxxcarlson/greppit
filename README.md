# greppit

greppit is a personal snippet store with fast search. You sign in, write
short notes in Markdown, Scripta, or plain text, and find them again by
typing a few words.

- **Search:** results update as you type (200 ms debounce). Search is
  case-insensitive and matches all the terms you type, against title,
  tags, and body. Results are ordered newest first.
- **Rendering:** Markdown with KaTeX math, Scripta (via the vendored
  Scripta v3 compiler), and plain text.
- **Reader:** a three-column layout with a clickable table of contents
  built from the snippet's headings.
- **Editor:** a CodeMirror source pane next to a live preview, with
  auto-save, export to a text file, and delete.

Live at <https://greppit.app>.

## Architecture

| Part | Tech | Where | Dev port |
|------|------|-------|----------|
| Frontend | Elm 0.19.2 single-page app, CodeMirror 6 custom element, KaTeX | `frontend/` | 8011 |
| Backend | Haskell (Servant, Stack / GHC 9.6) JSON API, JWT auth | `backend/` | 8085 |
| Database | Postgres, migrations with dbmate | `backend/dbmate/migrations/` | — |

The frontend works out where the API is when the page loads. On
`localhost` / `127.0.0.1` it calls `http://localhost:8085`; anywhere else
it calls the page's own origin, where nginx proxies `/api` to the
backend.

More detail:

- [`backend/README.md`](backend/README.md): endpoints, environment variables, backend layout
- [`frontend/README.md`](frontend/README.md): frontend modules, auth, rendering, CodeMirror notes
- [`deploy/README.md`](deploy/README.md): the full production runbook
- [`docs/changelog.md`](docs/changelog.md): dated change notes

## Run locally

### Prerequisites

- Postgres (running locally)
- [`stack`](https://haskellstack.org) (pulls GHC 9.6 via `lts-22.43`)
- [`dbmate`](https://github.com/amacneil/dbmate)
- Elm **0.19.2** (`npm install -g elm@latest-0.19.2`), plus `elm-test`
  for the frontend tests
- Python 3 (dev static-file server)
- `jq` and `curl` (backend integration test)

> **Elm version:** `frontend/elm.json` pins 0.19.2, and Elm refuses to
> build a project pinned to a different version. Check with
> `elm --version` before building; `scripts/restart.sh` calls whatever
> `elm` is first on your PATH.

### One-time setup

```sh
createdb greppit_dev
./scripts/migrate.sh up
```

`migrate.sh` reads `DATABASE_URL` from `.env` or from your environment.
It defaults to `postgres://localhost/greppit_dev` and adds
`sslmode=disable` for local connections.

Optionally, create a `.env` in the repo root (it's git-ignored) for
settings specific to your machine:

```sh
DATABASE_URL=postgres://localhost/greppit_dev
GREPPIT_BACKEND_PORT=8085
GREPPIT_FRONTEND_PORT=8011
```

Avoid ports 8000–8010.

### Start everything

```sh
./scripts/restart.sh --all --opt
```

This builds the backend (`stack build`) and the frontend
(`elm make --optimize`), then starts both in the background. Open
<http://localhost:8011>, sign up with any email and password, and start
writing.

The `--opt` flag matters: the unoptimized Elm build is noticeably
sluggish when rendering Scripta.

Other modes:

```sh
./scripts/restart.sh --backend          # rebuild + run backend in the foreground
./scripts/restart.sh --frontend --opt   # rebuild + run frontend in the foreground
./scripts/stop.sh                       # stop both
```

### Tests

```sh
cd backend && stack test        # unit tests (Tags, Search, Auth)
bash backend/test-api.sh        # integration suite; needs the backend running
cd frontend && elm-test         # decoder, export, TOC, and Scripta render tests
```

## Deploy

Production is a single DigitalOcean droplet:

- **nginx** serves the static frontend (`index.html`, `elm.js`,
  `codemirror-element.js`) and proxies `/api` to the backend.
- **systemd** runs the backend binary (`deploy/greppit-backend.service`)
  from `/usr/local/bin/greppit-backend`, bound to `127.0.0.1`.
- **Postgres** runs on the same droplet.
- **TLS:** Let's Encrypt (certbot) on the droplet, with Cloudflare
  proxying in front in "Full (strict)" mode.

First-time setup of a new droplet (packages, Postgres user, `.env`,
systemd, nginx, certs, Cloudflare) is in
[`deploy/README.md`](deploy/README.md). For a server that's already set
up, ship an update like this:

```sh
ssh <droplet>
cd ~/greppit && git pull

# Schema change (if there's a new migration)
./scripts/migrate.sh up

# Backend change
cd backend && stack install --local-bin-path /usr/local/bin
systemctl restart greppit-backend

# Frontend change (no restart needed; nginx serves the new file)
cd ~/greppit/frontend && elm make src/Main.elm --optimize --output=elm.js
```

`stack build` alone does **not** update production. The service runs the
copy in `/usr/local/bin`, so you need `stack install` to refresh it.

Production `.env` needs at least `DATABASE_URL`, `PORT` /
`GREPPIT_BACKEND_PORT`, and a `JWT_SECRET` of 32 bytes or more
(`openssl rand -base64 48`). Never change `JWT_SECRET` after launch:
doing so invalidates every issued token.

### Backups

On the droplet, `scripts/db-dump-do.sh` writes a dump to
`~/greppit/backups/`. A suggested cron entry is
`0 3 * * * /root/greppit/scripts/db-dump-do.sh`.

On your Mac, `scripts/db-fetch-dump.sh` pulls the dumps down, and
`scripts/db-restore-local.sh` loads one into the local dev database.
Set `GREPPIT_PROD_HOST` and `GREPPIT_PROD_BACKUP_DIR` in your local
`.env` first.
