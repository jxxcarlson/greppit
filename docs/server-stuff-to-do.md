# Server stuff to do

Written 2026-10-31.

## Stop browsers and Cloudflare serving an old build

**Done** 2026-10-31. nginx was changed with `deploy/nginx/add-no-cache.sh`,
and Cloudflare's Browser Cache TTL is set to "Respect Existing Headers"
(before that, Cloudflare replaced nginx's header with `max-age=14400`).
greppit.app now sends `cache-control: no-cache` for `/` and `elm.js`.
Keep the Cloudflare setting: a fixed TTL would override nginx again.
The steps below are kept for reference.

Branch `chore/nginx-no-cache` changes the nginx config so browsers and
Cloudflare check for a new `index.html`, `elm.js` and
`codemirror-element.js` on every load, instead of reusing a cached copy
for hours. When nothing has changed, the check is a quick "not modified"
reply, so pages don't get slower.

Edit the installed config in place. Don't copy the repo file over it,
because certbot added the HTTPS section to the installed copy and
copying would delete it.

### 1. Open the installed config

```bash
ssh root@161.35.125.40
nano /etc/nginx/sites-available/greppit.app.conf
```

### 2. Replace the caching blocks

Find these lines, which may appear in more than one `server { … }`
block once certbot has added its HTTPS block:

```nginx
location = /elm.js {
    add_header Cache-Control "public, max-age=3600";
}
location = /codemirror-element.js {
    add_header Cache-Control "public, max-age=31536000";
}
```

Replace them with:

```nginx
location = /index.html {
    add_header Cache-Control "no-cache";
}
location = /elm.js {
    add_header Cache-Control "no-cache";
}
location = /codemirror-element.js {
    add_header Cache-Control "no-cache";
}
```

The one that matters is the block with `listen 443 ssl`. That's what
Cloudflare connects to.

### 3. Test and reload nginx

```bash
nginx -t && systemctl reload nginx
```

If `nginx -t` reports an error, it doesn't reload and the site keeps
running as it was. If that happens, check the edit and try again.

### 4. Purge Cloudflare once

In the dashboard, go to greppit.app → Caching → Configuration → Purge
Everything, or purge just `https://greppit.app/elm.js`. This clears the
copy cached under the old 4-hour rule.

### 5. Check it from your Mac

```bash
curl -sI https://greppit.app/elm.js | grep -i cache-control
```

It should say `cache-control: no-cache`. On 2026-10-31 it said
`public, max-age=14400`. If it still says that after the reload and
purge, Cloudflare is overriding the server's setting. In that case, set
Caching → Configuration → Browser Cache TTL to "Respect Existing
Headers".

### 6. Merge the branches

Once the check passes, merge `chore/nginx-no-cache` into `main` so the
repo matches the server. `feat/document-reference` (the bookmarklet) is
working and can be merged at the same time.

Claude can do steps 1–3 and 5 over ssh. The Cloudflare purge has to be
done by you in the dashboard.
