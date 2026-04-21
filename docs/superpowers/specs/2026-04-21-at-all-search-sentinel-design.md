# `@all` Search Sentinel

## Summary

Introduce an `@all` search sentinel: when the trimmed, case-folded search
query equals `@all`, `GET /api/snippets` returns every snippet owned by the
authenticated user — no text filter, no `LIMIT`. All other queries behave
exactly as before (whitespace-split ILIKE patterns, `LIMIT 5`).

## Motivation

The existing list endpoint always applies `LIMIT 5` via
`Db.Snippet.searchSnippets`. There is no way for a user to retrieve the full
set of their snippets through the search input. `@all` is a low-ceremony,
discoverable sentinel to surface that capability without adding a separate
UI control.

## Semantics

- **Trigger:** `q` parameter, trimmed of surrounding whitespace, compared
  case-insensitively, equals the literal `@all`.
- **Examples that trigger:** `@all`, `  @all  `, `@ALL`, `@All`.
- **Examples that do NOT trigger (treated as literal search):**
  `@all foo`, `foo @all`, `@alll`, `all`, `@a`.
- **Result on trigger:** all snippets for the authenticated user,
  ordered by `updated_at DESC`, no limit.
- **Result otherwise:** unchanged — ILIKE ALL over `title || ' ' || tags || ' ' || body`, `LIMIT 5`.

## Implementation

### Backend only. No frontend change.

1. **`Service/Search.hs`** — add a pure helper:
   ```haskell
   isAllSentinel :: Maybe Text -> Bool
   ```
   Returns `True` iff the input is `Just t` and `T.toLower (T.strip t) == "@all"`.

2. **`Db/Snippet.hs`** — add a new statement:
   ```haskell
   listAllSnippets :: Statement UserId (Vector Snippet)
   ```
   SQL:
   ```sql
   SELECT id, user_id, title, tags, markup, body, created_at, updated_at
   FROM snippets
   WHERE user_id = $1
   ORDER BY updated_at DESC
   ```
   No `ILIKE`, no `LIMIT`. Reuses existing `snippetRow` decoder.

3. **`Handler/Snippets.hs listSnippetsHandler`** — dispatch on the sentinel
   before building ILIKE patterns:
   ```haskell
   if Search.isAllSentinel mq
     then run listAllSnippets
     else run searchSnippets with termsToIlikePatterns mq
   ```
   On error, same `InternalError "database error"` path as today.

### Out of scope

- No frontend change: the sentinel is a normal `q` value.
- No pagination or new query parameters.
- No change to the existing `searchSnippets` statement or
  `termsToIlikePatterns` behavior.

## Testing

- Unit test `isAllSentinel` on: `Nothing`, `Just ""`, `Just "@all"`,
  `Just "  @ALL  "`, `Just "@all foo"`, `Just "all"`.
- Manual / API test (via `backend/test-api.sh` or equivalent):
  create ≥ 6 snippets for a user; confirm `q=@all` returns all of them
  and `q=` (empty) still returns only 5.
