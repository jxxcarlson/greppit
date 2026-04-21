# Snippet List: Total Count + Revised Search Limits

## Summary

Three coordinated changes to `GET /api/snippets` and the frontend header:

1. **API shape change:** the endpoint returns `{ total, results }` instead of
   a bare array. `total` is the user's full snippet count; `results` is the
   list of snippets matching the current query.
2. **Revised limits:**
   - Empty / whitespace query → the 20 most recent snippets.
   - `@all` sentinel → every snippet for the user (unchanged).
   - Any other query → every match, capped at 500 as a safety ceiling.
3. **Header count display:** the existing "N snippets" tag becomes
   "M/N snippets", where M is the number currently displayed and N is the
   total. Hidden when N = 0.

## Motivation

Users need a quick indication of how much of their collection is currently in
view. The old `5 snippets` label was ambiguous — it didn't distinguish "you
have 5 total" from "you have many but only 5 are shown right now." The new
`M/N` form makes the relationship explicit and lets the backend lift the
old hardcoded `LIMIT 5` to more useful limits.

## Semantics

### Query → result-set rule

| `q` (as sent) | Matches        | Limit |
|---------------|----------------|-------|
| missing / empty / all-whitespace | user's full set | 20 most recent by `updated_at` |
| trimmed, case-folded equals `@all` | user's full set | no limit |
| anything else | ILIKE ALL the terms | no limit, safety cap 500 |

The `@all` sentinel and the empty case are already distinguishable: the
handler routes to `listAllSnippets` first on the sentinel, then to the
"empty" path only if `termsToIlikePatterns` returned an empty vector.

### Response shape

```json
{
  "total": 42,
  "results": [ { "id": "...", "title": "...", ... }, ... ]
}
```

`total` is `count(*)` of the authenticated user's snippets — the same
regardless of the query. `results` is the query's output, in the same
per-snippet shape used today.

### Header display

- `totalCount > 0` → render `"M/N snippets"` (always plural).
  M = `List.length results`, N = `totalCount`.
- `totalCount == 0` → render nothing.
- Not logged in → render nothing (unchanged).

## Implementation

### Backend

**`Api/RequestTypes.hs`** — add:

```haskell
data SnippetListResponse = SnippetListResponse
  { slrTotal   :: Int
  , slrResults :: [SnippetResponse]
  } -- ToJSON: { "total": ..., "results": [...] }
```

**`Api/Snippets.hs`** (route type) — change `GET /api/snippets` return type
from `[SnippetResponse]` to `SnippetListResponse`.

**`Db/Snippet.hs`** — four changes:

- Add `recentSnippets :: Statement UserId (Vector Snippet)`:
  ```
  SELECT <columns> FROM snippets
  WHERE user_id = $1
  ORDER BY updated_at DESC
  LIMIT 20
  ```
- Add `countSnippets :: Statement UserId Int`:
  ```
  SELECT count(*)::int FROM snippets WHERE user_id = $1
  ```
- Modify `searchSnippets`: drop `LIMIT 5`, replace with `LIMIT 500`.
- `listAllSnippets` unchanged.

**`Handler/Snippets.hs listSnippetsHandler`** — in a single `Pool.use`,
run `countSnippets` plus one of the three list statements based on the
query, then build a `SnippetListResponse`:

```haskell
result <- liftIO $ Pool.use pool $ do
  total <- Session.statement userId Db.countSnippets
  rows  <- if Search.isAllSentinel mq
    then Session.statement userId Db.listAllSnippets
    else case Search.termsToIlikePatterns mq of
           ps | V.null ps -> Session.statement userId Db.recentSnippets
              | otherwise -> Session.statement (userId, ps) Db.searchSnippets
  pure (total, rows)
```

On `Left`, keep the existing `InternalError "database error"` path.
On `Right (total, vec)`, assemble `SnippetListResponse total (map toResp (V.toList vec))`.

### Frontend

**`Types.elm`** — add:

```elm
type alias SnippetListResponse =
    { total : Int
    , results : List Snippet
    }
```

Extend the `Signed` state with `totalCount : Int` (initialized to `0`).

**`Api.elm listSnippets`** — change the decoder from
`D.list snippetDecoder` to a decoder for `SnippetListResponse`
(`total` as `D.int`, `results` as `D.list snippetDecoder`). The `toMsg`
callback signature changes from `List Snippet` to `SnippetListResponse`.

**`Main.elm`** — handler updates:

- `SearchResponded (Ok resp)`: set `results = resp.results` and
  `totalCount = resp.total`.
- Create success: `totalCount` += 1; `results = newSnippet :: s.results`
  (drop the old `List.take 4` — it existed solely to respect the old
  LIMIT 5).
- Delete success: `totalCount` -= 1; filter `results` as today.

**`Main.elm header`** — the `mInfo` record grows a `total` field:

```elm
header :
    Maybe { email : String, displayed : Int, total : Int } -> Html Msg
```

and the call site in the signed-in branch passes
`{ email, displayed = List.length s.results, total = s.totalCount }`.

Replace `snippetCountText`:

```elm
snippetCountText : { displayed : Int, total : Int } -> String
snippetCountText r =
    String.fromInt r.displayed ++ "/" ++ String.fromInt r.total ++ " snippets"
```

Render the count div only when `total > 0`.

### Out of scope

- Pagination (no `?offset` / `?page`).
- Exposing the 500 cap to the user or returning a "truncated" flag.
- Changes to the create / update / delete endpoints' response shapes.
- Any frontend test additions (codebase has none for list behavior).

## Testing

**Backend (hspec):** no new unit tests needed — the existing
`termsToIlikePatterns` and `isAllSentinel` tests still cover the pure
dispatch logic. The new statements (`recentSnippets`, `countSnippets`) are
thin SQL, following the convention that `Db.*` statements are exercised
only by the integration smoke test.

**Integration smoke test (manual, via curl + jq):**

1. New user, seed ~25 snippets (to exceed the 20-recent cap but stay under
   the 500-match cap).
2. `q=""` → response `{ total: 25, results.length: 20 }`.
3. `q=@all` → response `{ total: 25, results.length: 25 }`.
4. `q=<shared term>` where every snippet matches → response
   `{ total: 25, results.length: 25 }`.
5. `q=<term in one snippet>` → response `{ total: 25, results.length: 1 }`.
6. Header (browser): on (2), "20/25 snippets"; on (3), "25/25 snippets";
   on (5), "1/25 snippets". Delete all 25 → count div vanishes.
