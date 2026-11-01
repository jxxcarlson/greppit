# Changelog

## 2026-11-01 — pdfServer security fixes, and a log review of rose

pdfServer (pdfserv.app) compiles LaTeX and renders TikZ for anyone on
the internet, and it has real users besides James: about a dozen
countries in rose's logs, mostly `/tikz2png`. It ran as root.

### Log review on rose: no sign of a break-in

Logs available: auth.log from Oct 11, pdfServer's journal from Sep 4,
and nginx for two weeks.

- **Logins:**
  - all 151 SSH logins used this Mac's key (`carlson@jxxM3.local`);
    the other eight keys, `zarak@hey.com` included, were never used;
  - 441,389 failed password guesses, which can't succeed now that SSH is
    key-only.
- **Scanner traffic:** probes with `file:///root/.ssh/id_rsa`,
  cloud-metadata URLs and so on went to paths pdfServer doesn't have
  (`/fetch`, `/proxy`, `/__vite_rsc_findSourceMapURL`, ...). All got
  404, and nothing was fetched.
- **pdfServer's own records:**
  - the 162 saved LaTeX inputs contain nothing hostile; the only "hits"
    were pdfServer's own `\graphicspath`;
  - images were downloaded only from `imagedelivery.net`;
  - document names were ordinary.
