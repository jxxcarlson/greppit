# zku IDs — Phase 2 — Minting on Write (Design Spec)

**Status:** approved 2026-04-23.
**Precedes:** Phase 2 implementation plan (to be written next, under `docs/superpowers/plans/`).
**Succeeds:** Phase 1 (`docs/superpowers/plans/2026-04-23-zku-ids-phase-1-schema.md`).

## 1. Goal

Restore snippet creation and user signup on prod by teaching the backend to mint `users.username` and `snippets.zku_id` at insert time. After Phase 2 ships, every new user has a username derived from their email (matching the Phase 1 backfill algorithm), and every new snippet has a zku_id of the form `<username>-<YYYYMMDDHHMMSS-UTC>`.

Phase 1 added both columns as `UNIQUE NOT NULL` but left existing application code unaware, so any new INSERT after the Phase 1 deploy violates the `NOT NULL` constraint. Phase 2 closes that gap without changing the API or frontend.

## 2. Non-goals

- **API surface** — `SignupRequest`, `UserResponse`, `CreateSnippetRequest`, `SnippetResponse` stay byte-identical. Phase 3 adds `zkuId`/`username` to responses.
- **User-chosen usernames** — usernames are auto-derived. A later phase can add opt-in customization.
- **Frontend changes** — the Elm frontend works entirely with the current API shape; nothing to rebuild.
- **Retiring `snippets.id`** — the UUID primary key stays; `zku_id` is a secondary external identifier.
- **DB integration tests** — deferred. Only pure unit tests added in Phase 2.

## 3. Architecture summary

- New module `Service.Identifiers` holds the pure sanitization and timestamp formatting functions. Unit-tested in isolation.
- `Service.Auth.AuthUser` (the JWT payload) gains an `auUsername` field. Every token issued after Phase 2 carries the creator's username, eliminating a DB lookup on snippet creation.
- `Handler.Auth.signupHandler` computes candidate usernames, INSERTs under a bounded retry loop that distinguishes email-conflict from username-conflict by inspecting the Postgres unique-constraint name.
- `Handler.Snippets.createSnippetHandler` reads `auUsername` from the authenticated `AuthUser`, forms the base zku_id from `<username>-<UTC timestamp>`, INSERTs under the same retry pattern.
- `Db.User` and `Db.Snippet` INSERT statements are extended to include the new columns; SELECT statements for user retrieval are extended to populate `usrUsername` on the `User` record (needed by `loginHandler` to build the JWT payload).

Nothing else moves.

## 4. Component detail

### 4.1 `Service.Identifiers` (new)

```haskell
module Service.Identifiers
  ( sanitizeUsername
  , formatZkuTimestamp
  ) where

import Data.Text (Text)
import Data.Time.Clock (UTCTime)

-- | Strip email local-part down to [a-z0-9], lowercased.
-- Returns Nothing if no characters survive.
sanitizeUsername :: Text -> Maybe Text

-- | Format a UTCTime as YYYYMMDDHHMMSS (14 chars, zero-padded).
formatZkuTimestamp :: UTCTime -> Text
```

**Behavior contracts:**

| Input email local-part       | `sanitizeUsername` result |
|------------------------------|---------------------------|
| `"jxxcarlson"`               | `Just "jxxcarlson"`       |
| `"J.Smith+tag"`              | `Just "jsmithtag"`        |
| `"alice"` (already clean)    | `Just "alice"`            |
| `"jörg"`                     | `Just "jrg"`              |
| `"!!!"`                      | `Nothing`                 |
| `""`                         | `Nothing`                 |
| `"  "` (whitespace)          | `Nothing`                 |

`formatZkuTimestamp` uses `Data.Time.Format.formatTime defaultTimeLocale "%Y%m%d%H%M%S"` on the `UTCTime` as-is — no timezone shift needed since the value is already UTC.

**Match with Phase 1 SQL:** the migration used `lower(regexp_replace(split_part(email,'@',1), '[^a-z0-9]', '', 'gi'))`. The Haskell equivalent: lowercase the input, then keep only chars where `c >= 'a' && c <= 'z' || c >= '0' && c <= '9'`. No regex dependency needed.

### 4.2 `Service.Auth.AuthUser`

