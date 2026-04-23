# zku IDs — Phase 3 — Expose & Lookup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Expose `zku_id` in snippet responses and `username` in auth responses, and let the `/api/snippets/:id` handlers accept either the UUID or the zku_id in the path parameter. No frontend changes.

**Architecture:** Two narrow changes. **(1)** Extend the `Snippet` domain type with `snpZkuId`, widen `snippetRow` and every SELECT that reads snippets to include the new column, and add `spRespZkuId`/`urUsername` to the existing response records. **(2)** Widen the WHERE clauses of `getSnippetById`/`updateSnippet`/`deleteSnippet` from `id = $1` to `(id = $1 OR zku_id = $1)`, letting Postgres resolve which identifier the caller supplied. No new modules, no migration, no re-login required on deploy.

**Tech Stack:** Haskell (GHC 9.6), Hasql, Servant, HSpec.

**Spec:** `docs/superpowers/specs/2026-04-23-zku-ids-phase-3-expose-and-lookup-design.md` (committed on this branch as `869e4e8`).

---

## File Structure

**Modify:**
- `backend/src/Types/Snippet.hs` — add `snpZkuId :: Text` to the `Snippet` record.
- `backend/src/Db/Snippet.hs` — extend `snippetRow` decoder; add `zku_id` to SELECT column lists in `getSnippetById`, `searchSnippets`, `listAllSnippets`; widen WHERE clauses of `getSnippetById`/`updateSnippet`/`deleteSnippet`; leave `insertSnippet` unchanged (Phase 2 already handles it), leave `updateSnippet`'s SET list unchanged (zku_id is immutable).
- `backend/src/Api/RequestTypes.hs` — add `spRespZkuId :: Text` to `SnippetResponse` and `urUsername :: Text` to `UserResponse`.
- `backend/src/Handler/Snippets.hs` — extend `toResp` to populate `spRespZkuId`.
- `backend/src/Handler/Auth.hs` — populate `urUsername` in the three `UserResponse` construction sites (`signupHandler`, `loginHandler`, `meHandler`).

**No creates. No deletes. No migration.**

---

## Task 1: Expose `zkuId` in snippet responses and `username` in user responses

This task touches five files and must land atomically — Haskell's type system will reject any partial application. Apply all five edits, then build + test.

**Files:**
- Modify: `backend/src/Types/Snippet.hs`
- Modify: `backend/src/Db/Snippet.hs`
- Modify: `backend/src/Api/RequestTypes.hs`
- Modify: `backend/src/Handler/Snippets.hs`
- Modify: `backend/src/Handler/Auth.hs`

### Step 1: Extend `Types.Snippet.Snippet`

Full new content of `backend/src/Types/Snippet.hs`:

```haskell
{-# LANGUAGE OverloadedStrings #-}
module Types.Snippet (Snippet(..), Markup(..), parseMarkup, markupText) where

import Data.Text (Text)
import Data.Time (UTCTime)
import Types.Common (UserId, SnippetId)

data Markup = Markdown | Scripta | PlainText
  deriving (Show, Eq)

parseMarkup :: Text -> Maybe Markup
parseMarkup "markdown"  = Just Markdown
parseMarkup "scripta"   = Just Scripta
parseMarkup "plaintext" = Just PlainText
parseMarkup _           = Nothing

markupText :: Markup -> Text
markupText Markdown  = "markdown"
markupText Scripta   = "scripta"
markupText PlainText = "plaintext"

data Snippet = Snippet
  { snpId        :: SnippetId
  , snpUserId    :: UserId
  , snpZkuId     :: Text
  , snpTitle     :: Text
  , snpTags      :: Text
  , snpMarkup    :: Markup
  , snpBody      :: Text
  , snpCreatedAt :: UTCTime
  , snpUpdatedAt :: UTCTime
  } deriving (Show, Eq)
```

`snpZkuId` is inserted between `snpUserId` and `snpTitle` to match the DB column order `id, user_id, zku_id, title, tags, markup, body, created_at, updated_at`. The decoder relies on positional ordering, so this matters.