- **The system:**
  - no new accounts (`jxx` unused since 2020);
  - nothing in temp folders, no unusual processes, no suspicious shell
    history;
  - the October 25 changes (nmap snap, BBR tuning, scripta's nginx site)
    look like a deliberate work session; James to confirm.
- **Can't be verified:** `/tikz2png` input isn't kept anywhere, and older
  logs are gone.

### Flaws found and fixed

pdfServer2 commits `7cf920e` and `901f3ac`; the full write-up is in the
`7cf920e` commit message.

1. **Shell injection, run as root.** The document id, image file names,
   package names and image URLs went into `system` commands. Even an
   `\includegraphics{http://..."$(cmd)"}` inside the LaTeX ran `cmd`.
   - New `Safe.hs`: names are reduced to `[A-Za-z0-9._-]`, and every
     request body is cleaned on arrival.
   - Downloads use `curl` with an argument list, no shell.
2. **Path traversal.** An id like `../../etc/cron.d/x` wrote anywhere.
   Names are cleaned now, and `GET /pdf/:id` and `/tar/:id` refuse
   unsafe names.
3. **LaTeX reading any file**, e.g. `\input{/root/scripta-app-v4/.env}`,
   which holds the Stripe keys.
   - The server sets `openin_any=p`, `openout_any=p`, `shell_escape=f`
     and `TEXMFOUTPUT=<its folder>`.
   - Every TeX run has `-no-shell-escape`.
4. **Fetching any URL** (SSRF), including `file://` and the metadata
   service. Only public `http(s)` addresses are fetched now: the host is
   checked, curl is pinned to the checked address, and there are no
   redirects, plus time and size limits.
5. **Running as root.** pdfServer now runs as the system user
   `pdfserver`, with `ProtectSystem=strict`, `ProtectHome=read-only`,
   `NoNewPrivileges`, `PrivateTmp`, no capabilities, and write access
   only to its working folders. The old unit is in
   `/root/migration-backups/pdfServer.service.before-hardening`.
6. **No rate limit.** nginx now allows pdfserv.app 30 requests a minute
   per client (burst 30, then 429). Checked: 60 parallel requests got 55
   429s.

### Checks

- `deploy/security-test.py` in pdfServer2 (26 checks) passes on the live
  server.
- 25 real saved documents compiled with the same results before and
  after.

Also on rose2: `/root/.stack/config.yaml` now has `system-ghc: true`, so
plain `stack build` (pdfServer's `deploy.sh`) uses ghcup's GHC.

## 2026-11-01 — Everything moved from rose to rose2 (Ubuntu 24.04)

The plan, with progress notes:
`docs/superpowers/specs/2026-11-01-server-migration-design.md`.

### The new droplet

**rose2** (`147.182.143.224`) is a DigitalOcean NYC1 droplet: Ubuntu
24.04.5, 4 vCPU, 8 GB, 160 GB, Basic plan, with weekly DigitalOcean
backups and the metrics agent.

**Set up with:**
- key-only root SSH (`/etc/ssh/sshd_config.d/00-hardening.conf`), with
  only this Mac's key authorized;
- ufw allowing 22, 80 and 443;
- Postgres 16, nginx 1.24, certbot 2.9;
- 4 GB of swap;
- TeX Live 2023, poppler-utils and ghostscript;
- Node 18;
- ghcup with GHC 9.4.7, 9.6.6 and 9.6.7, cabal 3.16 and Stack 3.11;
- Elm 0.19.2;
- `/root` set to 711, so nginx can reach the frontends.

OpenSSH 9.6 means no more post-quantum warning. `/etc/letsencrypt` was
copied from rose, and `certbot renew --dry-run` passes for all five
domains.

### How each app moved

Each app was built and tested on rose2 first. At switch-over it was
stopped (and disabled) on rose, its database was dumped and restored,
and its DNS record was changed. Row counts matched for every table in
every database.

| App | Site | Notes |
|---|---|---|
| greppit | greppit.app | Built with `stack --system-ghc`. 97 snippets. www.greppit.app got its first DNS record (a CNAME). |
| cloudelog | cloudelog.app | Frontend copied as built on rose. 67 entries, 8 users. |
| pdfServer | pdfserv.app | The live program was the `pdfServer2` checkout (`master`, `lts-22.44`, GHC 9.6.7), not the `V3` code beside it. Same version, `c2f9a74`, on both servers. **Its DNS is at Squarespace Domains** (formerly Google Domains), not Cloudflare. |
| scripta | x-scripta.app | Built with GHC 9.4.7 + cabal, pinned to rose's exact versions in `cabal.project.production` (scripta-app-v4 `696f87d`). 19 tables matched. The domain is DNS-only. |
| kv-store | dataserv.app | Copied, NOT started, as on rose. Now proxied, with SSL/TLS mode Full (strict); "Flexible" caused a redirect loop. The domain expires 2026-12-10. |

Left behind on purpose: the `forscotty` database, shoobox.io, and
leftover folders (analyticsServer, docserver, file_server, xnginx,
dataServer).

### Found and fixed along the way

- **Postgres trusted every local connection on rose.** Its `pg_hba.conf`
  had `host all all 127.0.0.1/32 trust`: any local connection got in
  with no password, as any user, including the superuser `root` that
  scripta connected as.
  - On rose2, scripta connects as a non-superuser `root` role that owns
    `scripta_v4`, using peer authentication over the local socket. Its
    `.env` says `DATABASE_URL=postgresql:///scripta_v4?host=/var/run/postgresql`.
  - The original `.env` is in `/root/migration-backups/`.
- **rose2 had no GitHub access.** rose pulled with a key on James's
  GitHub account, so deploys on rose2 would have failed. rose2 now has
  its own key, `root@rose2`, also on that account. GitHub's host key
  was checked against its published fingerprint.
- **Deploy scripts pointed at rose.** They now point at rose2 in
  scripta-app-v4 (`7610d7d`; `prod-update.sh` now requires hostname
  `rose2`), cloudelog (`538a887`), pdfServer2 (`6e8b757`) and greppit
  (`4ec46ef`).
  - On rose2, `/usr/local/bin/elm-0.19.2` links to Elm, for scripta's
    `prod-restart.sh --frontend`.
- **`deploy/README.md`** now describes rose2 and the 24.04 setup.

### Still to do

- ~~Stop and disable pdfServer on rose.~~ Done at 19:51 UTC: its last
  request had been at 19:11. Only nginx still runs on rose, and no app is
  left there.
- After a few days of everything running well:
  - delete rose and its snapshot `rose-1793510599494`;
  - remove rose's key (`root@rose`, `SHA256:m9mhDSUd…`) from GitHub.
- cloudelog's frontend commit `d6ea514` is still undeployed, by choice.

## 2026-11-01 — Droplet security updates (Ubuntu Pro)

Item 4 in `docs/security-remaining-tasks.md` (finding 8). Done on the
droplet (rose, 161.35.125.40); there are no code changes.

- **Problem:** rose runs Ubuntu 18.04.6, whose free security updates ended
  in May 2023. Its kernel, OpenSSH, OpenSSL, nginx and Postgres were no
  longer getting fixes. The server had been up 186 days on kernel
  `4.15.0-213`.
- **Fix:** attached a free personal Ubuntu Pro subscription
  (`pro attach`, token from ubuntu.com/pro/dashboard). That turns on
  `esm-infra` and `esm-apps`, which bring security updates for 18.04
  until 2028. Livepatch is enabled too: it applies many kernel fixes
  without a reboot.
- **Steps:**
  1. Took a DigitalOcean snapshot, `rose-1793510599494`. Delete it after a
     few days if all is well; snapshots are billed.
  2. Ran `apt-get upgrade` in a `screen` session. It updated 267
     packages, 263 of them security fixes: OpenSSL, OpenSSH, nginx,
     Postgres 10 and others. It ran with `--force-confold`, so every
     existing config file was kept (nginx, sshd, Postgres).
  3. Rebooted.
  4. Ran `apt-get dist-upgrade` for the 11 packages `upgrade` holds back,
     including the new kernel, then rebooted again.
- **Result:**
  - The droplet runs kernel `4.15.0-261`, with nothing left to install.
  - Every service is `active`: ssh, nginx, postgresql@10-main,
    greppit-backend, scripta-backend, cloudelog-backend and pdfServer.
    They're all boot-enabled systemd services, which was checked before
    rebooting.
  - greppit.app, x-scripta.app and cloudelog.app answer normally.
  - SSH is still key-only, and the nginx security headers are still in
    place.
- **Still to know:**
  - The "post-quantum key exchange" SSH warning remains: OpenSSH 7.6
    can't do it. It goes away only on Ubuntu 22.04 or later.
  - `apt-get update` reports a 404 for `apt.postgresql.org … bionic-pgdg`:
    PostgreSQL's own repository dropped 18.04. Postgres 10 comes from
    Ubuntu, with updates through Pro, so this is harmless. Disable it by
    renaming `/etc/apt/sources.list.d/pgdg.list` to `pgdg.list.disabled`.
  - The long-term fix is still a new Ubuntu 24.04 droplet, moving the
    apps across one at a time and switching each domain's DNS in
    Cloudflare.
- **Unrelated:** scripta.io returned Cloudflare's 522 (can't reach the
  origin). It's a Lamdera app, not hosted on this droplet.

## 2026-10-31 — Security headers and a required JWT secret

Items 2 and 3 in `docs/security-remaining-tasks.md` (findings 2 and 5 in
`docs/security-fixes-to-do.md`). Branches `fix/jwt-secret-check`
(`c9c55f5`) and `feat/security-headers`, both merged into `main`.

### JWT secret check

- **Change:** the backend refuses to start if `JWT_SECRET` is missing,
  shorter than 32 bytes, or the old published default. It exits with a
  message saying how to generate one (`openssl rand -base64 48`).
  Before, a missing secret silently fell back to that default, which
  anyone could have used to sign valid tokens.
- **Code:** `Config.validateJwtSecret` in `backend/src/Config.hs`, used
  by `loadConfig`.
- **Tests:** `backend/test/ConfigSpec.hs`, 5 cases; all 46 backend tests
  pass. The real binary refuses a missing or short secret.
- **Production:** the droplet's 64-character secret passes, so logins
  aren't affected.
- **Local development:** a secret is now required locally too.
  - A generated one was added to the local `.env`.
  - `README.md`, `backend/README.md` and `.env.example` now say it's
    required.
  - Local logins signed with the old default stop working, so sign in
    again once.

### Security headers

- **Page policy:** `frontend/index.html` has a Content-Security-Policy
  `<meta>` tag.
  - **Scripts:** only from greppit, esm.sh and jsdelivr, plus the
    import map, allowed by its SHA-256 hash. Inline scripts and
    `javascript:` links are blocked, even if a renderer lets one
    through.
  - **Styles:** inline styles stay allowed (Elm, KaTeX and CodeMirror
    use them).
  - **Frames and media:** `https:` is allowed, for Scripta's `| iframe`.
  - **Connections:** greppit itself, plus `localhost:8085` for
    development.
- **Start-up script moved:** from `index.html` to `frontend/app.js`, so
  editing it can't break the policy.
- **Import map catch:** after any change to the import map, run
  `python3 scripts/csp-hash.py`. It says whether the hash in the policy
  still matches and prints the new one. A stale hash stops CodeMirror
  from loading.
- **Server headers:** `deploy/nginx/add-security-headers.sh` installs
  `/etc/nginx/snippets/greppit-security-headers.conf` (same as
  `deploy/nginx/greppit-security-headers.conf`):
  - `Strict-Transport-Security`: browsers always use HTTPS;
  - `X-Content-Type-Options: nosniff`: no guessing at file types;
  - `X-Frame-Options: DENY` and `frame-ancestors 'none'`: no framing by
    other sites (clickjacking);
  - `Referrer-Policy: strict-origin-when-cross-origin`.

  nginx drops inherited `add_header` lines in a location that has its
  own, so the snippet is included in the server block and in each
  no-cache location. `/app.js` also gets `no-cache`. The same changes
  are in `deploy/nginx/greppit.app.conf`.
- **Checked locally in Chrome:**
  - Elm, KaTeX math, the CodeMirror editor and backend calls work, with
    no policy errors.
  - An injected `javascript:` link and an injected inline script were
    both blocked.
  - The nginx edit was dry-run on a copy of the installed config.
- **Note:** the local backend stopped during testing, possibly because
  of a cleanup command. It was restarted with the new local secret.

### Deployed 2026-11-01 (UTC)

- **Frontend:** pulled and rebuilt on the droplet.
- **Headers:** `deploy/nginx/add-security-headers.sh` was run on the
  droplet (backup in `/root/nginx-backups/`). All five headers are on
  `/`, `/elm.js`, `/app.js` and `/api/`.
- **Backend:** `stack install` succeeded, but the service then failed
  with "Address already in use". Port 8086 was held by a backend started
  by hand on **2026-06-11** from `.stack-work` (an old SSH session's
  process, not the systemd service). So production had been running
  that June build all along, and earlier backend deploys hadn't taken
  effect. The fix: that process was stopped, and `greppit-backend` was
  started under systemd, running `/usr/local/bin/greppit-backend`.
  - The only backend commit since June is the JWT check above, and
    production's database already has migrations 001–003, so the new
    binary matches it.
  - After a backend deploy, check that `systemctl is-active
    greppit-backend` says `active`. `/api/health` answering isn't
    enough: a stray process can answer it.
- **Checked on greppit.app in Chrome:** still signed in (same secret),
  96 snippets listed, KaTeX math and CodeMirror work, a `javascript:`
  link is blocked, and there are no policy errors in the console.

## 2026-10-31 — Rate limit on login and signup

Finding 4 in `docs/security-fixes-to-do.md`.

- **Change:** nginx now limits `/api/auth/` (login, signup, me) to 5
  requests a minute per client, after a burst of 5. Over the limit, the
  answer is 429 Too Many Requests. Other API routes are not limited.
- **Client address:** behind Cloudflare, nginx's `$remote_addr` is
  Cloudflare's, so the limit is keyed on the `CF-Connecting-IP` header.
  Requests without that header (straight to the droplet) are keyed on
  the connecting address, so they're limited too.
- **Files:**
  - `deploy/nginx/add-auth-ratelimit.sh`: adds the limit to the
    installed config in place, keeping certbot's HTTPS section. It backs
    up the config first, and restores the backup if `nginx -t` fails.
    Run with `ssh root@161.35.125.40 'bash -s' < deploy/nginx/add-auth-ratelimit.sh`.
    It reads and writes UTF-8 explicitly: the droplet's Python 3.6
    defaults to ASCII and failed on a "→" in the config's comments.
  - `deploy/nginx/greppit.app.conf`: the same block, for fresh installs.
- **Applied** on the droplet 2026-10-31 (backup in `/root/nginx-backups/`).
  Checked: 12 quick bad logins gave six 401s, then six 429s; `/api/health`
  and `/api/snippets` answer as before.

## 2026-10-31 — Fix: math could inject links, styles and images

Branch `fix/katex-trust`. Finding 1 in `docs/security-fixes-to-do.md`.

- **Problem:** `<math-text>` in `frontend/index.html` ran KaTeX with
  `trust: true` and put its output in with `innerHTML`, outside Elm's
  protection. Math in a snippet could make a `javascript:` link (which
  can read the login token), a full-page overlay (`\htmlStyle`), or an
  image from any server (`\includegraphics`).
- **Fix:**
  - `katexTrust` allows only `\href` and `\url`, and only to `http`,
    `https` or `mailto`. Anything else renders as red source text.
    Neither compiler sends other trusted commands to KaTeX; Scripta uses
    `\href` and `\includegraphics` only in its LaTeX export.
  - KaTeX 0.16.9 → 0.16.47, the newest 0.16 release, which includes the
    fixes for the 0.16.9 advisories. 0.19 was not taken, to avoid
    rendering changes.
  - The KaTeX CSS, JS and mhchem files carry `integrity` hashes, so a
    changed file on jsdelivr is refused. A version bump needs new hashes.
  - A KaTeX error message is shown with `textContent`, not `innerHTML`.
- **Checked in Chrome:**
  - KaTeX 0.16.47 loads with no integrity or console errors.
  - `javascript:` links (any letter case), `\htmlStyle` and
    `\includegraphics` are refused; an `https` link works.
  - HTML in the math source is not injected.
  - In a temporary Markdown snippet (since deleted), a fraction, `\ce{H2O}`
    and a display integral render, and so does the Scripta property path.

## 2026-10-31 — Remember the last markup language

Branch `feat/remember-language`.

- **What it does:** New snippet starts in the language you last picked
  in the editor's language menu. The choice survives reloads and
  signing out. The very first time, it's Markdown (xmarkdown).
- **Code:**
  - `Model.currentLanguage` in `frontend/src/Types.elm`.
  - `emptyEditor` in `frontend/src/Main.elm` now takes the language.
    `EditorMarkupChanged` updates `currentLanguage` and calls the new
    `saveLanguage` port.
  - `frontend/index.html` stores the language in localStorage under
    `greppit-language` and passes it to Elm as the `initialLanguage`
    flag. An unknown or missing value falls back to Markdown.
- **Per browser:** the choice is kept in this browser only, not on the
  server.
- **Checked in Chrome:** with nothing stored, New snippet started in
  Markdown. After switching to Scripta, the next New snippet started in
  Scripta, and it still did after a reload. The test value was cleared
  afterwards.

## 2026-10-30 — Fix: duplicate title for Scripta snippets

Branch `fix/scripta-title-header`.

- **Symptom:** a Scripta snippet that starts with a `| title` block showed
  its title twice in the reader: greppit's header (the snippet's Title
  field) and then the compiler's title.
