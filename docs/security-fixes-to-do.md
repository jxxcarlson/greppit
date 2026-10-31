# Security fixes to do

Security review of greppit.app, 2026-10-31.

greppit.app is in reasonable shape: no way was found for one user to read
another user's snippets, and no SQL injection. The most serious problem
is in how math is rendered, which can let a snippet run code in your
browser. There are also no security headers and no limit on login
attempts.

**Not checked:** the server-side settings. Read-only ssh commands on the
droplet (firewall, sshd settings, whether the JWT secret is the default)
were blocked by auto mode's safety check. The commands to run are in
"Server checks to run" below.

## What's solid

- **Database queries:** every query uses parameters, and every snippet
  query is limited to the logged-in user
  (`backend/src/Db/Snippet.hs:63,77,91,104`).
- **Search:** search terms have `%` and `_` escaped
  (`backend/src/Service/Search.hs:14`).
- **Passwords:** stored as bcrypt hashes.
- **Tokens:** a token with no signature (`alg: none`) is rejected, and
  requests without a token get 401.
- **Logs:** the config's `Show` instance hides the JWT secret.
- **Public files:** `.git`, `.env`, `src/` and `tests/` are blocked by
  nginx. `backups/` and `db/` only return the app's normal page
  (`index.html`), so their contents aren't public.
- **Backend port:** the backend port (8086) can't be reached from the
  internet.

## Findings, most serious first

### 1. High: math in a snippet can run code

`frontend/index.html:163-170`

- **Cause:** KaTeX runs with `trust: true`, and its output is written
  into the page with `innerHTML`, so Elm's own protection doesn't
  apply. Confirmed in Chrome on 2026-10-31 that greppit's settings allow:
  - `\href{javascript:…}{text}`, a link that runs code when clicked;
  - `\htmlStyle{position:fixed…}`, an overlay that can cover the whole
    page;
  - `\includegraphics{https://any-site/…}`, an image loaded from any
    server, which can be used for tracking.
- **Impact:** a click on such a link runs code that can read your token
  from localStorage, which means taking over the account. Today you only
  see your own snippets, so the risk is text pasted from elsewhere. It
  becomes serious if sharing or import is ever added.
- **Also:**
  - KaTeX 0.16.9 has published advisories that are fixed in 0.16.10
    and 0.16.11.
  - The error branch puts `e.message` into `innerHTML`.
- **Fix:**
  - Change to `trust: false`, or allow only `\href` with `http`/`https`.
  - Upgrade KaTeX to 0.16.11 or later.
  - Show the error with `textContent` instead of `innerHTML`.

### 2. Medium: no security headers

The live site sends no `Content-Security-Policy`,
`Strict-Transport-Security`, `X-Frame-Options` / `frame-ancestors`, or
`X-Content-Type-Options`.

- **Impact:** a Content-Security-Policy would have blocked the
  `javascript:` link and the tracking image in finding 1.
- **Fix:** add these headers in nginx.

### 3. Medium: scripts from outside servers aren't pinned

The page loads KaTeX from jsdelivr and CodeMirror from esm.sh with no
integrity hash. esm.sh builds its files when they're requested, so a
compromise or a broken build there runs inside the page that holds your
token. Its outage earlier is how the CodeMirror editor broke.

- **Fix:** serve KaTeX and the CodeMirror bundle from greppit.app
  itself, or at least add integrity hashes (`integrity=`) to the KaTeX
  files.

### 4. Medium: no limit on login or signup attempts

`backend/src/Handler/Auth.hs`

- **Impact:**
  - Anyone can try passwords as fast as they like.
  - Anyone can create accounts, since signup is open.
  - Each login runs the slow bcrypt setting, so a flood of requests can
    also tie up the server's CPU.
- **Fix:** add an nginx `limit_req` rule on `/api/auth/`, or a Cloudflare
  rate-limiting rule.

### 5. Medium: a missing JWT secret falls back to a public one

`backend/src/Config.hs:27`

If `JWT_SECRET` is ever missing from `.env`, the backend starts with the
default secret, which is published in the repo. Anyone could then create
a valid token for any user.

- **Fix:** refuse to start when `JWT_SECRET` is unset or equals the
  default. The server's actual value hasn't been checked.

### 6. Low

- **Any website can call the API** (`backend/src/App.hs:54`): CORS
  allows `*`. Tokens are sent in a header rather than a cookie, so this
  isn't exploitable today. Still, restrict it to `https://greppit.app`.
- **Passwords aren't checked** (`signupHandler`): the backend accepts
  any password, including an empty one.
- **Account lookup:**
  - Signup answers "email already registered".
  - A login with an unknown email returns faster, because it skips
    bcrypt.

  Both let someone find out which emails have accounts.
- **Tokens:** they last 7 days, there's no way to cancel one on the
  server, and they're stored in localStorage, where any injected script
  (finding 1) can read them.
- **Cloudflare can be bypassed:** `https://161.35.125.40/` answers
  directly, skipping Cloudflare. Limiting ports 80 and 443 to
  Cloudflare's IP ranges would stop that.
- **Running as root:** the backend runs as root
  (`deploy/greppit-backend.service`), and nginx serves files from under
  `/root`.

## Server checks to run

These only read settings, and the JWT check prints the secret's length,
not the secret:

```bash
ssh root@161.35.125.40
s=$(grep ^JWT_SECRET= /root/greppit/.env | cut -d= -f2-); echo "len=${#s}"; [ "$s" = "dev-secret-change-in-production-min-32-chars!!" ] && echo DEFAULT
stat -c %a /root/greppit/.env            # want 600
ufw status
ss -tlnp                                  # postgres should be 127.0.0.1 only
sshd -T | grep -E "^(passwordauthentication|permitrootlogin) "   # want: no / prohibit-password
systemctl is-active fail2ban
apt list --upgradable 2>/dev/null | grep -i security
```

## Suggested order

Fix finding 1 first: it's three small changes in `frontend/index.html`,
plus a page header that blocks `javascript:` links even if KaTeX lets
one through.
