# `@all` Search Sentinel Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `GET /api/snippets?q=@all` return every snippet for the authenticated user (no filter, no `LIMIT`), while leaving every other query path unchanged.

**Architecture:** Pure helper in `Service.Search` recognizes the `@all` sentinel (trimmed, case-insensitive). Handler dispatches to either the existing `searchSnippets` statement or a new no-limit `listAllSnippets` statement. No frontend change.

**Tech Stack:** Haskell, Servant, Hasql, Hspec.

**Spec:** `docs/superpowers/specs/2026-04-21-at-all-search-sentinel-design.md`

---

## File Structure

- **Modify** `backend/src/Service/Search.hs` — export new `isAllSentinel :: Maybe Text -> Bool`.
- **Modify** `backend/src/Db/Snippet.hs` — export new `listAllSnippets :: Statement UserId (Vector Snippet)`.
- **Modify** `backend/src/Handler/Snippets.hs` — dispatch in `listSnippetsHandler`.
- **Modify** `backend/test/Service/SearchSpec.hs` — add `isAllSentinel` tests.

All four files already exist; no new modules are created.

---

## Task 1: `Service.Search.isAllSentinel` helper (TDD)

**Files:**
- Modify: `backend/src/Service/Search.hs`
- Test: `backend/test/Service/SearchSpec.hs`

- [ ] **Step 1: Add failing tests**

Append to `backend/test/Service/SearchSpec.hs` (after the existing `describe` block, inside the same `spec`):

```haskell
  describe "Service.Search.isAllSentinel" $ do
    it "is False for Nothing"          $ Search.isAllSentinel Nothing               `shouldBe` False
    it "is False for empty string"     $ Search.isAllSentinel (Just "")             `shouldBe` False
    it "is False for whitespace only"  $ Search.isAllSentinel (Just "   ")          `shouldBe` False
    it "is True for @all exact"        $ Search.isAllSentinel (Just "@all")         `shouldBe` True
    it "is True for @all with spaces"  $ Search.isAllSentinel (Just "  @all  ")     `shouldBe` True
    it "is True for @ALL (upper)"      $ Search.isAllSentinel (Just "@ALL")         `shouldBe` True
    it "is True for mixed case @All"   $ Search.isAllSentinel (Just "@All")         `shouldBe` True
    it "is False for @all with other terms" $
      Search.isAllSentinel (Just "@all foo")        `shouldBe` False
    it "is False for foo @all"         $ Search.isAllSentinel (Just "foo @all")     `shouldBe` False
    it "is False for @alll"            $ Search.isAllSentinel (Just "@alll")        `shouldBe` False
    it "is False for all (no @)"       $ Search.isAllSentinel (Just "all")          `shouldBe` False
```

Note: this lives inside the existing top-level `spec :: Spec` — convert the current `spec = describe "..." $ do ...` into two sibling `describe` blocks under one `spec`. If the current file's top form is:

```haskell
spec :: Spec
spec = describe "Service.Search.termsToIlikePatterns" $ do
  ...
```

Change it to:

```haskell
spec :: Spec
spec = do
  describe "Service.Search.termsToIlikePatterns" $ do
    ...  -- (unchanged existing tests)

  describe "Service.Search.isAllSentinel" $ do
    ...  -- (new tests above)
```

- [ ] **Step 2: Run the tests — expect failure**

From `backend/`:

```
stack test
```

Expected: compile error (`isAllSentinel` not in scope) or the new `describe` block failing. Either counts as a red test.

- [ ] **Step 3: Implement `isAllSentinel`**

Edit `backend/src/Service/Search.hs`. Update the module export list and add the function:

```haskell
module Service.Search
  ( termsToIlikePatterns
  , isAllSentinel
  ) where

-- (existing imports and code unchanged)

-- | True iff the query is the literal sentinel @all, after trimming
-- surrounding whitespace and folding case. Any other value — including
-- @all combined with other tokens — is False.
isAllSentinel :: Maybe Text -> Bool
isAllSentinel Nothing  = False
isAllSentinel (Just t) = T.toLower (T.strip t) == "@all"
```

- [ ] **Step 4: Run the tests — expect pass**

From `backend/`:

```
stack test
```

Expected: all tests pass, including the 11 new `isAllSentinel` cases.

- [ ] **Step 5: Commit**

```
git add backend/src/Service/Search.hs backend/test/Service/SearchSpec.hs
git commit -m "feat(search): add isAllSentinel helper for @all query"
```

---

## Task 2: `Db.Snippet.listAllSnippets` statement

**Files:**
- Modify: `backend/src/Db/Snippet.hs`

No new unit tests — this is a thin SQL statement covered by the manual API test in Task 4. (The existing codebase does not unit-test `Db.*` statements.)

- [ ] **Step 1: Add statement and export it**

In `backend/src/Db/Snippet.hs`, add `listAllSnippets` to the export list:

```haskell
module Db.Snippet
  ( insertSnippet
  , getSnippetById
  , updateSnippet
  , deleteSnippet
  , searchSnippets
  , listAllSnippets
  ) where
```