```haskell
data AuthUser = AuthUser
  { auUserId   :: Text
  , auEmail    :: Text
  , auUsername :: Text   -- NEW in Phase 2
  }
```

`AuthUser` is signed as the JWT payload. Adding a field changes the JSON shape, so every token issued before Phase 2 will fail to deserialize against the new shape.

**Migration strategy:** no accommodation. On deploy, users with old tokens are effectively logged out and must sign in again. On prod this is a single user (you). Documented in the deploy notes.

### 4.3 `Types.User.User`

```haskell
data User = User
  { usrId        :: Text
  , usrEmail     :: Text
  , usrPwHash    :: Text
  , usrUsername  :: Text   -- NEW in Phase 2
  , usrCreatedAt :: UTCTime
  }
```

Ordering preserved relative to the DB column order that Phase 1 produced: `id, email, pw_hash, username, created_at`. `Db.User.userRow` decoder extends to match.

### 4.4 `Db.User` SQL

```sql
-- insertUser now takes (id, email, pwHash, username):
INSERT INTO users (id, email, pw_hash, username) VALUES ($1, $2, $3, $4)

-- userRow-backed SELECTs include username:
SELECT id, email, pw_hash, username, created_at FROM users WHERE email = $1
SELECT id, email, pw_hash, username, created_at FROM users WHERE id    = $1
```

### 4.5 `Db.Snippet.insertSnippet`

```sql
INSERT INTO snippets (id, user_id, zku_id, title, tags, markup, body)
VALUES ($1, $2, $3, $4, $5, $6, $7)
```

Statement type: `Statement (SnippetId, UserId, Text, Text, Text, Text, Text) ()`.
Other existing statements (`getSnippetById`, `updateSnippet`, `deleteSnippet`, `searchSnippets`, `listAllSnippets`) are **not changed** in Phase 2 — they continue to select the existing columns; `zku_id` is not exposed yet.

### 4.6 Signup flow (`Handler.Auth.signupHandler`)

```
1. base <- sanitizeUsername (localPart of srEmail req)
   On Nothing → throwError 400 with
     "We couldn't create a username from your email. Please use an
      email that contains letters or numbers before the '@' sign."
2. Generate fresh UUID user_id and password hash as today.
3. candidates = [base, base<>"2", base<>"3", ..., base<>"100"]
4. For each candidate, attempt:
     Db.insertUser (userId, email, pwHash, candidate)
   On Right () → success, remember the chosen candidate.
   On Left err:
     case uniqueViolationConstraint err of
       Just "users_email_key"    → throwError 409 "email already registered"
       Just "users_username_key" → continue loop
       _                         → throwError 500 "database error"
5. If loop exhausts all 100 candidates without success:
     throwError 500 "could not derive a unique username"
   (log at error level; in practice unreachable)
6. Build AuthUser { auUserId, auEmail, auUsername = chosen }
   Sign JWT, return AuthResponse.
```

### 4.7 Snippet create flow (`Handler.Snippets.createSnippetHandler`)

```
1. auth -> AuthUser (as today). Extract auUsername and auUserId.
2. now <- liftIO getCurrentTime
3. baseZku = auUsername <> "-" <> formatZkuTimestamp now
4. Generate UUID sid (internal PK, as today).
5. candidates = [baseZku, baseZku<>"-2", baseZku<>"-3", ..., baseZku<>"-100"]
6. For each candidate:
     Db.insertSnippet (sid, userId, candidate, title, tags, markup, body)
   On Right () → success.
   On Left err:
     case uniqueViolationConstraint err of
       Just "snippets_zku_id_key" → continue loop
       _                          → throwError 500
7. If loop exhausts → throwError 500 "could not derive a unique zku_id"
   (log; pathological batch-import only)
8. Return existing SnippetResponse (zku_id not exposed yet — Phase 3).
```

### 4.8 `uniqueViolationConstraint`

Replaces today's boolean `isUniqueViolation` (Handler/Auth.hs:98) with a constraint-name extractor:

```haskell
uniqueViolationConstraint :: Pool.UsageError -> Maybe Text
uniqueViolationConstraint (Pool.SessionUsageError
  (Session.QueryError _ _
    (Session.ResultError
      (Session.ServerError code msg _ _ _))))
  | code == "23505" = extractConstraint msg
  | otherwise       = Nothing
uniqueViolationConstraint _ = Nothing
  where
    -- Postgres formats unique violations as:
    --   duplicate key value violates unique constraint "NAME"
    -- Extract NAME from the first pair of double quotes.
    extractConstraint :: ByteString -> Maybe Text
```

