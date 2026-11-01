# Security: remaining tasks

As of 2026-10-31. The full review, with what was found and what's
already fixed, is in `docs/security-fixes-to-do.md`.

Already done on 2026-10-31:
- math rendering (finding 1);
- rate limit on login and signup (finding 4);
- SSH key-only root login, with the authorized keys pruned to this Mac's
  (finding 7);
- jxxcarlson.org crawler trap (not a greppit finding).

## 1. `.env` readable by every account on the droplet

**Done** 2026-10-31: `chmod 600 /root/greppit/.env`, run by hand on the
droplet.

`/root/greppit/.env` holds `JWT_SECRET` and the database URL, and its
permissions are 644.

- **Fix:** a one-line change on the droplet:
  `chmod 600 /root/greppit/.env`. The backend runs as root, so it can
  still read the file.

## 2. No security headers (finding 2, medium)

**Done** 2026-10-31/11-01; see `docs/changelog.md`.

greppit.app sends no `Content-Security-Policy`,
`Strict-Transport-Security`, `X-Frame-Options` / `frame-ancestors`, or
`X-Content-Type-Options`.

- **Fix:** add them in nginx: HSTS, nosniff, `frame-ancestors 'none'`,
  and a Content-Security-Policy.
- **The hard part is the Content-Security-Policy.** It would also block
  greppit's own inline scripts (the import map and the start-up script
  in `frontend/index.html`) unless they are moved to a file or listed by
  hash, and a mistake there blanks the whole app. Its payoff is
  blocking `javascript:` links even if a renderer lets one through.

## 3. JWT secret falls back to a public default (finding 5, medium)

**Done** 2026-10-31/11-01; see `docs/changelog.md`.

`backend/src/Config.hs:27`: if `JWT_SECRET` is ever missing from `.env`,
the backend starts with the default secret, which is published in the
repo. Anyone could then create a valid login token for any user. The
droplet's secret is fine today (64 characters, not the default).

- **Fix:** refuse to start when `JWT_SECRET` is unset, equals the
  default, or is shorter than 32 bytes.

## 4. Ubuntu 18.04, past the end of standard support (finding 8, medium)

**Done for now** 2026-11-01: Ubuntu Pro attached, so security updates
run until 2028, and all packages and the kernel are updated (see
`docs/changelog.md`). The long-term fix, a new 24.04 droplet, is still
open.

Its free security updates ended in May 2023, so nginx, OpenSSH, OpenSSL
and the kernel no longer get fixes.

- **Fix:** turn on Ubuntu Pro (free for personal use), or move to a new
  24.04 droplet.
- **Moving is the larger job:** scripta, cloudelog and the PDF server
  also run there.

## 5. Scripts from outside servers (rest of finding 3, medium)

KaTeX is now pinned with integrity hashes. CodeMirror still comes from
esm.sh, which builds its files when they're requested, so a compromise
or broken build there runs in the page that holds the login token.

- **Fix:** serve the CodeMirror bundle from greppit.app itself.

## 6. Smaller items (finding 6, low)

- **CORS:** allows any origin (`backend/src/App.hs:54`). Restrict it to
  `https://greppit.app`.
- **Passwords:** signup accepts any password, including an empty one.
  Set a minimum length.
- **Account lookup:**
  - signup answers "email already registered";
  - a login with an unknown email returns faster, because it skips
    bcrypt.

  Both reveal which emails have accounts.
- **Tokens:** they last 7 days, there's no way to cancel one on the
  server, and they're stored in localStorage.
- **Cloudflare bypass:** `https://161.35.125.40/` answers directly,
  skipping Cloudflare. Limit ports 80 and 443 to Cloudflare's IP ranges.
- ~~**Root:** the backend runs as root.~~ Done 2026-11-01: greppit,
  cloudelog and scripta run as their own unprivileged users in a systemd
  sandbox (`deploy/run-backends-unprivileged.sh`). nginx still serves the
  frontends from under `/root` (711).
- **Backend port:** the backend listens on all addresses (8086). The
  firewall blocks it, but binding it to 127.0.0.1 wouldn't depend on the
  firewall.
- **fail2ban:** not installed, although `deploy/README.md` says it is.
  It matters little now that SSH passwords are off. Either install it or
  correct the README.

## pdfServer (pdfserv.app)

**Security flaws fixed** 2026-11-01; see `docs/changelog.md`. Still open,
with security first, then suggested improvements:

- **Cloudflare Images abuse:** `/image` and `/tikz2png` upload to James's
  Cloudflare Images account for anyone. The rate limit slows this. A real
  fix would be a check on the caller, for example the `Origin` of
  scripta's sites.
- **PDFs are public by name:** generated PDFs in `outbox/` can be fetched
  by anyone who knows or guesses the name. Random names or short-lived
  links would fix it.
- ~~**`save/` keeps a copy of every document anyone exports, forever.**~~
  Done 2026-11-01 (pdfServer2 `ff046b8`): copies are kept 7 days, which
  cut `save/` from 162 files to 2.
- ~~**Simultaneous requests clobber each other.**~~ Done 2026-11-01
  (pdfServer2 `ff046b8`): one LaTeX job runs at a time, under an MVar
  lock. A folder per request was the alternative, but paths, and
  scripta's own `\graphicspath`, are hard-wired to the shared folders.
  6 simultaneous exports went from 3/6 correct to 6/6.
- **Image URLs get mangled** when one image's name appears inside another
  URL. URLs are swapped for file names by plain text substitution, which
  shows in the logs as `…/image-1.jpgd7b724d-image-1.jpg…`.
- **Very chatty log:** `logStdoutDev` logs every request with its
  parameters (172,000 lines in two months). `logStdout`, or no request
  log, would do.
- **Port 3000 listens on all addresses.** The firewall blocks it, but
  binding to 127.0.0.1 wouldn't depend on that.
- **Small cleanups:** the `staticPolicy` middleware is added twice; the
  deprecated `param` should become `captureParam`; the `V3` checkout in
  `/root/pdfServer` is unused old code.

## Not reviewed

The droplet's firewall also opens 3000, 3001, 8080 and 8179 for the other
apps (scripta, cloudelog, the PDF server). Those apps weren't part of
this review.
