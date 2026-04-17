# Greppit — v1 Design

**Date:** 2026-04-17
**Domain:** greppit.app (deferred to post-v1)
**Status:** Approved design, ready for implementation plan

## Purpose

A small personal note tool. A signed-in user creates short snippets (title,
tags, markup language, body) written in Markdown or Scripta, and retrieves
them via conjunctive case-insensitive keyword search. The UI is deliberately
minimal: a header and two columns.

## Scope

### In scope for v1
- Email/password signup and login; JWT sessions
- Create, read, update, delete personal snippets (private per user)
- Markdown rendering with KaTeX math (`$...$`, `$$...$$`)
- Scripta option in the markup dropdown, but rendering stubbed ("not yet enabled")
- Conjunctive ILIKE search over `title + tags + body`, capped at 5 results
- Empty search shows the 5 most recently updated snippets
- CodeMirror 6 editor for the snippet body

### Out of scope for v1
- Sharing / collaboration / multi-user on a snippet
- Scripta rendering (data path ready; rendering stubbed)
- Pagination beyond 5 results (refine the query instead)
- Autosave (explicit Save button)
- Password reset, magic links, OAuth
- WebSocket / real-time features
- Production deployment to greppit.app
- Pill-style tag input (space-separated string is fine for v1)

## Architecture

Tech stack mirrors `scripta-app-v4`: **Postgres + Hasql (Haskell) + Elm**.
Minimize JavaScript; keep rendering and state in Elm.

### Backend layout (`backend/`)

Full `scripta-app-v4` layout, minus WebSocket:

```
app/Main.hs
src/
  App.hs
  AppEnv.hs
  AppError.hs
  Config.hs
  Lib.hs
  Api/
  Db/
  Handler/
  Service/
  Types/
db/schema.sql          -- managed via dbmate
```

No `WebSocket/` subtree; greppit has no collaborative features.

### Frontend layout (`frontend/`)

Single-page Elm app, one `Main.elm`, one top-level model.

```
frontend/
  elm.json
  index.html
  codemirror-element.js       -- lifted from scripta-app-v4
  elm-markdown/               -- vendored from scripta-app-v4 (extended markdown + math)
  src/
    Main.elm
    Types.elm
    Auth.elm
    Api.elm
    Search.elm
    Editor.elm
    Render.elm
    CodeMirror.elm
```

### Deployment

Local dev only for v1. `run.sh` / `serve.py` style scripts matching
`scripta-app-v4`. `greppit.app` domain hookup is explicitly deferred.

## Data model

Two tables.

```sql
CREATE TABLE users (
    id         TEXT PRIMARY KEY,          -- UUID
    email      TEXT NOT NULL UNIQUE,
    pw_hash    TEXT NOT NULL,             -- bcrypt; cost matches scripta-app-v4
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE snippets (
    id         TEXT PRIMARY KEY,          -- UUID
    user_id    TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    title      TEXT NOT NULL,
    tags       TEXT NOT NULL DEFAULT '',  -- space-separated, lowercased on save
    markup     TEXT NOT NULL DEFAULT 'markdown'
                 CHECK (markup IN ('markdown', 'scripta')),
    body       TEXT NOT NULL DEFAULT '',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX snippets_user_updated_idx ON snippets (user_id, updated_at DESC);
```

### Search query

One `ILIKE '%term%'` predicate per whitespace-separated search term, ANDed
together. Empty query → no predicates, just the 5 most recent.

```sql
SELECT id, title, tags, markup, body, created_at, updated_at
FROM snippets
WHERE user_id = $1
  AND title || ' ' || tags || ' ' || body ILIKE $2
  AND title || ' ' || tags || ' ' || body ILIKE $3
  -- one ILIKE per term, ANDed
ORDER BY updated_at DESC
LIMIT 5;
```

Postgres handles this fine at the expected scale (hundreds to low thousands
of snippets per user). An upgrade path to `pg_trgm` or `tsvector` is
available later without UI changes.

## API

All routes under `/api`. Everything except `/auth/signup` and `/auth/login`
requires `Authorization: Bearer <jwt>`.

```
POST   /api/auth/signup         { email, password }        → { token, user }
POST   /api/auth/login          { email, password }        → { token, user }
GET    /api/auth/me                                        → { user }

GET    /api/snippets?q=<terms>                             → [ snippet, ... ]  (max 5, recency-ordered)
POST   /api/snippets            { title, tags, markup, body }  → snippet
GET    /api/snippets/:id                                   → snippet
PUT    /api/snippets/:id        { title, tags, markup, body }  → snippet
DELETE /api/snippets/:id                                   → 204
```

### `snippet` JSON shape

```json
{
  "id": "...",
  "userId": "...",
  "title": "...",
  "tags": "elm howto",
  "markup": "markdown",
  "body": "...",
  "createdAt": "2026-04-17T...",
  "updatedAt": "2026-04-17T..."
}
```

