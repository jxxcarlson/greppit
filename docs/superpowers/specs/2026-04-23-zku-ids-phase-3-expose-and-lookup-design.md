# zku IDs — Phase 3 — Expose in Responses & Accept in Path Captures (Design Spec)

**Status:** approved 2026-04-23.
**Precedes:** Phase 3 implementation plan (to be written next).
**Succeeds:** Phase 2 (`docs/superpowers/plans/2026-04-23-zku-ids-phase-2-minting-on-write.md`).

## 1. Goal

Surface the zku identifiers that Phase 2 started minting. After Phase 3:

- `GET`/`POST`/`PUT` snippet responses include `zkuId`.
- Auth responses' `UserResponse` includes `username`.
- `GET`/`PUT`/`DELETE /api/snippets/:id` accept **either** a UUID (existing clients, including the Elm frontend) **or** a `zku_id` string in the path parameter.
- The Elm frontend does not change in Phase 3 — its JSON decoders are `D.field`-based and silently tolerate extra fields; its URL-construction continues to use the UUID it receives as `snippet.id`. A later phase may switch the frontend to zku_ids for shareable URLs.

## 2. Non-goals

- **Frontend changes.** Phase 3 stays strictly backend-facing. Phase 4 (or later) can switch Elm to using `zku_id` in URLs, add shareable-link UI, etc.
- **Retiring `snippets.id`.** The UUID PK stays. It's still the "source of truth" column for internal references (FKs, etc.) — zku_id is a secondary unique external identifier. Dropping the UUID is not on any roadmap and would require a coordinated migration (which we're not doing here).
- **DB integration tests.** Same deferral as Phase 2; we rely on manual verification on dev.
- **Constraining zku_id format in the lookup.** We won't try to parse/discriminate UUID-vs-zku_id in Haskell. Postgres's `OR` predicate does the lookup cheaply; if a malformed string is provided, it simply matches neither column and returns 404 — same outcome as today.

## 3. Architecture summary

- **Response shape additions are purely additive.** New optional-looking JSON fields (`zkuId`, `username`) appear; nothing existing is renamed or removed. Elm decoders tolerate extra fields, so no frontend change is required.
- **Path-capture lookup widens via SQL.** The three affected statements (`getSnippetById`, `updateSnippet`, `deleteSnippet`) gain `OR zku_id = $1` in their `WHERE` clauses. No Haskell-side branching on identifier format. The unique constraint on `zku_id` plus PK on `id` guarantees at most one row matches.
- **`Snippet` domain type + `snippetRow` decoder extend for `zku_id`.** All existing SELECTs (`getSnippetById`, `searchSnippets`, `listAllSnippets`, and the post-create/post-update re-fetch) add `zku_id` to their column list to match the decoder.
- **`User` type already carries `usrUsername`** (Phase 2). Just surface it in the API response by populating `urUsername` in signup/login.

No new modules. No DB migration. No constraint changes.

## 4. Component detail

### 4.1 `Types.Snippet.Snippet`

Gains `snpZkuId :: Text`, inserted to match the DB column order `id, user_id, zku_id, title, tags, markup, body, created_at, updated_at`:

```haskell
data Snippet = Snippet
  { snpId        :: SnippetId
  , snpUserId    :: UserId
  , snpZkuId     :: Text        -- NEW in Phase 3
  , snpTitle     :: Text
  , snpTags      :: Text
  , snpMarkup    :: Markup
  , snpBody      :: Text
  , snpCreatedAt :: UTCTime
  , snpUpdatedAt :: UTCTime
  } deriving (Show, Eq)
```

### 4.2 `Db.Snippet` — decoder and statements

The `snippetRow` decoder adds one column in the new position:

