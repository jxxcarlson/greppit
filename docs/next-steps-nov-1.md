# Next steps (as of 2026-11-01)

What's left after the move to rose2 and the pdfServer security work. The
details are in `docs/security-remaining-tasks.md` and in the migration
notes in `docs/changelog.md`.

## On a date

- **Around November 4–5:** if rose2 has been running well:
  - delete the **rose** droplet (161.35.125.40) and its snapshot
    `rose-1793510599494` in DigitalOcean;
  - remove rose's key (`root@rose`, `SHA256:m9mhDSUd…`) from GitHub
    (github.com/settings/keys).
- **Before December 10:** dataserv.app's registration expires, so check
  auto-renew in Cloudflare (Domains → Registrations → dataserv.app).

## What to do next

1. ~~**Run greppit, cloudelog and scripta the way pdfServer now runs.**~~
   **Done 2026-11-01.** All four backends now run as their own
   unprivileged users (`greppit`, `cloudelog`, `scripta`, `pdfserver`)
   in a systemd sandbox, set up by `deploy/run-backends-unprivileged.sh`.
   James tested all three apps; see `docs/changelog.md`.
2. ~~**Fix pdfServer's image-URL mangling.**~~ **Done 2026-11-01** in
   pdfServer (`b34570b`, deployed). The matching fix in scripta-app-v3
   (`src/Frontend/PDF.elm`) is local, not committed, for James to deploy
   with Lamdera. In documents with several
   images, one image's name gets substituted inside the other URLs (it
   shows in the logs as `…/image-1.jpgd7b724d-image-1.jpg…`), so those
   downloads fail. Users can actually hit this.
3. **Keep a copy of the nightly database dumps somewhere other than
   rose2.** Right now they live only on rose2, plus DigitalOcean's weekly
   backup of the whole server. A nightly copy to the Mac or to cloud
   storage would close that gap.

Next: (3).

## Smaller items, any time

- **pdfServer:**
  - anyone can use `/image` and `/tikz2png` to upload to the Cloudflare
    Images account; checking that requests come from scripta's sites
    would limit that;
  - PDFs can be fetched by anyone who knows the name;
  - the request log is very chatty;
  - port 3000 should listen only on the server itself;
  - minor code cleanups (deprecated `param`, a duplicate `staticPolicy`,
    the unused `V3` checkout).
- **greppit:**
  - CodeMirror is loaded from esm.sh rather than served by greppit
    itself;
  - the API accepts requests from any website (CORS);
  - there's no minimum password length;
  - the login and signup responses reveal which emails have accounts.
- **cloudelog:** the frontend change `d6ea514` is still undeployed.