### Semantics
- `GET /api/snippets` with no `q` returns the 5 most recently updated.
- Search terms are split server-side on whitespace.
- `GET`/`PUT`/`DELETE` on a snippet scope to `user_id = <current user>`; a
  404 is returned for another user's id (no existence leak).
- Tags are lowercased and whitespace-normalized on save.

## Auth

- Signup creates a user, hashes the password with bcrypt (cost matches
  `scripta-app-v4`), returns a JWT.
- Login verifies credentials, returns a JWT.
- JWT is HS256-signed with a server secret from env; 7-day expiry.
- Backend middleware verifies the token and attaches `userId` to the
  request context.
- Frontend stores the token in localStorage via a `saveToken` port; reads
  it back on init via flags.

## Frontend state and UI

### Top-level shape

```elm
type Page
    = SignedOut SignedOutModel
    | SignedIn SignedInModel

type alias SignedInModel =
    { user : User
    , token : String
    , searchInput : String
    , results : List Snippet           -- the most recent 5 matches
    , rightMode : RightMode
    }

type RightMode
    = Display (Maybe Snippet)          -- Nothing before first selection
    | Editor EditorState               -- handles both New and Edit
```

`EditorState` carries either a fresh draft (for New) or an `editing`
snippet plus a draft derived from it (for Edit), so Save routes to POST
vs PUT accordingly.

### Layout

- **Header:** `greppit` on the left; on the right, a **New Snippet**
  button, the signed-in user's email, and **Sign out**.
- **Left column:** search input, then a scrolling list of up to 5
  matched snippets (title + short tag line).
- **Right column:** either Display mode (one rendered snippet, with an
  **Edit** button) or Editor mode (the new/edit form).

### Data flow
1. Typing in the search box → debounced 200ms → `GET /api/snippets?q=…` → `results`.
2. Click a result → `rightMode := Display (Just snippet)`. Snippet already
   present in `results`; no fetch needed.
3. Header **New Snippet** → `rightMode := Editor { newDraft = empty }`.
4. Display-mode **Edit** button → `rightMode := Editor { editing = s, draft = fromSnippet s }`.
5. **Save** → POST (new) or PUT (edit) → on success, merge the returned
   snippet into `results` and set `rightMode := Display (Just savedSnippet)`.
6. **Delete** (Editor mode only, confirm prompt) → DELETE → remove from
   `results`, `rightMode := Display Nothing`.
7. **Sign out** → clear token and model, return to `SignedOut`.

### Editor form fields
- Title (text input)
- Tags (text input; space-separated; lowercased on save)
- Markup (dropdown: Markdown / Scripta; default Markdown)
- Body (CodeMirror 6)
- Buttons: **Save**, **Cancel**; in Edit mode also **Delete** (with
  confirm).

### CodeMirror integration
- Lift `codemirror-element.js` from `scripta-app-v4/frontend/`. It defines
  a `<codemirror-editor>` custom element with `value` / `on-change`.
- `CodeMirror.elm` renders `Html.node "codemirror-editor" [...]` and
  subscribes to a port `codemirrorChanged : (String -> msg) -> Sub msg`.
- Setting the value is an attribute assignment; no `Cmd` needed.

## Rendering

`Render.elm` exports `render : Snippet -> Html msg`, dispatching on
`snippet.markup`:

- **Markdown branch:** calls the vendored `elm-markdown` package entry
  point used by `scripta-app-v4`. Math delimiters `$...$` and `$$...$$`
  render through **KaTeX** using the same mechanism `scripta-app-v4`
  uses (NOT MathJax; `elm-mathjax` is not used).
- **Scripta branch:** for v1, renders a static "Scripta rendering not
  yet enabled" placeholder. Data and the dropdown still work, so
  enabling real Scripta rendering later is a `Render.elm`-only change.

## Search UX details

- Search is conjunctive: every whitespace-separated term must match.
- Case-insensitive everywhere (`ILIKE`).
- Empty input → 5 most recently updated snippets.
- Results capped at 5; refining the query is the way to find more. No
  pagination in v1.

## Open questions resolved during brainstorming

- **Edit mode:** third right-column mode; Editor form is reusable for
  New and Edit.
- **Search fields:** title + tags + body, concatenated.
- **Result ordering:** most recently updated first.
- **Auth:** email + password with JWT (matches scripta-app-v4).
- **Markdown library:** vendored `elm-markdown` from scripta-app-v4.
- **Empty search:** show 5 most recent.
- **Delete:** available in Edit mode, with confirm.
- **Tag format:** space-separated string.
- **Header:** app name left; New Snippet + email + Sign out right.
- **Save:** explicit button, no autosave.
- **Backend layout:** full scripta-app-v4 mirror minus WebSocket.
- **Math renderer:** KaTeX, not MathJax.

## Items to confirm during implementation (not blockers)

- Exact entry point name in vendored `elm-markdown` for rendering.
- bcrypt cost factor used in `scripta-app-v4` (match it).
- HTTP framework in `scripta-app-v4/backend` (Servant vs plain WAI) — match it.
- KaTeX wiring: lift the exact mechanism scripta-app-v4 uses.