```haskell
snippetRow :: D.Row Snippet
snippetRow = Snippet
  <$> D.column (D.nonNullable D.text)        -- id
  <*> D.column (D.nonNullable D.text)        -- user_id
  <*> D.column (D.nonNullable D.text)        -- zku_id
  <*> D.column (D.nonNullable D.text)        -- title
  <*> D.column (D.nonNullable D.text)        -- tags
  <*> D.column (D.nonNullable (D.refine refineMarkup D.text))  -- markup
  <*> D.column (D.nonNullable D.text)        -- body
  <*> D.column (D.nonNullable D.timestamptz) -- created_at
  <*> D.column (D.nonNullable D.timestamptz) -- updated_at
```

Five SQL strings change. All three `WHERE` clauses that look up by `id` widen to accept zku_id too. All four SELECTs add `zku_id` to their column list. `insertSnippet` is **unchanged** (Phase 2 already populates zku_id on insert).

```sql
-- getSnippetById:
SELECT id, user_id, zku_id, title, tags, markup, body, created_at, updated_at
FROM snippets
WHERE (id = $1 OR zku_id = $1) AND user_id = $2

-- updateSnippet (zku_id NOT updated here — it's immutable by design):
UPDATE snippets
SET title = $3, tags = $4, markup = $5, body = $6, updated_at = now()
WHERE (id = $1 OR zku_id = $1) AND user_id = $2

-- deleteSnippet:
DELETE FROM snippets
WHERE (id = $1 OR zku_id = $1) AND user_id = $2

-- searchSnippets:
SELECT id, user_id, zku_id, title, tags, markup, body, created_at, updated_at
FROM snippets
WHERE user_id = $1
  AND (title || ' ' || tags || ' ' || body) ILIKE ALL ($2 :: text[])
ORDER BY updated_at DESC
LIMIT 5

-- listAllSnippets:
SELECT id, user_id, zku_id, title, tags, markup, body, created_at, updated_at
FROM snippets
WHERE user_id = $1
ORDER BY updated_at DESC
```

### 4.3 `Api.RequestTypes` — response shape additions

`SnippetResponse` gains `spRespZkuId` (serializes as `zkuId` via the existing `stripPrefixOptions 6` rule). `UserResponse` gains `urUsername` (serializes as `username`).

```haskell
data SnippetResponse = SnippetResponse
  { spRespId        :: SnippetId
  , spRespUserId    :: UserId
  , spRespZkuId     :: Text        -- NEW
  , spRespTitle     :: Text
  , spRespTags      :: Text
  , spRespMarkup    :: Text
  , spRespBody      :: Text
  , spRespCreatedAt :: UTCTime
  , spRespUpdatedAt :: UTCTime
  } deriving (Show, Generic)

data UserResponse = UserResponse
  { urId       :: UserId
  , urEmail    :: Text
  , urUsername :: Text             -- NEW
  } deriving (Show, Generic)
```

Both serialize additively — the two new fields are strings that land alongside existing keys.

### 4.4 `Handler.Snippets.toResp`

Extends one field mapping:

```haskell
toResp s = SnippetResponse
  { spRespId        = snpId s
  , spRespUserId    = snpUserId s
  , spRespZkuId     = snpZkuId s     -- NEW
  , spRespTitle     = snpTitle s
  , spRespTags      = snpTags s
  , spRespMarkup    = markupText (snpMarkup s)
  , spRespBody      = snpBody s
  , spRespCreatedAt = snpCreatedAt s
  , spRespUpdatedAt = snpUpdatedAt s
  }
```

### 4.5 `Handler.Auth` — populate `urUsername` at signup + login

Two call sites. Both already have the username in scope:

- `signupHandler`: the chosen username is `chosen` (returned by `tryInsertUser`). Pass to `UserResponse`.
- `loginHandler`: the fetched `User` has `usrUsername`. Pass to `UserResponse`.
- `meHandler`: builds `UserResponse` from `AuthUser`, which carries `auUsername` since Phase 2.