### Step 2: Extend `Db.Snippet` — decoder and SELECT column lists only

In `backend/src/Db/Snippet.hs`, apply three edits. Do **not** change the WHERE clauses yet (that's Task 2).

**(a)** Replace `snippetRow` (currently ~lines 22-38) with:

```haskell
-- | Decode one snippet row.
-- Columns: id, user_id, zku_id, title, tags, markup, body, created_at, updated_at
snippetRow :: D.Row Snippet
snippetRow = Snippet
  <$> D.column (D.nonNullable D.text)        -- id
  <*> D.column (D.nonNullable D.text)        -- user_id
  <*> D.column (D.nonNullable D.text)        -- zku_id
  <*> D.column (D.nonNullable D.text)        -- title
  <*> D.column (D.nonNullable D.text)        -- tags
  <*> D.column (D.nonNullable (D.refine refineMarkup D.text))
  <*> D.column (D.nonNullable D.text)        -- body
  <*> D.column (D.nonNullable D.timestamptz) -- created_at
  <*> D.column (D.nonNullable D.timestamptz) -- updated_at
  where
    refineMarkup :: Text -> Either Text Markup
    refineMarkup t = case parseMarkup t of
      Just m  -> Right m
      Nothing -> Left ("unknown markup: " <> t)
```

**(b)** In `getSnippetById`, change the SQL's SELECT column list (leave WHERE alone for now):

```haskell
getSnippetById :: Statement (SnippetId, UserId) (Maybe Snippet)
getSnippetById = Statement sql encoder (D.rowMaybe snippetRow) True
  where
    sql = "SELECT id, user_id, zku_id, title, tags, markup, body, created_at, updated_at \
          \FROM snippets WHERE id = $1 AND user_id = $2"
    encoder =
      (fst >$< E.param (E.nonNullable E.text)) <>
      (snd >$< E.param (E.nonNullable E.text))
```

**(c)** In `searchSnippets`, add `zku_id` to the SELECT column list:

```haskell
searchSnippets :: Statement (UserId, Vector Text) (Vector Snippet)
searchSnippets = Statement sql encoder (D.rowVector snippetRow) True
  where
    sql = "SELECT id, user_id, zku_id, title, tags, markup, body, created_at, updated_at \
          \FROM snippets \
          \WHERE user_id = $1 \
          \  AND (title || ' ' || tags || ' ' || body) ILIKE ALL ($2 :: text[]) \
          \ORDER BY updated_at DESC \
          \LIMIT 5"
    encoder =
      (fst >$< E.param (E.nonNullable E.text)) <>
      (snd >$< E.param (E.nonNullable
        (E.array (E.dimension foldl (E.element (E.nonNullable E.text))))))
```

**(d)** In `listAllSnippets`, add `zku_id` to the SELECT column list:

```haskell
listAllSnippets :: Statement UserId (Vector Snippet)
listAllSnippets = Statement sql encoder (D.rowVector snippetRow) True
  where
    sql = "SELECT id, user_id, zku_id, title, tags, markup, body, created_at, updated_at \
          \FROM snippets \
          \WHERE user_id = $1 \
          \ORDER BY updated_at DESC"
    encoder = E.param (E.nonNullable E.text)
```

Leave `insertSnippet`, `updateSnippet`, and `deleteSnippet` completely untouched in Task 1.

### Step 3: Extend `Api.RequestTypes` response records

In `backend/src/Api/RequestTypes.hs`:

**(a)** Replace the `SnippetResponse` definition (around lines 57-68) with:

```haskell
data SnippetResponse = SnippetResponse
  { spRespId        :: SnippetId
  , spRespUserId    :: UserId
  , spRespZkuId     :: Text
  , spRespTitle     :: Text
  , spRespTags      :: Text
  , spRespMarkup    :: Text
  , spRespBody      :: Text
  , spRespCreatedAt :: UTCTime
  , spRespUpdatedAt :: UTCTime
  } deriving (Show, Generic)
instance ToJSON SnippetResponse where
  toJSON = genericToJSON (stripPrefixOptions 6)   -- strip "spResp"
```

`spRespZkuId` serializes as `zkuId` (strip `spResp`, lowercase first char).

**(b)** Replace the `UserResponse` definition (around lines 42-47) with:

```haskell
data UserResponse = UserResponse
  { urId       :: UserId
  , urEmail    :: Text
  , urUsername :: Text
  } deriving (Show, Generic)
instance ToJSON UserResponse where
  toJSON = genericToJSON (stripPrefixOptions 2)
```

`urUsername` serializes as `username`.

### Step 4: Extend `Handler.Snippets.toResp`

In `backend/src/Handler/Snippets.hs`, replace the `toResp` definition (around lines 42-52) with:

```haskell
-- | Convert a Snippet domain value into its JSON response.
toResp :: Snippet -> SnippetResponse
toResp s = SnippetResponse
  { spRespId        = snpId s
  , spRespUserId    = snpUserId s
  , spRespZkuId     = snpZkuId s
  , spRespTitle     = snpTitle s
  , spRespTags      = snpTags s
  , spRespMarkup    = markupText (snpMarkup s)
  , spRespBody      = snpBody s
  , spRespCreatedAt = snpCreatedAt s
  , spRespUpdatedAt = snpUpdatedAt s
  }
```

All other handler functions in this file stay untouched.

### Step 5: Populate `urUsername` in `Handler.Auth`

In `backend/src/Handler/Auth.hs`, three call sites construct `UserResponse`. Replace each with a three-argument construction:

**(a)** In `signupHandler` (around line 66), replace:

```haskell
          , arUser  = UserResponse userId (srEmail req)
```

with:

```haskell
          , arUser  = UserResponse userId (srEmail req) chosen
```

(`chosen` is already in scope from the `tryInsertUser` result.)

**(b)** In `loginHandler` (around line 90), replace:

```haskell
              , arUser  = UserResponse (usrId user) (usrEmail user)
```

with:

```haskell
              , arUser  = UserResponse (usrId user) (usrEmail user) (usrUsername user)
```

**(c)** Replace the entire `meHandler` function (around lines 94-98):

```haskell
meHandler :: AuthResult AuthUser -> AppM UserResponse
meHandler (Authenticated au) =
  pure $ UserResponse (auUserId au) (auEmail au) (auUsername au)
meHandler _ =
  throwError $ appErrorToServantErr Unauthorized
```

No other changes in this file.

### Step 6: Build and test

```bash
cd /Users/carlson/dev/greppit/.worktrees/zku-ids-phase3/backend
stack build 2>&1 | tail -20
```

Expected: clean build, no warnings. If GHC complains about missing fields at a record construction, that's a signal you missed one of Steps 1-5 — re-read.

```bash
stack test 2>&1 | tail -10
```

Expected: `41 examples, 0 failures` (unchanged — no new tests).

### Step 7: Commit

```bash
cd /Users/carlson/dev/greppit/.worktrees/zku-ids-phase3
git add backend/src/Types/Snippet.hs \
        backend/src/Db/Snippet.hs \
        backend/src/Api/RequestTypes.hs \
        backend/src/Handler/Snippets.hs \
        backend/src/Handler/Auth.hs
git commit -m "feat(api): expose zkuId in snippets and username in users

- Snippet domain type carries snpZkuId; snippetRow and all three
  SELECTs (getSnippetById, searchSnippets, listAllSnippets) include
  the new column. insertSnippet and updateSnippet SQL are unchanged:
  zku_id is minted on insert (Phase 2) and immutable thereafter.
- SnippetResponse adds spRespZkuId -> 'zkuId'.
- UserResponse adds urUsername -> 'username', populated at signup,
  login, and /me.
- No auth-token shape change: existing tokens remain valid.
"
```

---

## Task 2: Accept `zku_id` in `/api/snippets/:id` path captures

Widen the WHERE clauses of the three handlers that look up by id to also match on `zku_id`. No Haskell-side changes — the handlers already pass an opaque `Text` through.

**Files:**
- Modify: `backend/src/Db/Snippet.hs`

### Step 1: Widen `getSnippetById` WHERE

In `backend/src/Db/Snippet.hs`, replace the `getSnippetById` statement definition with:

```haskell
-- | Fetch a snippet scoped to a user, by either its UUID `id`
-- or its external `zku_id`. Returns Nothing if not owned / missing.
getSnippetById :: Statement (SnippetId, UserId) (Maybe Snippet)
getSnippetById = Statement sql encoder (D.rowMaybe snippetRow) True
  where
    sql = "SELECT id, user_id, zku_id, title, tags, markup, body, created_at, updated_at \
          \FROM snippets WHERE (id = $1 OR zku_id = $1) AND user_id = $2"
    encoder =
      (fst >$< E.param (E.nonNullable E.text)) <>
      (snd >$< E.param (E.nonNullable E.text))
```

### Step 2: Widen `updateSnippet` WHERE (SET list unchanged)

Replace the `updateSnippet` statement definition with:

```haskell
-- | UPDATE a snippet's mutable fields. Also bumps updated_at = now().
-- zku_id is NOT part of the SET list — it's immutable by design.
-- Matches on either the UUID `id` or the `zku_id`.
-- Takes (id, userId, title, tags, markup, body). Returns rows affected.
updateSnippet :: Statement (SnippetId, UserId, Text, Text, Text, Text) Int
updateSnippet = Statement sql encoder (fromIntegral <$> D.rowsAffected) True
  where
    sql = "UPDATE snippets \
          \SET title = $3, tags = $4, markup = $5, body = $6, updated_at = now() \
          \WHERE (id = $1 OR zku_id = $1) AND user_id = $2"
    encoder =
      ((\(a,_,_,_,_,_) -> a) >$< E.param (E.nonNullable E.text)) <>
      ((\(_,b,_,_,_,_) -> b) >$< E.param (E.nonNullable E.text)) <>
      ((\(_,_,c,_,_,_) -> c) >$< E.param (E.nonNullable E.text)) <>
      ((\(_,_,_,d,_,_) -> d) >$< E.param (E.nonNullable E.text)) <>
      ((\(_,_,_,_,e,_) -> e) >$< E.param (E.nonNullable E.text)) <>
      ((\(_,_,_,_,_,f) -> f) >$< E.param (E.nonNullable E.text))
```

### Step 3: Widen `deleteSnippet` WHERE

Replace the `deleteSnippet` statement definition with:

```haskell
-- | DELETE a snippet scoped to a user. Matches on UUID `id` or `zku_id`.
-- Returns rows affected (0 or 1).
deleteSnippet :: Statement (SnippetId, UserId) Int
deleteSnippet = Statement sql encoder (fromIntegral <$> D.rowsAffected) True
  where
    sql = "DELETE FROM snippets WHERE (id = $1 OR zku_id = $1) AND user_id = $2"
    encoder =
      (fst >$< E.param (E.nonNullable E.text)) <>
      (snd >$< E.param (E.nonNullable E.text))
```

### Step 4: Build and test

```bash
cd /Users/carlson/dev/greppit/.worktrees/zku-ids-phase3/backend
stack build 2>&1 | tail -10
stack test 2>&1 | tail -10
```

Expected: clean build; `41 examples, 0 failures`. No new tests — behavior change is strictly "also accept this other string" which is exercised by Task 3's manual verification.

### Step 5: Commit

```bash
cd /Users/carlson/dev/greppit/.worktrees/zku-ids-phase3
git add backend/src/Db/Snippet.hs
git commit -m "feat(api): accept zku_id in /api/snippets/:id path captures

Widens the WHERE clauses of getSnippetById, updateSnippet, and
deleteSnippet from 'id = \$1' to '(id = \$1 OR zku_id = \$1)'.
No Haskell-side format discrimination — Postgres resolves the match.
Uniqueness of both columns (Phase 1 constraints) guarantees at most
one row matches.

updateSnippet's SET list is unchanged — zku_id is immutable by
design (birth-ID semantics).

Elm frontend is unaffected: it continues to pass the UUID id it
receives in snippet responses.
"
```

---

## Task 3: Manual verification on `greppit_dev`

No code changes. Verifies the 9 spec behaviors end-to-end against the real DB.

### Step 1: Start the dev backend

```bash
cd /Users/carlson/dev/greppit/.worktrees/zku-ids-phase3/backend
DATABASE_URL="host=localhost dbname=greppit_dev" PORT=8085 stack exec greppit-backend &
SERVER_PID=$!
sleep 3
curl -sS http://localhost:8085/api/health
```
Expected: `"ok"` or equivalent.

### Step 2: Signup and capture a token + user

```bash
SIGNUP=$(curl -sS -X POST http://localhost:8085/api/auth/signup \
  -H "Content-Type: application/json" \
  -d '{"email":"phase3test@example.com","password":"correctbattery"}')
echo "$SIGNUP" | python3 -m json.tool
TOKEN=$(echo "$SIGNUP" | python3 -c "import sys,json;print(json.load(sys.stdin)['token'])")
```

Expected: the response body includes `"username": "phase3test"` inside the `"user"` object.

### Step 3: `/api/auth/me` returns username

```bash
curl -sS -H "Authorization: Bearer $TOKEN" http://localhost:8085/api/auth/me | python3 -m json.tool
```
Expected: `{"id": "...", "email": "phase3test@example.com", "username": "phase3test"}`.

### Step 4: Create a snippet and verify response includes `zkuId`

```bash
CREATE=$(curl -sS -X POST http://localhost:8085/api/snippets \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"title":"phase3","tags":"","markup":"markdown","body":"# hi"}')
echo "$CREATE" | python3 -m json.tool
UUID=$(echo "$CREATE" | python3 -c "import sys,json;print(json.load(sys.stdin)['id'])")
ZKU=$(echo "$CREATE" | python3 -c "import sys,json;print(json.load(sys.stdin)['zkuId'])")
echo "UUID=$UUID"
echo "ZKU=$ZKU"
```
Expected: response includes both `"id": "<uuid>"` and `"zkuId": "phase3test-<14 digits>"`.

### Step 5: GET by UUID and by zku_id — both return the same snippet

```bash
curl -sS -H "Authorization: Bearer $TOKEN" "http://localhost:8085/api/snippets/$UUID" | python3 -c "import sys,json;d=json.load(sys.stdin);print('by UUID -> id:', d['id'], 'zkuId:', d['zkuId'])"
curl -sS -H "Authorization: Bearer $TOKEN" "http://localhost:8085/api/snippets/$ZKU"  | python3 -c "import sys,json;d=json.load(sys.stdin);print('by ZKU  -> id:', d['id'], 'zkuId:', d['zkuId'])"
```
Expected: both lines print the same `id` and the same `zkuId`.

### Step 6: PUT by zku_id

```bash
curl -sS -X PUT "http://localhost:8085/api/snippets/$ZKU" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"title":"phase3 updated","tags":"","markup":"markdown","body":"# updated"}' \
  | python3 -m json.tool
```
Expected: response has `"title": "phase3 updated"`, same `"id"` and `"zkuId"`, updated `"updatedAt"`.

### Step 7: DELETE by zku_id then confirm 404 by both identifiers

```bash
curl -sS -i -X DELETE "http://localhost:8085/api/snippets/$ZKU" \
  -H "Authorization: Bearer $TOKEN" | head -5
echo "---"
curl -sS -i -H "Authorization: Bearer $TOKEN" "http://localhost:8085/api/snippets/$ZKU"  | head -3
curl -sS -i -H "Authorization: Bearer $TOKEN" "http://localhost:8085/api/snippets/$UUID" | head -3
```
Expected: DELETE returns `204 No Content`; both subsequent GETs return `404 Not Found`.

### Step 8: Bogus id returns 404 (no crash)

```bash
curl -sS -i -H "Authorization: Bearer $TOKEN" http://localhost:8085/api/snippets/this-is-not-a-real-id | head -3
```
Expected: `HTTP/1.1 404 Not Found`. No 500.

### Step 9: List endpoint returns `zkuId` per item

Create two quick snippets so the list has something, then list:

```bash
for i in A B; do
  curl -sS -X POST http://localhost:8085/api/snippets \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"title\":\"list$i\",\"tags\":\"\",\"markup\":\"markdown\",\"body\":\"$i\"}" \
    > /dev/null
done
curl -sS -H "Authorization: Bearer $TOKEN" "http://localhost:8085/api/snippets?q=list" | python3 -m json.tool | head -40
```
Expected: each item object has an `"id"` and a `"zkuId"` key.

### Step 10: Elm frontend smoke test (optional but valuable)

In a separate terminal, rebuild the frontend (it hasn't changed but this confirms nothing broke):

```bash
cd /Users/carlson/dev/greppit/.worktrees/zku-ids-phase3/frontend
elm make src/Main.elm --optimize --output=elm.js
```
Open `frontend/index.html` in a browser (or use the existing dev setup), sign in as `phase3test@example.com` / `correctbattery`, and poke the UI: list, view, edit, create, delete a snippet. Every action should work exactly as before — the extra `zkuId`/`username` fields in JSON are silently ignored by the Elm decoder.

### Step 11: Stop the dev server

```bash
kill $SERVER_PID 2>/dev/null
```

### Step 12: Leave the test rows in place

These are small and harmless. If you want to clean them up:

```bash
psql greppit_dev -c "DELETE FROM snippets WHERE user_id IN (SELECT id FROM users WHERE email LIKE 'phase3test%'); DELETE FROM users WHERE email LIKE 'phase3test%';"
```

### Step 13: No commit

This task is pure verification.

---

## Task 4: Final stack test + branch summary

### Step 1: Clean test run

```bash
cd /Users/carlson/dev/greppit/.worktrees/zku-ids-phase3/backend
stack test 2>&1 | tail -5
```
Expected: `41 examples, 0 failures`.

### Step 2: Branch state

```bash
cd /Users/carlson/dev/greppit/.worktrees/zku-ids-phase3
git status
git log --oneline main..HEAD
```
Expected: working tree clean; 3 commits above main (spec + feat(api) expose + feat(api) accept zku_id).

---

## Deploy Appendix (reference — performed outside this plan)

After the branch merges to `main` and is pushed to `origin`:

```bash
# On the DO server, as root.
cd ~/greppit
scripts/db-dump-do.sh

git pull

cd backend && stack install --local-bin-path /usr/local/bin
ls -la /usr/local/bin/greppit-backend   # timestamp should be fresh

# Confirm nothing is holding the port:
ss -tlnp | grep 8086
# If a pid shows up:
#   kill <pid>
#   systemctl reset-failed greppit-backend

systemctl restart greppit-backend
systemctl status greppit-backend --no-pager
```

**No migration.** Phase 1 schema already has `zku_id`.

**No re-login required.** `AuthUser` is unchanged in Phase 3 (still `{auUserId, auEmail, auUsername}` from Phase 2). Existing tokens decode cleanly.

**Smoke-test on prod** with the authoritative runbook in `deploy/README.md` ("Backend update" section).

---

## Success Criteria

Phase 3 is done when all of:
1. `stack test` reports `41 examples, 0 failures`.
2. Every `SnippetResponse` JSON body in Task 3's curl transcript contains both `"id"` and `"zkuId"`.
3. `/api/auth/me`, `/api/auth/signup`, and `/api/auth/login` responses all include `"username"`.
4. `GET /api/snippets/<zku_id>` and `GET /api/snippets/<uuid>` return identical payloads.
5. `PUT` and `DELETE` accept the zku_id in the path and succeed.
6. A bogus id string returns 404, not 500.
7. The Elm frontend works unchanged against the new backend (Task 3 Step 10 smoke test).
8. Prod deploy succeeds and manual spot-check (a single `curl /api/auth/me` on prod) shows `"username"` in the response.