At the bottom of the file, append:

```haskell
-- | List every snippet owned by the user, newest-updated first.
-- No text filter. No LIMIT. Used by the @all sentinel path.
listAllSnippets :: Statement UserId (Vector Snippet)
listAllSnippets = Statement sql encoder (D.rowVector snippetRow) True
  where
    sql = "SELECT id, user_id, title, tags, markup, body, created_at, updated_at \
          \FROM snippets \
          \WHERE user_id = $1 \
          \ORDER BY updated_at DESC"
    encoder = E.param (E.nonNullable E.text)
```

- [ ] **Step 2: Build to verify it compiles**

From `backend/`:

```
stack build
```

Expected: clean build with no errors or warnings about the new function.

- [ ] **Step 3: Commit**

```
git add backend/src/Db/Snippet.hs
git commit -m "feat(db): add listAllSnippets statement (no limit)"
```

---

## Task 3: Dispatch sentinel in `listSnippetsHandler`

**Files:**
- Modify: `backend/src/Handler/Snippets.hs`

- [ ] **Step 1: Update `listSnippetsHandler` to branch on the sentinel**

In `backend/src/Handler/Snippets.hs`, replace the current `listSnippetsHandler` (lines 61–71) with:

```haskell
listSnippetsHandler
  :: AuthResult AuthUser -> Maybe Text -> AppM [SnippetResponse]
listSnippetsHandler auth mq = do
  userId <- requireUser auth
  pool   <- asks envDbPool
  result <- liftIO $ Pool.use pool $
    if Search.isAllSentinel mq
      then Session.statement userId Db.listAllSnippets
      else let patterns = Search.termsToIlikePatterns mq
           in Session.statement (userId, patterns) Db.searchSnippets
  case result of
    Left _    -> throwError $ appErrorToServantErr (InternalError "database error")
    Right vec -> pure $ map toResp (V.toList vec)
```

No new imports are needed — `Search` and `Db` are already qualified-imported at the top of the file.

- [ ] **Step 2: Build to verify it compiles**

From `backend/`:

```
stack build
```

Expected: clean build.

- [ ] **Step 3: Run the test suite**

From `backend/`:

```
stack test
```

Expected: all tests pass (no new unit tests here, but this guards against regressions in `Service.Search` and `Service.Tags`).

- [ ] **Step 4: Commit**

```
git add backend/src/Handler/Snippets.hs
git commit -m "feat(snippets): dispatch @all sentinel to listAllSnippets"
```

---

## Task 4: Manual API verification

**Files:** none modified.

This is a smoke test against a running backend. Skip gracefully if the engineer cannot run Postgres locally — the unit tests in Task 1 plus the clean build in Tasks 2–3 are the primary verification gate.

- [ ] **Step 1: Start the backend**

From `backend/`:

```
./run.sh
```

Expected: server listening on `:8085`.

- [ ] **Step 2: Acquire a token and seed > 5 snippets**

Use the existing `backend/test-api.sh` flow (or manual `curl`) to:
1. Sign up or log in a test user, capture the JWT into `$TOKEN`.
2. `POST /api/snippets` six or more times with distinct titles.

Example seed loop:

```
for i in 1 2 3 4 5 6; do
  curl -s -X POST http://localhost:8085/api/snippets \
    -H "Authorization: Bearer $TOKEN" \
    -H 'Content-Type: application/json' \
    -d "{\"title\":\"seed $i\",\"tags\":\"\",\"markup\":\"plaintext\",\"body\":\"body $i\"}" >/dev/null
done
```

- [ ] **Step 3: Confirm empty query still caps at 5**

```
curl -s -H "Authorization: Bearer $TOKEN" \
  'http://localhost:8085/api/snippets' | jq 'length'
```

Expected: `5`.

- [ ] **Step 4: Confirm `@all` returns every snippet**

```
curl -s -H "Authorization: Bearer $TOKEN" \
  'http://localhost:8085/api/snippets?q=@all' | jq 'length'
```

Expected: `6` (or however many were seeded for this user — strictly greater than 5).

- [ ] **Step 5: Confirm case-insensitivity**

```
curl -s -H "Authorization: Bearer $TOKEN" \
  'http://localhost:8085/api/snippets?q=@ALL' | jq 'length'
```

Expected: same count as Step 4.

- [ ] **Step 6: Confirm `@all foo` is a literal search, not the sentinel**

```
curl -s -H "Authorization: Bearer $TOKEN" \
  --data-urlencode 'q=@all foo' \
  -G 'http://localhost:8085/api/snippets' | jq 'length'
```

Expected: `0` (no snippet body contains the literal `@all`), and at most `5` in any case.

- [ ] **Step 7: No commit needed — this task creates no files.**

---

## Done Criteria

- `stack test` from `backend/` passes with new `isAllSentinel` cases.
- `stack build` from `backend/` produces no warnings on the modified files.
- Manual API calls in Task 4 match expectations.
- Four commits on the branch, one per implementation task (Task 4 has none).