The existing call site in `signupHandler` (line 44) changes from `isUniqueViolation err` to `uniqueViolationConstraint err == Just "users_email_key"`.

`isUniqueViolation` is removed. Nothing else references it.

## 5. Error handling

| Situation                                                | Response                                                                                                   | HTTP |
|----------------------------------------------------------|------------------------------------------------------------------------------------------------------------|------|
| Signup with invalid email local-part                     | `{error: "We couldn't create a username from your email. Please use an email that contains letters or numbers before the '@' sign."}` | 400  |
| Signup with already-registered email                     | `{error: "email already registered"}` (existing)                                                           | 409  |
| Signup exhausts 100 username candidates                  | `{error: "could not derive a unique username"}` (logged)                                                   | 500  |
| Snippet create exhausts 100 zku_id candidates            | `{error: "could not derive a unique zku_id"}` (logged)                                                     | 500  |
| Any other DB error                                       | `{error: "database error"}` (existing behavior)                                                            | 500  |

## 6. Testing

### 6.1 New: `Service.IdentifiersSpec`

- `sanitizeUsername` cases from the table in §4.1.
- `formatZkuTimestamp` on a fixed UTC input (e.g., `2026-04-23 14:30:22 UTC`) asserts the exact 14-char output `"20260423143022"`.
- Round-trip spot check: `sanitizeUsername` of a bunch of plausible email local-parts produces strings matching `[a-z0-9]+` (mirrors Phase 1's A3 assertion in the migration's validation).

### 6.2 Unchanged

`Service.TagsSpec`, `Service.SearchSpec`, `Service.AuthSpec`. All 30 existing tests must still pass.

### 6.3 Manual verification (part of the deploy check)

After the Phase 2 binary is restarted on dev:

1. Create a new user via the signup endpoint with a novel email.
2. Confirm `SELECT username FROM users WHERE email = '<new>';` returns the expected sanitized form.
3. Log in as that user.
4. Create a snippet via the create endpoint.
5. Confirm `SELECT zku_id FROM snippets WHERE user_id = '<new-user-id>';` returns `<username>-<14-digit-UTC>`.
6. Create two snippets rapidly; confirm the second has `-2` suffix.

Then repeat on prod.

## 7. Deploy notes

- **Requires backend restart.** No schema change in Phase 2, so dbmate is not involved. `git pull && stack build && systemctl restart greppit-backend` is the whole deploy.
- **Re-login required.** The JWT payload shape changed. Anyone with an old token will get a 401 once the new binary takes over; resolution is to log in again. Zero data migration.
- **Fixes the Phase 1 write bug.** Between Phase 1 deploy and Phase 2 deploy, signup and snippet-create are 500-ing. Phase 2 restarts resolve this.

## 8. Success criteria

Phase 2 is done when all of:

1. `Service.IdentifiersSpec` is added and passes; whole suite is `≥ 32 examples, 0 failures`.
2. Signup handler minting + retry loop + email/username conflict branching is implemented and passes a manual dev round-trip (new user gets correct username; duplicate email returns 409; all-symbol email local-part returns 400 with the friendly message).
3. Snippet create handler mints zku_id, retries on collision, passes a manual round-trip (single create succeeds; two rapid creates produce `<base>` and `<base>-2`).
4. `AuthUser` carries `auUsername`; logging in and then creating a snippet reflects that username in the DB.
5. Deployed to prod; manual verification confirms signup and snippet creation work (closing the Phase 1 write-bug window).

## 9. Future work (explicitly deferred)

- Phase 3: expose `zkuId` and `username` in JSON responses; accept `zkuId` as URL path parameter.
- Phase 4: Elm frontend surfaces the new identifier.
- User-chosen usernames (post-phase-4).
- DB integration tests (general project improvement).
- Username/zku_id retry-exhaustion: if ever observed in the wild, upgrade to a different strategy (e.g., random suffix, or pre-SELECT max suffix).
- Retiring `snippets.id` in favor of `zku_id` as the primary key — low priority; only worth the migration if the UUID becomes a real cost somewhere.