- **Fix:** the source's title wins. The reader header now leaves out the
  snippet title whenever the body supplies one. The check is
  `Render.hasSourceTitle`:
  - Scripta asks the compiler (`Scripta.Document.title`, the text of the
    `| title` block).
  - Markdown uses the existing `%title` rule.
  - Plain text never has a source title.
- **Tests:** `tests/MarkdownTitleTests.elm` became
  `tests/SourceTitleTests.elm`, with Scripta and plain-text cases added.
- **Checked in Chrome** with a temporary Scripta snippet (since deleted):
  no header title, and "Good Podcasts!" shows once. A Scripta snippet
  without a title block still shows its header title.

## 2026-10-30 — Markdown from the xmarkdown-compiler package

Branch `feat/xmarkdown-package`.

- **Change:** Markdown is now compiled by
  [`jxxcarlson/xmarkdown-compiler`](https://package.elm-lang.org/packages/jxxcarlson/xmarkdown-compiler/latest/)
  instead of the vendored `elm-markdown/`, which is deleted. The reader's
  table of contents now comes from the compiler. Its `SelectId` events
  become `ScrollToHeading`. greppit's own heading/TOC code in
  `src/Render.elm` and its test (`MarkdownTocTests`) are gone.
- **Math:** XMarkdown passes math as `data-content` / `data-display`
  attributes, so `<math-text>` in `index.html` now reads those as well as
  the properties the Scripta compiler sets.
- **Title blocks:** a Markdown snippet that starts with a title block
  (`%title`, `%author`, `%date`) gets its title from the compiler, so the
  reader no longer shows the snippet title above it. Without a `%title`,
  the header is unchanged. The check is `Render.hasMarkdownTitle`, tested
  in `tests/MarkdownTitleTests.elm`.
- **`elm.json`:** added the package and `avh4/elm-color`. `elm/regex`
  moved to indirect.
- **Version:** uses xmarkdown 2.2.5. 2.2.4 made paragraphs and lists fit
  panes narrower than 700px. 2.2.5 made a title block count only at the
  start of a document.
- **Checked in Chrome** against the published 2.2.5: the reader and the
  editor preview fit their panes, TOC clicks scroll, a leading title
  block replaces the header title, and a `%title` block later in the
  document renders nothing.

## 2026-10-30 — Scripta from the published package

Branch `feat/scripta-package`.

- **Change:** Scripta is now compiled by the published
  [`jxxcarlson/scripta-compiler-v3`](https://package.elm-lang.org/packages/jxxcarlson/scripta-compiler-v3/latest/)
  package (1.0.1) instead of the copy vendored into `frontend/scripta/`
  on 2026-06-11, which had fallen behind upstream. The vendored directory
  is deleted and `scripta` is gone from `source-directories`.
- **Code:** no source changes. `src/Render.elm` and
  `tests/ScriptaRenderTests.elm` only use the public `Scripta` API, and
  the package exposes the same functions.
- **`elm.json`:** added the package (which brings `jxxcarlson/etex` and
  `elmcraft/core-extra`). Seven dependencies greppit's own code doesn't
  import moved from direct to indirect, because the package still needs
  them: list-extra, maybe-extra, result-extra, maca/elm-rose-tree,
  elm-syntax-highlight, toastal/either, elm/parser.
  `zwilias/elm-rosetree` was removed; nothing uses it.
- **Checked:** the app builds with `--optimize`, and the test modules
  compile. In Chrome, the existing Scripta snippets render. A sample with
  sections, a list, and inline and display math rendered in the editor
  preview: H2/H3 headings, two list items, KaTeX math.
- **Open question:** the "Test" snippet's first line, `| Test (foo)`,
  renders as `[Test]`. This wasn't compared against the vendored
  version.

## 2026-10-30 — Save before switching snippets

Branch `feat/save-before-switch`.

- **What it does:** if you're editing and click another snippet in the
  list, or press New snippet, your unsaved changes are saved first. The
  switch happens once that save succeeds. This also covers a save that
  was already running when you clicked.
- **If the save fails:** you stay in the editor, the status line shows
  the error, and nothing is lost.
- **Fixed along the way:** pressing New snippet while on a new snippet
  used to keep the old text in CodeMirror, because both editors had the
  key `"new"`. Each new-snippet editor now gets its own key.
- **Code:** `saveBeforeLeaving`, `performNav` and `startAutoSave` in
  `frontend/src/Main.elm`; `PendingNav` and `editorSeq` in
  `frontend/src/Types.elm`.
- **Checked in Chrome** (with temporary snippets, since deleted): new
  snippet then list click; new snippet then New snippet; edit an existing
  snippet then list click. Each time the switch happened before
  auto-save's 2 seconds were up, and the server had the right text with
  no duplicates. The save-failure path was not exercised.

## 2026-10-30 — Fix: editor pane empty (CodeMirror failed to load)

Branch `fix/codemirror-esm-lezer`, also cherry-picked onto
`chore/elm-0.19.2`.

- **Symptom:** you couldn't type in a new snippet, and an existing
  snippet showed its rendered preview but no source.
- **Cause:** esm.sh's build of `@codemirror/commands@6.3.3` pulled in its
  own copy of `@lezer/common@^1.1.0`. esm.sh can't build that copy: it
  returns a 500 error ("no space left on device"). The failure spread:
  `commands` failed, then the `codemirror` bundle, then
  `codemirror-element.js`. So `<codemirror-editor>` was never defined.
  This was unrelated to auto-save and to Elm 0.19.2.
- **Fix:** `frontend/index.html` now lists `@lezer/common` as external
  for `@codemirror/commands`, so it uses the import map's copy (1.2.1),
  the same as the other CodeMirror packages. Checked in Chrome: the
  editor loads, existing snippets show their source, and new snippets
  are editable.
- **Note:** browsers may keep the old `index.html` cached. Do a hard
  reload (⇧⌘R) after deploying.

## 2026-10-30 — Build with Elm 0.19.2

Branch `chore/elm-0.19.2`. The frontend now targets Elm 0.19.2, the
version installed at `/usr/local/bin/elm`.

- `frontend/elm.json`: `elm-version` changed from 0.19.1 to 0.19.2. No
  source or dependency changes were needed: all 64 modules build with
  `--optimize`, and the test modules compile.
- `README.md`, `frontend/README.md`, `deploy/README.md`: prerequisites
  now say 0.19.2. The droplet setup installs it with
  `npm install -g elm@latest-0.19.2`.
- **On the droplet:** before the next frontend deploy, install 0.19.2
  there as well, or `elm make` will refuse the new `elm.json`.

## 2026-10-30 — Editor auto-save

Commit `9e4ae1a`. Merged into `main` 2026-10-30. Tested in the browser locally. Unit tests compile but have not been run.

**What it does**

- **When it saves:** any change to title, tags, markup or body starts a 2-second countdown, and each new change restarts it. When the countdown ends, the snippet is saved and you stay in the editor. A new snippet is created on its first save, and later saves update it. A brand-new snippet with no title and no body is never saved.
- **Status line:** a small line next to the buttons says "Saving…", "Saved", "Unsaved changes", or "Auto-save failed: …".
- **Save button:** works as before: it saves and goes back to the reading view.
- **Cancel is now Close:** with auto-save, Cancel could no longer undo anything. If you press Close within those 2 seconds, it saves the pending changes before closing.
- **No editor jumps:** the editor's key and starting text are fixed when it opens, so a save doesn't reload it or move your cursor.
- **Lists stay current:** the results list updates after each save. If you close the editor while a save is still running, the snippet on screen updates when that save finishes.
- **One save at a time:** Save, Close, Export and Delete are greyed out while an auto-save is running, so you can't create a duplicate. Changes made during a save are picked up right after it.

**Where the code is**

- `frontend/src/Main.elm`: the `AutoSaveTick` / `AutoSaveResponded` handlers and the `editorChanged` and `closeEditor` helpers.
- `frontend/src/Types.elm`: the new `EditorState` fields.
- `frontend/src/Editor.elm`: the status line (`autoSaveStatus`).

**Things to know**

- **Compiler version:** `/usr/local/bin/elm` is now 0.19.2, which rejects this project's `elm.json` (0.19.1). So `./scripts/restart.sh` fails at the `elm make` step. Build with `~/.elm/elm-tooling/elm/0.19.1/elm` instead. (Resolved by the Elm 0.19.2 entry above.)
- **Tests not run:** the sandbox blocked elm-test, so the suite hasn't been run. To run it: `cd frontend && elm-test`
- **Process:** the usual spec and plan were skipped at the user's request.