```haskell
-- signupHandler (tail)
pure AuthResponse
  { arToken = …
  , arUser  = UserResponse userId (srEmail req) chosen
  }

-- loginHandler (tail)
pure AuthResponse
  { arToken = …
  , arUser  = UserResponse (usrId user) (usrEmail user) (usrUsername user)
  }

-- meHandler
meHandler (Authenticated au) =
  pure $ UserResponse (auUserId au) (auEmail au) (auUsername au)
```

### 4.6 API route handlers — unchanged externally

`Api.Snippets` already uses `Capture "id" Text`. The handlers (`getSnippetHandler`, `updateSnippetHandler`, `deleteSnippetHandler`) pass that opaque text straight to `Db.Snippet` — no format inspection on the Haskell side. Postgres decides what matches.

## 5. Error handling

Unchanged across the board. 401 on unauthorized, 404 on not-found (whether the caller passed a bogus UUID or a bogus zku_id), 500 on DB errors. Invalid ID formats simply match zero rows.

## 6. Testing

### 6.1 Unit tests — unchanged

Phase 2's `41 examples, 0 failures` stay green. No new pure logic to unit-test.

### 6.2 Elm decoder tests — unchanged

`frontend/tests/ApiDecoderTests.elm` exercises `D.field`-based decoders that ignore extra fields. New fields in the JSON won't break decoding. We don't add Elm tests for the new fields because the Elm frontend doesn't yet *use* them.

### 6.3 Manual dev verification — the real gate

1. Start backend locally against `greppit_dev`.
2. `GET /api/auth/me` (with a valid token) → response includes `username`.
3. `POST /api/snippets` → response includes `zkuId`.
4. `GET /api/snippets/<UUID>` → same snippet (old behavior).
5. `GET /api/snippets/<zkuId>` → same snippet (new behavior).
6. `PUT /api/snippets/<zkuId>` with new body → succeeds; response has the same `zkuId` and updated timestamps.
7. `DELETE /api/snippets/<zkuId>` → 204; subsequent GET returns 404 whether by `<UUID>` or `<zkuId>`.
8. `GET /api/snippets/nonsense-string` → 404.
9. `GET /api/snippets?q=...` → list items each have `zkuId`.

## 7. Deploy notes

Same shape as Phase 2:

```bash
cd ~/greppit
scripts/db-dump-do.sh
git pull
cd backend && stack install --local-bin-path /usr/local/bin
ls -la /usr/local/bin/greppit-backend   # timestamp should be fresh
ss -tlnp | grep 8086                    # confirm no orphan
# if a PID shows up, kill it before restart:
# kill <PID> && systemctl reset-failed greppit-backend
systemctl restart greppit-backend
systemctl status greppit-backend --no-pager
```

**No migration** (Phase 1 schema already has the columns; Phase 2 already populates them on write).

**No re-login required** this time. `AuthUser` is unchanged in Phase 3 (still `{auUserId, auEmail, auUsername}` from Phase 2). Existing tokens stay valid.

## 8. Success criteria

Phase 3 is done when all of:

1. `stack test` still reports `41 examples, 0 failures`.
2. A `curl` against `/api/auth/me` on dev returns a body containing `"username":"..."`.
3. A `curl` against a freshly-created snippet by its `zkuId` returns the same payload as by its UUID `id`.
4. Every `SnippetResponse` returned by the API contains `"zkuId":"..."`.
5. The Elm frontend's existing behavior is visually unchanged on dev (smoke test: open app, list snippets, view one, edit one, delete one, create one — all operations continue to work).
6. Deployed to prod; manual spot-check confirms both behaviors.

## 9. Future work (explicitly deferred)

- **Phase 4**: Elm frontend switches to `zku_id` in URL paths (shareable bookmarks), displays username in the UI, etc.
- **API versioning or deprecation of UUID paths**: only meaningful if we ever retire `snippets.id`. No current plan to do that.
- **DB integration tests**: still deferred; the pure test suite has been enough signal so far.
