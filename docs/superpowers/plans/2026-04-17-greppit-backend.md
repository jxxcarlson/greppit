# Greppit Backend Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the greppit v1 backend: a Postgres-backed JSON API for email/password auth and personal snippet CRUD with conjunctive ILIKE search, with integration tests that exercise the full flow.

**Architecture:** Haskell + Servant (HTTP) + Hasql (Postgres) + JWT (`servant-auth-server`). Layout mirrors `/Users/carlson/dev/elm-work/scripta/scripta-app-v4/backend/` minus `WebSocket/`. Migrations via `dbmate`. Two tables (`users`, `snippets`). Search uses Postgres `ILIKE ALL (ARRAY[...])` so we can pass a variable-length terms array as one statement.

**Tech Stack:** GHC via `stack` (resolver `lts-22.43`), `servant`, `servant-auth-server`, `hasql`, `hasql-pool`, `aeson`, `bcrypt`, `jose`, `uuid`, `wai-cors`, `warp`. Tests: `hspec`. Integration: `bash` + `curl` + `jq` (matches scripta-app-v4).

**Reference project:** `/Users/carlson/dev/elm-work/scripta/scripta-app-v4/backend/` — use as pattern source. Copy-adapt rather than invent.

**Prerequisites assumed installed:** `stack`, `dbmate`, a running local Postgres, `jq`, `curl`. Port `8085` (not 8000–8010, per user convention).

---

## File Structure

```
backend/
  package.yaml
  stack.yaml
  .gitignore
  run.sh
  test-api.sh
  dbmate/
    migrations/
      001_initial_schema.sql
  app/
    Main.hs
  src/
    App.hs
    AppEnv.hs
    AppError.hs
    Config.hs
    Lib.hs
    Api/
      Auth.hs
      RequestTypes.hs
      Snippets.hs
      Types.hs
    Db/
      Pool.hs
      Snippet.hs
      User.hs
    Handler/
      Auth.hs
      Snippets.hs
    Service/
      Auth.hs
      Search.hs
      Tags.hs
    Types/
      Common.hs
      Snippet.hs
      User.hs
  test/
    Spec.hs
    Service/
      TagsSpec.hs
      SearchSpec.hs
      AuthSpec.hs
```

**Per-file responsibility:**

- `Config.hs` — load env vars (`DATABASE_URL`, `JWT_SECRET`, `PORT`).
- `AppEnv.hs` — runtime context (db pool, JWT settings). `AppM = ReaderT AppEnv Handler`.
- `AppError.hs` — domain errors; converter to `ServerError`.
- `Db/Pool.hs` — `hasql-pool` setup.
- `Db/User.hs` / `Db/Snippet.hs` — Hasql `Statement`s only. No business logic.
- `Service/Auth.hs` — bcrypt wrappers, JWT settings, `AuthUser` type (JWT subject).
- `Service/Tags.hs` — `normalizeTags :: Text -> Text` (lowercase, collapse whitespace).
- `Service/Search.hs` — `parseTerms :: Maybe Text -> Vector Text` → list of `%term%` patterns for `ILIKE ALL`.
- `Api/*.hs` — Servant API *types* only.
- `Api/RequestTypes.hs` — JSON request/response record types with aeson codecs.
- `Handler/*.hs` — `AppM` handlers. Bind DB + service + request/response.
- `App.hs` — `startApp`, `server`, `mkApp`, CORS.

---

## Global Conventions (apply to every task)

- **Module header pragmas:** start every non-trivial module with `{-# LANGUAGE OverloadedStrings #-}`. Add `DeriveGeneric`, `DataKinds`, `TypeOperators` where Servant/aeson need them. If you see `Couldn't match expected type Text with actual type [Char]`, add `OverloadedStrings`.
- **JSON field naming:** use the `stripPrefixOptions` helper from scripta-app-v4 (we will copy it into `Api/RequestTypes.hs`) so Haskell records can keep a short prefix while JSON uses clean `camelCase`.
- **Errors:** never `error`; always `throwError $ appErrorToServantErr <error>`.
- **IDs:** UUIDv4 generated server-side at signup/create; stored as `TEXT`.
- **Commits:** one commit per completed task (messages given per task). Run `stack build` before any commit of Haskell changes; fix compile errors before committing.
- **Test DB:** for `stack test` we use the same local Postgres database; tests that touch the DB create a unique temp user and clean up. Pure (`Tags`, `Search`, `Auth`) tests do not hit the DB.

---

### Task 1: Project scaffolding

**Files:**
- Create: `backend/package.yaml`
- Create: `backend/stack.yaml`
- Create: `backend/.gitignore`
- Create: `backend/app/Main.hs` (placeholder)
- Create: `backend/src/Lib.hs` (placeholder)
- Create: `backend/test/Spec.hs` (placeholder)

- [ ] **Step 1: Create `backend/package.yaml`**

```yaml
name: greppit-backend
version: 0.1.0.0

dependencies:
  - base >= 4.7 && < 5
  - aeson
  - bcrypt
  - bytestring
  - containers
  - hasql
  - hasql-pool >= 0.9 && < 1
  - http-types
  - jose
  - mtl
  - servant
  - servant-auth
  - servant-auth-server
  - servant-server
  - text
  - time
  - transformers
  - uuid
  - vector
  - wai
  - wai-cors
  - warp

library:
  source-dirs: src

executables:
  greppit-backend:
    main: Main.hs
    source-dirs: app
    dependencies:
      - greppit-backend
    ghc-options:
      - -threaded
      - -rtsopts
      - -with-rtsopts=-N

tests:
  greppit-backend-test:
    main: Spec.hs
    source-dirs: test
    dependencies:
      - greppit-backend
      - hspec
```

- [ ] **Step 2: Create `backend/stack.yaml`**

```yaml
resolver: lts-22.43

packages:
  - .

extra-deps: []

# macOS libpq paths (adjust for your system if not using Homebrew on Apple Silicon)
extra-include-dirs:
  - /opt/homebrew/opt/libpq/include
extra-lib-dirs:
  - /opt/homebrew/opt/libpq/lib
```

- [ ] **Step 3: Create `backend/.gitignore`**

```
.stack-work/
dist-newstyle/
*.cabal
.env
```

- [ ] **Step 4: Create placeholder `backend/app/Main.hs`**

```haskell
module Main where

main :: IO ()
main = putStrLn "greppit backend starting..."
```

- [ ] **Step 5: Create placeholder `backend/src/Lib.hs`**

```haskell
module Lib (placeholder) where

placeholder :: String
placeholder = "greppit"
```

- [ ] **Step 6: Create placeholder `backend/test/Spec.hs`**

```haskell
module Main where

main :: IO ()
main = putStrLn "tests not yet implemented"
```

- [ ] **Step 7: Verify project builds**

Run: `cd backend && stack build`
Expected: first-time stack setup may take several minutes; ends with successful build. No compiler errors.

- [ ] **Step 8: Commit**

```bash
git add backend/package.yaml backend/stack.yaml backend/.gitignore \
        backend/app/Main.hs backend/src/Lib.hs backend/test/Spec.hs
git commit -m "scaffold greppit-backend project with stack + hpack"
```

---

### Task 2: Config module (env-driven)

**Files:**
- Create: `backend/src/Config.hs`
- Modify: `backend/app/Main.hs`

- [ ] **Step 1: Write `backend/src/Config.hs`**

```haskell
module Config (Config(..), loadConfig) where

import Data.ByteString (ByteString)
import Data.Text (pack)
import Data.Text.Encoding (encodeUtf8)
import System.Environment (lookupEnv)

data Config = Config
  { configDbUrl         :: ByteString
  , configJwtSecret     :: ByteString
  , configJwtExpiryDays :: Int
  , configPort          :: Int
  } deriving (Show)

loadConfig :: IO Config
loadConfig = do
  dbUrl     <- envOrDefault "DATABASE_URL" "postgres://localhost/greppit_dev"
  jwtSecret <- envOrDefault "JWT_SECRET"   "dev-secret-change-in-production-min-32-chars!!"
  jwtExpiry <- envIntOrDefault "JWT_EXPIRY_DAYS" 7
  port      <- envIntOrDefault "PORT" 8085
  pure Config
    { configDbUrl         = encodeUtf8 (pack dbUrl)
    , configJwtSecret     = encodeUtf8 (pack jwtSecret)
    , configJwtExpiryDays = jwtExpiry
    , configPort          = port
    }

envOrDefault :: String -> String -> IO String
envOrDefault name def = maybe def id <$> lookupEnv name

envIntOrDefault :: String -> Int -> IO Int
envIntOrDefault name def = maybe def read <$> lookupEnv name
```

- [ ] **Step 2: Wire Config into Main.hs so it at least loads**

Replace `backend/app/Main.hs` with:

```haskell
module Main where

import Config (loadConfig)

main :: IO ()
main = do
  cfg <- loadConfig
  putStrLn $ "greppit backend: loaded config with port=" <> show cfg
```

- [ ] **Step 3: Build and run**

Run: `cd backend && stack build && stack exec greppit-backend`
Expected: prints a `Config { ... }` line ending with `... configPort = 8085 }`.

- [ ] **Step 4: Commit**

```bash
git add backend/src/Config.hs backend/app/Main.hs backend/package.yaml
git commit -m "add Config module with env-driven defaults"
```

---

### Task 3: AppEnv, AppError, Db/Pool

**Files:**
- Create: `backend/src/AppEnv.hs`
- Create: `backend/src/AppError.hs`
- Create: `backend/src/Db/Pool.hs`

- [ ] **Step 1: Create `backend/src/AppEnv.hs`**

```haskell
module AppEnv
  ( AppEnv(..)
  , AppM
  ) where

import Control.Monad.Reader (ReaderT)
import qualified Hasql.Pool as Pool
import Servant (Handler)
import Servant.Auth.Server (JWTSettings, CookieSettings)

data AppEnv = AppEnv
  { envDbPool         :: Pool.Pool
  , envJwtSettings    :: JWTSettings
  , envCookieSettings :: CookieSettings
  , envPort           :: Int
  , envJwtExpiryDays  :: Int
  }

type AppM = ReaderT AppEnv Handler
```

- [ ] **Step 2: Create `backend/src/AppError.hs`**

```haskell
{-# LANGUAGE OverloadedStrings #-}

module AppError
  ( AppError(..)
  , appErrorToServantErr
  ) where

import Data.Aeson (object, (.=), encode)
import Data.Text (Text)
import Servant (ServerError(..), err400, err401, err403, err404, err409, err500)

data AppError
  = NotFound
  | Forbidden
  | Unauthorized
  | Conflict Text
  | InvalidInput Text
  | InternalError Text
  deriving (Show, Eq)

appErrorToServantErr :: AppError -> ServerError
appErrorToServantErr NotFound =
  err404 { errBody = encode $ object
    ["error" .= ("not_found" :: Text), "message" .= ("Not found" :: Text)] }
appErrorToServantErr Forbidden =
  err403 { errBody = encode $ object
    ["error" .= ("forbidden" :: Text), "message" .= ("Forbidden" :: Text)] }
appErrorToServantErr Unauthorized =
  err401 { errBody = encode $ object
    ["error" .= ("unauthorized" :: Text), "message" .= ("Unauthorized" :: Text)] }
appErrorToServantErr (Conflict msg) =
  err409 { errBody = encode $ object
    ["error" .= ("conflict" :: Text), "message" .= msg] }
appErrorToServantErr (InvalidInput msg) =
  err400 { errBody = encode $ object
    ["error" .= ("invalid_input" :: Text), "message" .= msg] }
appErrorToServantErr (InternalError msg) =
  err500 { errBody = encode $ object
    ["error" .= ("internal_error" :: Text), "message" .= msg] }
```

- [ ] **Step 3: Create `backend/src/Db/Pool.hs`**

```haskell
module Db.Pool (createPool) where

import Data.ByteString (ByteString)
import Data.Time.Clock (DiffTime)
import qualified Hasql.Pool as Pool

createPool :: ByteString -> IO Pool.Pool
createPool connSettings =
  Pool.acquire poolSize acquireTimeout idleTimeout maxLifetime connSettings
  where
    poolSize, _unused :: Int
    poolSize = 10
    _unused = 0
    acquireTimeout, idleTimeout, maxLifetime :: DiffTime
    acquireTimeout = 10
    idleTimeout = 600
    maxLifetime = 3600
```

(The `_unused` is only to anchor the type signature comment; you can delete it — it is there to suppress a warning if `poolSize` style causes one. If `stack build` flags it, just drop it.)

- [ ] **Step 4: Register the new modules in package.yaml's library**

hpack derives the module list from source-dirs automatically — no change needed. But verify by running `cd backend && stack build`.

Expected: builds successfully. If it complains about `hasql-pool` `acquire` signature (newer versions changed it), drop back to the 3-argument form:

```haskell
Pool.acquire poolSize acquireTimeout idleTimeout connSettings
```

and confirm against the version resolved by `lts-22.43` (matching scripta-app-v4 exactly).

- [ ] **Step 5: Commit**

```bash
git add backend/src/AppEnv.hs backend/src/AppError.hs backend/src/Db/Pool.hs
git commit -m "add AppEnv, AppError, Db/Pool skeletons"
```

---

### Task 4: Minimal App.hs with /api/health + run.sh

**Files:**
- Create: `backend/src/App.hs`
- Create: `backend/src/Api/Types.hs`
- Modify: `backend/app/Main.hs`
- Create: `backend/run.sh`

- [ ] **Step 1: Create `backend/src/Api/Types.hs`**

```haskell
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeOperators #-}

module Api.Types (GreppitAPI) where

import Servant

type GreppitAPI =
  "api" :> "health" :> Get '[JSON] String
```

- [ ] **Step 2: Create `backend/src/App.hs`**

```haskell
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE OverloadedStrings #-}

module App
  ( startApp
  , appToHandler
  ) where

import Control.Monad.Reader (runReaderT)
import Data.Proxy (Proxy(..))
import Network.Wai (Application)
import Network.Wai.Handler.Warp (run)
import Network.Wai.Middleware.Cors
  (cors, simpleCorsResourcePolicy, corsRequestHeaders, corsMethods, corsOrigins, CorsResourcePolicy)
import Network.HTTP.Types.Method (methodGet, methodPost, methodPut, methodDelete, methodOptions)
import Servant
import Servant.Auth.Server (defaultCookieSettings, defaultJWTSettings)
import Crypto.JOSE.JWK (fromOctets)

import AppEnv (AppEnv(..), AppM)
import Api.Types (GreppitAPI)
import Config (Config(..))
import Db.Pool (createPool)

server :: ServerT GreppitAPI AppM
server = pure "ok"

appToHandler :: AppEnv -> AppM a -> Handler a
appToHandler env action = runReaderT action env

corsPolicy :: CorsResourcePolicy
corsPolicy = simpleCorsResourcePolicy
  { corsOrigins = Nothing
  , corsMethods = [methodGet, methodPost, methodPut, methodDelete, methodOptions]
  , corsRequestHeaders = ["Authorization", "Content-Type"]
  }

mkApp :: AppEnv -> Application
mkApp env =
  cors (const $ Just corsPolicy)
    $ serve (Proxy :: Proxy GreppitAPI)
    $ hoistServer (Proxy :: Proxy GreppitAPI) (appToHandler env) server

startApp :: Config -> IO ()
startApp config = do
  pool <- createPool (configDbUrl config)
  let jwtSettings = defaultJWTSettings (fromOctets (configJwtSecret config))
      env = AppEnv
        { envDbPool         = pool
        , envJwtSettings    = jwtSettings
        , envCookieSettings = defaultCookieSettings
        , envPort           = configPort config
        , envJwtExpiryDays  = configJwtExpiryDays config
        }
  putStrLn $ "greppit backend listening on port " <> show (configPort config)
  run (configPort config) (mkApp env)
```

- [ ] **Step 3: Update `backend/app/Main.hs`**

```haskell
module Main where

import App (startApp)
import Config (loadConfig)

main :: IO ()
main = loadConfig >>= startApp
```

- [ ] **Step 4: Create `backend/run.sh`**

```bash
#!/usr/bin/env bash
PORT=8085 DATABASE_URL="${DATABASE_URL:-postgres://localhost/greppit_dev}" stack exec greppit-backend
```

Then: `chmod +x backend/run.sh`.

- [ ] **Step 5: Create the dev database (one-time, manual)**

Run: `createdb greppit_dev`
Expected: command succeeds silently. If it says "already exists", that's fine. If psql isn't on the path, install Postgres first.

- [ ] **Step 6: Build and smoke test**

Run: `cd backend && stack build`
Then in one terminal: `cd backend && ./run.sh`
Then in another: `curl -s http://localhost:8085/api/health`
Expected: `"ok"` (with quotes — aeson string encoding).

Kill the server (Ctrl-C).

- [ ] **Step 7: Commit**

```bash
git add backend/src/App.hs backend/src/Api/Types.hs backend/app/Main.hs backend/run.sh
git commit -m "add minimal Servant app with /api/health"
```

---

### Task 5: Database migration — users + snippets

**Files:**
- Create: `backend/dbmate/migrations/001_initial_schema.sql`
- Create: `backend/migrate-up.sh` (small helper; optional)

- [ ] **Step 1: Create the migration file**

`backend/dbmate/migrations/001_initial_schema.sql`:

```sql
-- migrate:up

CREATE TABLE users (
    id            TEXT PRIMARY KEY,
    email         TEXT NOT NULL UNIQUE,
    pw_hash       TEXT NOT NULL,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE snippets (
    id          TEXT PRIMARY KEY,
    user_id     TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    title       TEXT NOT NULL,
    tags        TEXT NOT NULL DEFAULT '',
    markup      TEXT NOT NULL DEFAULT 'markdown'
                  CHECK (markup IN ('markdown', 'scripta')),
    body        TEXT NOT NULL DEFAULT '',
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX snippets_user_updated_idx ON snippets (user_id, updated_at DESC);

-- migrate:down

DROP INDEX IF EXISTS snippets_user_updated_idx;
DROP TABLE IF EXISTS snippets;
DROP TABLE IF EXISTS users;
```

- [ ] **Step 2: Run the migration**

Run (from `backend/`):

```bash
DATABASE_URL="postgres://localhost/greppit_dev?sslmode=disable" \
  dbmate --migrations-dir dbmate/migrations up
```

Expected: `Applied: 001_initial_schema.sql`. A `schema_migrations` tracking table is created.

- [ ] **Step 3: Verify schema**

Run: `psql greppit_dev -c '\d users' -c '\d snippets'`
Expected: both tables listed with the columns defined above.

- [ ] **Step 4: Commit**

```bash
git add backend/dbmate/migrations/001_initial_schema.sql
git commit -m "add initial schema migration: users + snippets"
```

---

### Task 6: Core domain types

**Files:**
- Create: `backend/src/Types/Common.hs`
- Create: `backend/src/Types/User.hs`
- Create: `backend/src/Types/Snippet.hs`

- [ ] **Step 1: `backend/src/Types/Common.hs`**

```haskell
module Types.Common
  ( UserId
  , SnippetId
  ) where

import Data.Text (Text)

type UserId    = Text
type SnippetId = Text
```

- [ ] **Step 2: `backend/src/Types/User.hs`**

```haskell
module Types.User (User(..)) where

import Data.Text (Text)
import Data.Time (UTCTime)
import Types.Common (UserId)

data User = User
  { usrId         :: UserId
  , usrEmail      :: Text
  , usrPwHash     :: Text
  , usrCreatedAt  :: UTCTime
  } deriving (Show, Eq)
```

- [ ] **Step 3: `backend/src/Types/Snippet.hs`**

```haskell
module Types.Snippet (Snippet(..), Markup(..), parseMarkup, markupText) where

import Data.Text (Text)
import Data.Time (UTCTime)
import Types.Common (UserId, SnippetId)

data Markup = Markdown | Scripta
  deriving (Show, Eq)

parseMarkup :: Text -> Maybe Markup
parseMarkup "markdown" = Just Markdown
parseMarkup "scripta"  = Just Scripta
parseMarkup _          = Nothing

markupText :: Markup -> Text
markupText Markdown = "markdown"
markupText Scripta  = "scripta"

data Snippet = Snippet
  { snpId        :: SnippetId
  , snpUserId    :: UserId
  , snpTitle     :: Text
  , snpTags      :: Text          -- space-separated, normalized
  , snpMarkup    :: Markup
  , snpBody      :: Text
  , snpCreatedAt :: UTCTime
  , snpUpdatedAt :: UTCTime
  } deriving (Show, Eq)
```

- [ ] **Step 4: Build**

Run: `cd backend && stack build`
Expected: success.

- [ ] **Step 5: Commit**

```bash
git add backend/src/Types/
git commit -m "add domain types: User, Snippet, Markup"
```

---

### Task 7: Service.Tags — tag normalization (TDD)

Rules: lowercase; collapse runs of whitespace into single spaces; trim leading/trailing whitespace.

**Files:**
- Create: `backend/test/Service/TagsSpec.hs`
- Create: `backend/src/Service/Tags.hs`
- Modify: `backend/test/Spec.hs`

- [ ] **Step 1: Write the failing test**

`backend/test/Service/TagsSpec.hs`:

```haskell
{-# LANGUAGE OverloadedStrings #-}

module Service.TagsSpec (spec) where

import Test.Hspec
import qualified Service.Tags as Tags

spec :: Spec
spec = describe "Service.Tags.normalize" $ do
  it "leaves a clean single word alone" $
    Tags.normalize "elm" `shouldBe` "elm"

  it "lowercases tags" $
    Tags.normalize "Elm Howto" `shouldBe` "elm howto"

  it "collapses multiple spaces" $
    Tags.normalize "elm   howto    postgres" `shouldBe` "elm howto postgres"

  it "strips leading and trailing whitespace" $
    Tags.normalize "   elm howto   " `shouldBe` "elm howto"

  it "normalizes tabs and newlines to single spaces" $
    Tags.normalize "elm\thowto\npostgres" `shouldBe` "elm howto postgres"

  it "returns empty string for all-whitespace input" $
    Tags.normalize "   \t \n " `shouldBe` ""

  it "returns empty string for empty input" $
    Tags.normalize "" `shouldBe` ""
```

- [ ] **Step 2: Update `backend/test/Spec.hs`**

```haskell
module Main where

import Test.Hspec
import qualified Service.TagsSpec

main :: IO ()
main = hspec $ do
  describe "Service.Tags" Service.TagsSpec.spec
```

- [ ] **Step 3: Run test — expect failure**

Run: `cd backend && stack test`
Expected: compile failure — `Service.Tags` not defined.

- [ ] **Step 4: Implement `backend/src/Service/Tags.hs`**

```haskell
{-# LANGUAGE OverloadedStrings #-}

module Service.Tags (normalize) where

import Data.Text (Text)
import qualified Data.Text as T

-- | Lowercase, split on whitespace runs, rejoin with single spaces.
-- Returns "" for all-whitespace / empty input.
normalize :: Text -> Text
normalize = T.unwords . T.words . T.toLower
```

- [ ] **Step 5: Run tests — expect pass**

Run: `cd backend && stack test`
Expected: all seven cases pass.

- [ ] **Step 6: Commit**

```bash
git add backend/src/Service/Tags.hs backend/test/Service/TagsSpec.hs backend/test/Spec.hs
git commit -m "add Service.Tags.normalize with tests"
```

---

### Task 8: Service.Search — parse search terms (TDD)

Rules: split the query string on whitespace; wrap each term as `%term%` for ILIKE. Empty / missing input → empty vector.

**Files:**
- Create: `backend/test/Service/SearchSpec.hs`
- Create: `backend/src/Service/Search.hs`
- Modify: `backend/test/Spec.hs`

- [ ] **Step 1: Write the failing test**

`backend/test/Service/SearchSpec.hs`:

```haskell
{-# LANGUAGE OverloadedStrings #-}

module Service.SearchSpec (spec) where

import Test.Hspec
import qualified Data.Vector as V
import qualified Service.Search as Search

spec :: Spec
spec = describe "Service.Search.termsToIlikePatterns" $ do
  it "returns empty vector for Nothing" $
    Search.termsToIlikePatterns Nothing `shouldBe` V.empty

  it "returns empty vector for empty string" $
    Search.termsToIlikePatterns (Just "") `shouldBe` V.empty

  it "returns empty vector for whitespace-only" $
    Search.termsToIlikePatterns (Just "   \t  ") `shouldBe` V.empty

  it "wraps a single term in percent signs" $
    Search.termsToIlikePatterns (Just "elm") `shouldBe` V.fromList ["%elm%"]

  it "splits multiple terms and wraps each" $
    Search.termsToIlikePatterns (Just "elm howto")
      `shouldBe` V.fromList ["%elm%", "%howto%"]

  it "collapses multiple whitespace" $
    Search.termsToIlikePatterns (Just "  elm   howto  ")
      `shouldBe` V.fromList ["%elm%", "%howto%"]
```

- [ ] **Step 2: Wire the spec into `backend/test/Spec.hs`**

Replace `backend/test/Spec.hs` with:

```haskell
module Main where

import Test.Hspec
import qualified Service.TagsSpec
import qualified Service.SearchSpec

main :: IO ()
main = hspec $ do
  describe "Service.Tags"   Service.TagsSpec.spec
  describe "Service.Search" Service.SearchSpec.spec
```

- [ ] **Step 3: Run tests — expect failure**

Run: `cd backend && stack test`
Expected: compile failure on `Service.Search`.

- [ ] **Step 4: Implement `backend/src/Service/Search.hs`**

```haskell
{-# LANGUAGE OverloadedStrings #-}

module Service.Search (termsToIlikePatterns) where

import Data.Text (Text)
import qualified Data.Text as T
import Data.Vector (Vector)
import qualified Data.Vector as V

-- | Split the (optional) query string on whitespace and wrap each term
-- as a case-insensitive ILIKE pattern. Returns empty on Nothing / blank.
termsToIlikePatterns :: Maybe Text -> Vector Text
termsToIlikePatterns Nothing   = V.empty
termsToIlikePatterns (Just q)  =
  V.fromList [ "%" <> t <> "%" | t <- T.words q, not (T.null t) ]
```

- [ ] **Step 5: Run tests — expect pass**

Run: `cd backend && stack test`
Expected: Tags + Search suites both green.

- [ ] **Step 6: Commit**

```bash
git add backend/src/Service/Search.hs backend/test/Service/SearchSpec.hs backend/test/Spec.hs
git commit -m "add Service.Search.termsToIlikePatterns with tests"
```

---

### Task 9: Service.Auth — bcrypt + JWT settings + AuthUser (TDD for hashing)

**Files:**
- Create: `backend/src/Service/Auth.hs`
- Create: `backend/test/Service/AuthSpec.hs`
- Modify: `backend/test/Spec.hs`

- [ ] **Step 1: Write the failing test**

`backend/test/Service/AuthSpec.hs`:

```haskell
{-# LANGUAGE OverloadedStrings #-}

module Service.AuthSpec (spec) where

import Test.Hspec
import Data.Maybe (isJust, fromJust)
import qualified Service.Auth as Auth

spec :: Spec
spec = describe "Service.Auth password hashing" $ do
  it "hashPassword returns Just on non-empty input" $ do
    h <- Auth.hashPassword "hunter2"
    h `shouldSatisfy` isJust

  it "checkPassword accepts the original password" $ do
    h <- fromJust <$> Auth.hashPassword "hunter2"
    Auth.checkPassword "hunter2" h `shouldBe` True

  it "checkPassword rejects a different password" $ do
    h <- fromJust <$> Auth.hashPassword "hunter2"
    Auth.checkPassword "wrong" h `shouldBe` False
```

- [ ] **Step 2: Wire it into `backend/test/Spec.hs`**

```haskell
module Main where

import Test.Hspec
import qualified Service.TagsSpec
import qualified Service.SearchSpec
import qualified Service.AuthSpec

main :: IO ()
main = hspec $ do
  describe "Service.Tags"   Service.TagsSpec.spec
  describe "Service.Search" Service.SearchSpec.spec
  describe "Service.Auth"   Service.AuthSpec.spec
```

- [ ] **Step 3: Run tests — expect failure**

Run: `cd backend && stack test`
Expected: compile failure on `Service.Auth`.

- [ ] **Step 4: Implement `backend/src/Service/Auth.hs`**

```haskell
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE DeriveGeneric #-}

module Service.Auth
  ( AuthUser(..)
  , hashPassword
  , checkPassword
  , makeJwtSettings
  ) where

import Crypto.BCrypt (hashPasswordUsingPolicy, slowerBcryptHashingPolicy, validatePassword)
import Data.Aeson (FromJSON, ToJSON)
import Data.ByteString (ByteString)
import Data.Text (Text)
import Data.Text.Encoding (encodeUtf8, decodeUtf8)
import GHC.Generics (Generic)
import Servant.Auth.Server (FromJWT, ToJWT, JWTSettings, defaultJWTSettings)
import Crypto.JOSE.JWK (fromOctets)

import Types.Common (UserId)

data AuthUser = AuthUser
  { auUserId :: UserId
  , auEmail  :: Text
  } deriving (Show, Eq, Generic)

instance FromJSON AuthUser
instance ToJSON   AuthUser
instance FromJWT  AuthUser
instance ToJWT    AuthUser

hashPassword :: Text -> IO (Maybe Text)
hashPassword password = do
  result <- hashPasswordUsingPolicy slowerBcryptHashingPolicy (encodeUtf8 password)
  pure (decodeUtf8 <$> result)

checkPassword :: Text -> Text -> Bool
checkPassword password hash =
  validatePassword (encodeUtf8 hash) (encodeUtf8 password)

makeJwtSettings :: ByteString -> JWTSettings
makeJwtSettings secret = defaultJWTSettings (fromOctets secret)
```

- [ ] **Step 5: Swap the App-level JWT settings helper**

In `backend/src/App.hs`, replace the local `defaultJWTSettings (fromOctets ...)` call with `makeJwtSettings (configJwtSecret config)` and `import Service.Auth (makeJwtSettings)`. Remove the now-unused `defaultJWTSettings` and `fromOctets` imports.

- [ ] **Step 6: Build and test**

Run: `cd backend && stack test`
Expected: all three suites green. Password tests are slow (bcrypt `slower` policy) — a few seconds is normal.

- [ ] **Step 7: Commit**

```bash
git add backend/src/Service/Auth.hs backend/src/App.hs \
        backend/test/Service/AuthSpec.hs backend/test/Spec.hs
git commit -m "add Service.Auth with bcrypt + JWT settings"
```

---

### Task 10: Api.RequestTypes — JSON request/response records

**Files:**
- Create: `backend/src/Api/RequestTypes.hs`

- [ ] **Step 1: Create the module**

```haskell
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}

module Api.RequestTypes where

import Data.Aeson
  ( FromJSON(..), ToJSON(..), genericParseJSON, genericToJSON
  , defaultOptions, Options(..)
  )
import Data.Char (toLower)
import Data.Text (Text)
import Data.Time (UTCTime)
import GHC.Generics (Generic)

import Types.Common (UserId, SnippetId)

-- Strip a fixed prefix from Haskell field names when (de)serializing JSON,
-- then lower-case the next character. E.g. `srEmail` -> `email`.
stripPrefixOptions :: Int -> Options
stripPrefixOptions prefixLen = defaultOptions
  { fieldLabelModifier = \s ->
      case drop prefixLen s of
        []     -> s
        (c:cs) -> toLower c : cs
  }

-- Auth
data SignupRequest = SignupRequest
  { srEmail    :: Text
  , srPassword :: Text
  } deriving (Show, Generic)
instance FromJSON SignupRequest where
  parseJSON = genericParseJSON (stripPrefixOptions 2)

data LoginRequest = LoginRequest
  { lrEmail    :: Text
  , lrPassword :: Text
  } deriving (Show, Generic)
instance FromJSON LoginRequest where
  parseJSON = genericParseJSON (stripPrefixOptions 2)

data UserResponse = UserResponse
  { urId    :: UserId
  , urEmail :: Text
  } deriving (Show, Generic)
instance ToJSON UserResponse where
  toJSON = genericToJSON (stripPrefixOptions 2)

data AuthResponse = AuthResponse
  { arToken :: Text
  , arUser  :: UserResponse
  } deriving (Show, Generic)
instance ToJSON AuthResponse where
  toJSON = genericToJSON (stripPrefixOptions 2)

-- Snippets
data SnippetResponse = SnippetResponse
  { spRespId        :: SnippetId
  , spRespUserId    :: UserId
  , spRespTitle     :: Text
  , spRespTags      :: Text
  , spRespMarkup    :: Text
  , spRespBody      :: Text
  , spRespCreatedAt :: UTCTime
  , spRespUpdatedAt :: UTCTime
  } deriving (Show, Generic)
instance ToJSON SnippetResponse where
  toJSON = genericToJSON (stripPrefixOptions 6)   -- strip "spResp"

data CreateSnippetRequest = CreateSnippetRequest
  { csrTitle  :: Text
  , csrTags   :: Text
  , csrMarkup :: Text
  , csrBody   :: Text
  } deriving (Show, Generic)
instance FromJSON CreateSnippetRequest where
  parseJSON = genericParseJSON (stripPrefixOptions 3)

data UpdateSnippetRequest = UpdateSnippetRequest
  { usrTitle  :: Text
  , usrTags   :: Text
  , usrMarkup :: Text
  , usrBody   :: Text
  } deriving (Show, Generic)
instance FromJSON UpdateSnippetRequest where
  parseJSON = genericParseJSON (stripPrefixOptions 3)
```

- [ ] **Step 2: Build**

Run: `cd backend && stack build`
Expected: success.

- [ ] **Step 3: Commit**

```bash
git add backend/src/Api/RequestTypes.hs
git commit -m "add Api.RequestTypes with auth and snippet JSON shapes"
```

---

### Task 11: Db.User — user statements

**Files:**
- Create: `backend/src/Db/User.hs`

- [ ] **Step 1: Create the module**

```haskell
{-# LANGUAGE OverloadedStrings #-}

module Db.User
  ( insertUser
  , getUserByEmail
  , getUserById
  ) where

import Data.Functor.Contravariant ((>$<))
import Data.Text (Text)
import Hasql.Statement (Statement(..))
import qualified Hasql.Encoders as E
import qualified Hasql.Decoders as D

import Types.Common (UserId)
import Types.User (User(..))

userRow :: D.Row User
userRow = User
  <$> D.column (D.nonNullable D.text)
  <*> D.column (D.nonNullable D.text)
  <*> D.column (D.nonNullable D.text)
  <*> D.column (D.nonNullable D.timestamptz)

insertUser :: Statement (UserId, Text, Text) ()
insertUser = Statement sql encoder D.noResult True
  where
    sql = "INSERT INTO users (id, email, pw_hash) VALUES ($1, $2, $3)"
    encoder =
      ((\(a,_,_) -> a) >$< E.param (E.nonNullable E.text)) <>
      ((\(_,b,_) -> b) >$< E.param (E.nonNullable E.text)) <>
      ((\(_,_,c) -> c) >$< E.param (E.nonNullable E.text))

getUserByEmail :: Statement Text (Maybe User)
getUserByEmail = Statement sql encoder decoder True
  where
    sql = "SELECT id, email, pw_hash, created_at FROM users WHERE email = $1"
    encoder = E.param (E.nonNullable E.text)
    decoder = D.rowMaybe userRow

getUserById :: Statement UserId (Maybe User)
getUserById = Statement sql encoder decoder True
  where
    sql = "SELECT id, email, pw_hash, created_at FROM users WHERE id = $1"
    encoder = E.param (E.nonNullable E.text)
    decoder = D.rowMaybe userRow
```

- [ ] **Step 2: Build**

Run: `cd backend && stack build`
Expected: success.

- [ ] **Step 3: Commit**

```bash
git add backend/src/Db/User.hs
git commit -m "add Db.User with insert/get statements"
```

---

### Task 12: Handler.Auth + Api.Auth — signup, login, me

**Files:**
- Create: `backend/src/Api/Auth.hs`
- Create: `backend/src/Handler/Auth.hs`
- Modify: `backend/src/Api/Types.hs`
- Modify: `backend/src/App.hs`
- Create: `backend/test-api.sh`

- [ ] **Step 1: Create `backend/src/Api/Auth.hs`**

```haskell
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeOperators #-}

module Api.Auth (AuthAPI) where

import Servant
import Servant.Auth (Auth, JWT)
import Api.RequestTypes (SignupRequest, LoginRequest, AuthResponse, UserResponse)
import Service.Auth (AuthUser)

type AuthAPI =
       "signup" :> ReqBody '[JSON] SignupRequest :> Post '[JSON] AuthResponse
  :<|> "login"  :> ReqBody '[JSON] LoginRequest  :> Post '[JSON] AuthResponse
  :<|> "me"     :> Auth '[JWT] AuthUser :> Get '[JSON] UserResponse
```

- [ ] **Step 2: Create `backend/src/Handler/Auth.hs`**

```haskell
{-# LANGUAGE OverloadedStrings #-}

module Handler.Auth
  ( signupHandler
  , loginHandler
  , meHandler
  ) where

import Control.Monad.IO.Class (liftIO)
import Control.Monad.Reader (asks)
import qualified Data.ByteString.Lazy as LBS
import Data.Text.Encoding (decodeUtf8)
import qualified Data.UUID as UUID
import qualified Data.UUID.V4 as UUID
import Servant (throwError)
import Servant.Auth.Server (AuthResult(..), makeJWT)
import qualified Hasql.Pool as Pool
import qualified Hasql.Session as Session

import AppEnv (AppEnv(..), AppM)
import AppError (AppError(..), appErrorToServantErr)
import Api.RequestTypes
  ( SignupRequest(..), LoginRequest(..), AuthResponse(..), UserResponse(..) )
import Service.Auth (AuthUser(..), hashPassword, checkPassword)
import Types.User (User(..))
import qualified Db.User as Db

signupHandler :: SignupRequest -> AppM AuthResponse
signupHandler req = do
  pool        <- asks envDbPool
  jwtSettings <- asks envJwtSettings
  userId      <- liftIO $ UUID.toText <$> UUID.nextRandom
  mHash       <- liftIO $ hashPassword (srPassword req)
  case mHash of
    Nothing ->
      throwError $ appErrorToServantErr (InternalError "password hashing failed")
    Just hash -> do
      result <- liftIO $ Pool.use pool $ Session.statement
                  (userId, srEmail req, hash) Db.insertUser
      case result of
        Left _err ->
          throwError $ appErrorToServantErr (Conflict "email already registered")
        Right () -> do
          let au = AuthUser userId (srEmail req)
          eTok <- liftIO $ makeJWT au jwtSettings Nothing
          case eTok of
            Left _ ->
              throwError $ appErrorToServantErr (InternalError "token generation failed")
            Right tokBS -> pure AuthResponse
              { arToken = decodeUtf8 (LBS.toStrict tokBS)
              , arUser  = UserResponse userId (srEmail req)
              }

loginHandler :: LoginRequest -> AppM AuthResponse
loginHandler req = do
  pool        <- asks envDbPool
  jwtSettings <- asks envJwtSettings
  result <- liftIO $ Pool.use pool $ Session.statement
              (lrEmail req) Db.getUserByEmail
  case result of
    Left _ ->
      throwError $ appErrorToServantErr (InternalError "database error")
    Right Nothing ->
      throwError $ appErrorToServantErr Unauthorized
    Right (Just user)
      | checkPassword (lrPassword req) (usrPwHash user) -> do
          let au = AuthUser (usrId user) (usrEmail user)
          eTok <- liftIO $ makeJWT au jwtSettings Nothing
          case eTok of
            Left _ -> throwError $ appErrorToServantErr (InternalError "token generation failed")
            Right tokBS -> pure AuthResponse
              { arToken = decodeUtf8 (LBS.toStrict tokBS)
              , arUser  = UserResponse (usrId user) (usrEmail user)
              }
      | otherwise -> throwError $ appErrorToServantErr Unauthorized

meHandler :: AuthResult AuthUser -> AppM UserResponse
meHandler (Authenticated au) =
  pure $ UserResponse (auUserId au) (auEmail au)
meHandler _ =
  throwError $ appErrorToServantErr Unauthorized
```

- [ ] **Step 3: Update `backend/src/Api/Types.hs`**

```haskell
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeOperators #-}

module Api.Types (GreppitAPI) where

import Servant
import Api.Auth (AuthAPI)

type GreppitAPI =
       "api" :> "auth" :> AuthAPI
  :<|> "api" :> "health" :> Get '[JSON] String
```

- [ ] **Step 4: Update `backend/src/App.hs` `server` definition**

Replace the single-line `server` with:

```haskell
server :: ServerT GreppitAPI AppM
server = authHandlers :<|> healthHandler
  where
    authHandlers =
           signupHandler
      :<|> loginHandler
      :<|> meHandler

    healthHandler :: AppM String
    healthHandler = pure "ok"
```

And add at the top of App.hs:

```haskell
import Handler.Auth (signupHandler, loginHandler, meHandler)
import Servant.Auth.Server (CookieSettings, JWTSettings)
```

Update `mkApp` to supply the auth context:

```haskell
mkApp :: AppEnv -> Application
mkApp env =
  cors (const $ Just corsPolicy)
    $ serveWithContext api ctx
    $ hoistServerWithContext api ctxProxy (appToHandler env) server
  where
    api = Proxy :: Proxy GreppitAPI
    ctxProxy = Proxy :: Proxy '[CookieSettings, JWTSettings]
    ctx = envCookieSettings env :. envJwtSettings env :. EmptyContext
```

(Remove the now-unused `serve` / `hoistServer` imports if the compiler complains.)

- [ ] **Step 5: Create `backend/test-api.sh`**

```bash
#!/usr/bin/env bash
# Integration smoke test for the greppit backend.
# Requires: running server on port 8085, jq, curl.
set -u

BASE="http://localhost:8085"
EMAIL="test-$(date +%s)@example.com"
PW="hunter2"

say() { printf "\n=== %s ===\n" "$1"; }

say "Health"
curl -sS "$BASE/api/health" | jq .

say "Signup"
SIGNUP=$(curl -sS -X POST "$BASE/api/auth/signup" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$EMAIL\",\"password\":\"$PW\"}")
echo "$SIGNUP" | jq .
TOKEN=$(echo "$SIGNUP" | jq -r .token)

say "Login"
LOGIN=$(curl -sS -X POST "$BASE/api/auth/login" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$EMAIL\",\"password\":\"$PW\"}")
echo "$LOGIN" | jq .

say "Me"
curl -sS "$BASE/api/auth/me" \
  -H "Authorization: Bearer $TOKEN" | jq .

say "Login wrong password (expect 401)"
curl -sS -o /dev/null -w "status=%{http_code}\n" \
  -X POST "$BASE/api/auth/login" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$EMAIL\",\"password\":\"wrong\"}"
```

Then: `chmod +x backend/test-api.sh`.

- [ ] **Step 6: Build and run**

Run: `cd backend && stack build`
Expected: success.

Start the server in one terminal: `cd backend && ./run.sh`.
In another terminal: `cd backend && bash test-api.sh`.

Expected:
- Health: `"ok"`
- Signup: `{ "token": "...", "user": { "id": "...", "email": "..." } }`
- Login: same shape.
- Me: `{ "id": "...", "email": "..." }` matching the signed-in user.
- Wrong password: `status=401`.

- [ ] **Step 7: Commit**

```bash
git add backend/src/Api/Auth.hs backend/src/Handler/Auth.hs \
        backend/src/Api/Types.hs backend/src/App.hs \
        backend/test-api.sh
git commit -m "add auth API: signup, login, me with JWT"
```

---

### Task 13: Db.Snippet — statements for CRUD and search

**Files:**
- Create: `backend/src/Db/Snippet.hs`

- [ ] **Step 1: Create the module**

```haskell
{-# LANGUAGE OverloadedStrings #-}

module Db.Snippet
  ( insertSnippet
  , getSnippetById
  , updateSnippet
  , deleteSnippet
  , searchSnippets
  ) where

import Data.Functor.Contravariant ((>$<))
import Data.Text (Text)
import Data.Vector (Vector)
import Hasql.Statement (Statement(..))
import qualified Hasql.Encoders as E
import qualified Hasql.Decoders as D

import Types.Common (SnippetId, UserId)
import Types.Snippet (Snippet(..), Markup, parseMarkup)

-- | Decode one snippet row.
-- Columns: id, user_id, title, tags, markup, body, created_at, updated_at
snippetRow :: D.Row Snippet
snippetRow = Snippet
  <$> D.column (D.nonNullable D.text)
  <*> D.column (D.nonNullable D.text)
  <*> D.column (D.nonNullable D.text)
  <*> D.column (D.nonNullable D.text)
  <*> D.column (D.nonNullable (D.text `D.refine` refineMarkup))
  <*> D.column (D.nonNullable D.text)
  <*> D.column (D.nonNullable D.timestamptz)
  <*> D.column (D.nonNullable D.timestamptz)
  where
    refineMarkup :: Text -> Either Text Markup
    refineMarkup t = case parseMarkup t of
      Just m  -> Right m
      Nothing -> Left ("unknown markup: " <> t)

-- | INSERT a snippet. Takes (id, userId, title, tags, markup, body).
-- created_at / updated_at default to now() on the DB side.
insertSnippet :: Statement (SnippetId, UserId, Text, Text, Text, Text) ()
insertSnippet = Statement sql encoder D.noResult True
  where
    sql = "INSERT INTO snippets (id, user_id, title, tags, markup, body) \
          \VALUES ($1, $2, $3, $4, $5, $6)"
    encoder =
      ((\(a,_,_,_,_,_) -> a) >$< E.param (E.nonNullable E.text)) <>
      ((\(_,b,_,_,_,_) -> b) >$< E.param (E.nonNullable E.text)) <>
      ((\(_,_,c,_,_,_) -> c) >$< E.param (E.nonNullable E.text)) <>
      ((\(_,_,_,d,_,_) -> d) >$< E.param (E.nonNullable E.text)) <>
      ((\(_,_,_,_,e,_) -> e) >$< E.param (E.nonNullable E.text)) <>
      ((\(_,_,_,_,_,f) -> f) >$< E.param (E.nonNullable E.text))

-- | Fetch a snippet scoped to a user. Returns Nothing if not owned / missing.
getSnippetById :: Statement (SnippetId, UserId) (Maybe Snippet)
getSnippetById = Statement sql encoder (D.rowMaybe snippetRow) True
  where
    sql = "SELECT id, user_id, title, tags, markup, body, created_at, updated_at \
          \FROM snippets WHERE id = $1 AND user_id = $2"
    encoder =
      (fst >$< E.param (E.nonNullable E.text)) <>
      (snd >$< E.param (E.nonNullable E.text))

-- | UPDATE a snippet's mutable fields. Also bumps updated_at = now().
-- Takes (id, userId, title, tags, markup, body). Returns number of rows affected.
updateSnippet :: Statement (SnippetId, UserId, Text, Text, Text, Text) Int
updateSnippet = Statement sql encoder (fromIntegral <$> D.rowsAffected) True
  where
    sql = "UPDATE snippets \
          \SET title = $3, tags = $4, markup = $5, body = $6, updated_at = now() \
          \WHERE id = $1 AND user_id = $2"
    encoder =
      ((\(a,_,_,_,_,_) -> a) >$< E.param (E.nonNullable E.text)) <>
      ((\(_,b,_,_,_,_) -> b) >$< E.param (E.nonNullable E.text)) <>
      ((\(_,_,c,_,_,_) -> c) >$< E.param (E.nonNullable E.text)) <>
      ((\(_,_,_,d,_,_) -> d) >$< E.param (E.nonNullable E.text)) <>
      ((\(_,_,_,_,e,_) -> e) >$< E.param (E.nonNullable E.text)) <>
      ((\(_,_,_,_,_,f) -> f) >$< E.param (E.nonNullable E.text))

-- | DELETE a snippet scoped to a user. Returns rows affected (0 or 1).
deleteSnippet :: Statement (SnippetId, UserId) Int
deleteSnippet = Statement sql encoder (fromIntegral <$> D.rowsAffected) True
  where
    sql = "DELETE FROM snippets WHERE id = $1 AND user_id = $2"
    encoder =
      (fst >$< E.param (E.nonNullable E.text)) <>
      (snd >$< E.param (E.nonNullable E.text))

-- | Search / list. `patterns` is a Vector of ILIKE patterns (each "%term%");
-- empty vector means "no predicates". Uses Postgres ILIKE ALL over an array.
-- Always returns the 5 most recently updated matches.
searchSnippets :: Statement (UserId, Vector Text) (Vector Snippet)
searchSnippets = Statement sql encoder (D.rowVector snippetRow) True
  where
    sql = "SELECT id, user_id, title, tags, markup, body, created_at, updated_at \
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

**Note on `ILIKE ALL`:** Postgres `ILIKE ALL (ARRAY[...]::text[])` is trivially true when the array is empty, which is exactly the "no search" behavior we want.

- [ ] **Step 2: Build**

Run: `cd backend && stack build`
Expected: success. If Hasql's array encoder API differs in `lts-22.43`, adjust `E.array` per the Hasql version's docs — the function's purpose is "encode a Haskell `Vector Text` as a Postgres `text[]` parameter." The typical Hasql 1.6.x spelling is `E.array (E.dimension foldl (E.element (E.nonNullable E.text)))`.

- [ ] **Step 3: Commit**

```bash
git add backend/src/Db/Snippet.hs
git commit -m "add Db.Snippet statements: insert, get, update, delete, search"
```

---

### Task 14: Api.Snippets type

**Files:**
- Create: `backend/src/Api/Snippets.hs`

- [ ] **Step 1: Create the module**

```haskell
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeOperators #-}

module Api.Snippets (SnippetsAPI) where

import Data.Text (Text)
import Servant

import Api.RequestTypes
  ( SnippetResponse, CreateSnippetRequest, UpdateSnippetRequest )

type SnippetsAPI =
       -- GET /api/snippets?q=<terms>
       QueryParam "q" Text :> Get '[JSON] [SnippetResponse]

       -- POST /api/snippets
  :<|> ReqBody '[JSON] CreateSnippetRequest :> Post '[JSON] SnippetResponse

       -- GET /api/snippets/:id
  :<|> Capture "id" Text :> Get '[JSON] SnippetResponse

       -- PUT /api/snippets/:id
  :<|> Capture "id" Text :> ReqBody '[JSON] UpdateSnippetRequest :> Put '[JSON] SnippetResponse

       -- DELETE /api/snippets/:id
  :<|> Capture "id" Text :> DeleteNoContent
```

- [ ] **Step 2: Build**

Run: `cd backend && stack build`
Expected: success (the type compiles even though handlers don't exist yet).

- [ ] **Step 3: Commit**

```bash
git add backend/src/Api/Snippets.hs
git commit -m "add Api.Snippets type (GET/POST/GET:id/PUT/DELETE)"
```

---

### Task 15: Handler.Snippets — CRUD + search

**Files:**
- Create: `backend/src/Handler/Snippets.hs`

- [ ] **Step 1: Create the module**

```haskell
{-# LANGUAGE OverloadedStrings #-}

module Handler.Snippets
  ( listSnippetsHandler
  , createSnippetHandler
  , getSnippetHandler
  , updateSnippetHandler
  , deleteSnippetHandler
  ) where

import Control.Monad.IO.Class (liftIO)
import Control.Monad.Reader (asks)
import Data.Text (Text)
import qualified Data.UUID as UUID
import qualified Data.UUID.V4 as UUID
import qualified Data.Vector as V
import Servant (NoContent(..), throwError)
import Servant.Auth.Server (AuthResult(..))
import qualified Hasql.Pool as Pool
import qualified Hasql.Session as Session

import AppEnv (AppEnv(..), AppM)
import AppError (AppError(..), appErrorToServantErr)
import Api.RequestTypes
  ( SnippetResponse(..)
  , CreateSnippetRequest(..)
  , UpdateSnippetRequest(..)
  )
import Service.Auth (AuthUser(..))
import qualified Service.Search as Search
import qualified Service.Tags as Tags
import qualified Db.Snippet as Db
import Types.Common (SnippetId, UserId)
import Types.Snippet (Snippet(..), Markup, parseMarkup, markupText)

-- | Extract the current user id from a Servant.Auth AuthResult, or 401.
requireUser :: AuthResult AuthUser -> AppM UserId
requireUser (Authenticated au) = pure (auUserId au)
requireUser _ = throwError $ appErrorToServantErr Unauthorized

-- | Convert a Snippet domain value into its JSON response.
toResp :: Snippet -> SnippetResponse
toResp s = SnippetResponse
  { spRespId        = snpId s
  , spRespUserId    = snpUserId s
  , spRespTitle     = snpTitle s
  , spRespTags      = snpTags s
  , spRespMarkup    = markupText (snpMarkup s)
  , spRespBody      = snpBody s
  , spRespCreatedAt = snpCreatedAt s
  , spRespUpdatedAt = snpUpdatedAt s
  }

-- | Validate and normalize a markup string from the client.
parseMarkupOrFail :: Text -> AppM Text
parseMarkupOrFail t = case parseMarkup t of
  Just _  -> pure t
  Nothing -> throwError $ appErrorToServantErr (InvalidInput "markup must be \"markdown\" or \"scripta\"")

listSnippetsHandler
  :: AuthResult AuthUser -> Maybe Text -> AppM [SnippetResponse]
listSnippetsHandler auth mq = do
  userId <- requireUser auth
  pool   <- asks envDbPool
  let patterns = Search.termsToIlikePatterns mq
  result <- liftIO $ Pool.use pool $
              Session.statement (userId, patterns) Db.searchSnippets
  case result of
    Left _    -> throwError $ appErrorToServantErr (InternalError "database error")
    Right vec -> pure $ map toResp (V.toList vec)

createSnippetHandler
  :: AuthResult AuthUser -> CreateSnippetRequest -> AppM SnippetResponse
createSnippetHandler auth req = do
  userId <- requireUser auth
  pool   <- asks envDbPool
  _      <- parseMarkupOrFail (csrMarkup req)
  let normTags = Tags.normalize (csrTags req)
  sid <- liftIO $ UUID.toText <$> UUID.nextRandom
  insRes <- liftIO $ Pool.use pool $ Session.statement
              (sid, userId, csrTitle req, normTags, csrMarkup req, csrBody req)
              Db.insertSnippet
  case insRes of
    Left _   -> throwError $ appErrorToServantErr (InternalError "database error")
    Right () -> do
      -- Re-fetch so we return the DB-populated timestamps.
      g <- liftIO $ Pool.use pool $
             Session.statement (sid, userId) Db.getSnippetById
      case g of
        Right (Just s) -> pure (toResp s)
        _ -> throwError $ appErrorToServantErr (InternalError "snippet vanished after insert")

getSnippetHandler
  :: AuthResult AuthUser -> SnippetId -> AppM SnippetResponse
getSnippetHandler auth sid = do
  userId <- requireUser auth
  pool   <- asks envDbPool
  r      <- liftIO $ Pool.use pool $
              Session.statement (sid, userId) Db.getSnippetById
  case r of
    Left _          -> throwError $ appErrorToServantErr (InternalError "database error")
    Right Nothing   -> throwError $ appErrorToServantErr NotFound
    Right (Just s)  -> pure (toResp s)

updateSnippetHandler
  :: AuthResult AuthUser -> SnippetId -> UpdateSnippetRequest -> AppM SnippetResponse
updateSnippetHandler auth sid req = do
  userId <- requireUser auth
  pool   <- asks envDbPool
  _      <- parseMarkupOrFail (usrMarkup req)
  let normTags = Tags.normalize (usrTags req)
  updRes <- liftIO $ Pool.use pool $ Session.statement
              (sid, userId, usrTitle req, normTags, usrMarkup req, usrBody req)
              Db.updateSnippet
  case updRes of
    Left _        -> throwError $ appErrorToServantErr (InternalError "database error")
    Right 0       -> throwError $ appErrorToServantErr NotFound
    Right _       -> do
      g <- liftIO $ Pool.use pool $
             Session.statement (sid, userId) Db.getSnippetById
      case g of
        Right (Just s) -> pure (toResp s)
        _              -> throwError $ appErrorToServantErr (InternalError "snippet vanished after update")

deleteSnippetHandler
  :: AuthResult AuthUser -> SnippetId -> AppM NoContent
deleteSnippetHandler auth sid = do
  userId <- requireUser auth
  pool   <- asks envDbPool
  r      <- liftIO $ Pool.use pool $
              Session.statement (sid, userId) Db.deleteSnippet
  case r of
    Left _   -> throwError $ appErrorToServantErr (InternalError "database error")
    Right 0  -> throwError $ appErrorToServantErr NotFound
    Right _  -> pure NoContent
```

- [ ] **Step 2: Build**

Run: `cd backend && stack build`
Expected: success.

- [ ] **Step 3: Commit**

```bash
git add backend/src/Handler/Snippets.hs
git commit -m "add Handler.Snippets with CRUD and search"
```

---

### Task 16: Wire snippets into the API and extend integration tests

**Files:**
- Modify: `backend/src/Api/Types.hs`
- Modify: `backend/src/App.hs`
- Modify: `backend/test-api.sh`

- [ ] **Step 1: Extend `backend/src/Api/Types.hs`**

```haskell
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeOperators #-}

module Api.Types (GreppitAPI) where

import Servant
import Servant.Auth (Auth, JWT)
import Service.Auth (AuthUser)
import Api.Auth (AuthAPI)
import Api.Snippets (SnippetsAPI)

type GreppitAPI =
       "api" :> "auth"     :> AuthAPI
  :<|> "api" :> "snippets" :> Auth '[JWT] AuthUser :> SnippetsAPI
  :<|> "api" :> "health"   :> Get '[JSON] String
```

- [ ] **Step 2: Extend `backend/src/App.hs` `server` definition**

```haskell
server :: ServerT GreppitAPI AppM
server = authHandlers :<|> snippetsHandlers :<|> healthHandler
  where
    authHandlers =
           signupHandler
      :<|> loginHandler
      :<|> meHandler

    snippetsHandlers authResult =
           listSnippetsHandler   authResult
      :<|> createSnippetHandler  authResult
      :<|> getSnippetHandler     authResult
      :<|> updateSnippetHandler  authResult
      :<|> deleteSnippetHandler  authResult

    healthHandler :: AppM String
    healthHandler = pure "ok"
```

Add imports:

```haskell
import Handler.Snippets
  ( listSnippetsHandler, createSnippetHandler, getSnippetHandler
  , updateSnippetHandler, deleteSnippetHandler
  )
```

- [ ] **Step 3: Extend `backend/test-api.sh`**

Append (after the "Login wrong password" step):

```bash
say "Create snippet A"
A=$(curl -sS -X POST "$BASE/api/snippets" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"title":"Elm howto","tags":"elm howto","markup":"markdown","body":"# Hello\n$e^{i\\pi}+1=0$"}')
echo "$A" | jq .
A_ID=$(echo "$A" | jq -r .id)

say "Create snippet B"
curl -sS -X POST "$BASE/api/snippets" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"title":"Postgres ilike tip","tags":"postgres","markup":"markdown","body":"Use ILIKE for case-insensitive."}' \
  | jq .

say "Create snippet C (scripta)"
curl -sS -X POST "$BASE/api/snippets" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"title":"Scripta demo","tags":"scripta","markup":"scripta","body":"[b bold]"}' \
  | jq .

say "List (no search) - expect 3 results, most recent first"
curl -sS "$BASE/api/snippets" \
  -H "Authorization: Bearer $TOKEN" | jq 'length'

say "Search 'elm' - expect 1"
curl -sS "$BASE/api/snippets?q=elm" \
  -H "Authorization: Bearer $TOKEN" | jq 'length'

say "Search 'elm howto' - expect 1 (conjunctive)"
curl -sS --get --data-urlencode "q=elm howto" \
  "$BASE/api/snippets" -H "Authorization: Bearer $TOKEN" | jq 'length'

say "Search 'elm postgres' - expect 0"
curl -sS --get --data-urlencode "q=elm postgres" \
  "$BASE/api/snippets" -H "Authorization: Bearer $TOKEN" | jq 'length'

say "Update A"
curl -sS -X PUT "$BASE/api/snippets/$A_ID" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"title":"Elm howto v2","tags":"elm howto","markup":"markdown","body":"updated"}' \
  | jq .

say "Get A (expect v2)"
curl -sS "$BASE/api/snippets/$A_ID" \
  -H "Authorization: Bearer $TOKEN" | jq .title

say "Delete A"
curl -sS -o /dev/null -w "status=%{http_code}\n" \
  -X DELETE "$BASE/api/snippets/$A_ID" \
  -H "Authorization: Bearer $TOKEN"

say "Get A (expect 404)"
curl -sS -o /dev/null -w "status=%{http_code}\n" \
  "$BASE/api/snippets/$A_ID" -H "Authorization: Bearer $TOKEN"

say "Unauthed list (expect 401)"
curl -sS -o /dev/null -w "status=%{http_code}\n" "$BASE/api/snippets"
```

- [ ] **Step 4: Build and run**

```bash
cd backend && stack build
./run.sh &
SERVER_PID=$!
sleep 2
bash test-api.sh
kill $SERVER_PID
```

Expected:
- Snippet A,B,C creation: each returns full JSON with a UUID `id`.
- List with no search: `3`.
- Search `elm`: `1`.
- Search `elm howto`: `1`.
- Search `elm postgres`: `0`.
- Update: `title` comes back as `"Elm howto v2"`.
- Delete: `status=204`.
- Get after delete: `status=404`.
- Unauthed list: `status=401`.

- [ ] **Step 5: Commit**

```bash
git add backend/src/Api/Types.hs backend/src/App.hs backend/test-api.sh
git commit -m "wire snippets API end-to-end; extend integration test"
```

---

### Task 17: Cross-user isolation check

Verify that one user cannot see, update, or delete another user's snippet. This is the "no existence leak" guarantee from the spec.

**Files:**
- Modify: `backend/test-api.sh` (add a second user + cross-access checks)

- [ ] **Step 1: Append to `backend/test-api.sh`**

```bash
say "Cross-user isolation"

EMAIL2="test2-$(date +%s)@example.com"
SIGNUP2=$(curl -sS -X POST "$BASE/api/auth/signup" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$EMAIL2\",\"password\":\"$PW\"}")
TOKEN2=$(echo "$SIGNUP2" | jq -r .token)

say "User1 creates X"
X=$(curl -sS -X POST "$BASE/api/snippets" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"title":"private","tags":"","markup":"markdown","body":"secret"}')
X_ID=$(echo "$X" | jq -r .id)

say "User2 tries to GET X (expect 404, not 403 - no existence leak)"
curl -sS -o /dev/null -w "status=%{http_code}\n" \
  "$BASE/api/snippets/$X_ID" -H "Authorization: Bearer $TOKEN2"

say "User2 tries to PUT X (expect 404)"
curl -sS -o /dev/null -w "status=%{http_code}\n" \
  -X PUT "$BASE/api/snippets/$X_ID" \
  -H "Authorization: Bearer $TOKEN2" -H "Content-Type: application/json" \
  -d '{"title":"hijack","tags":"","markup":"markdown","body":""}'

say "User2 tries to DELETE X (expect 404)"
curl -sS -o /dev/null -w "status=%{http_code}\n" \
  -X DELETE "$BASE/api/snippets/$X_ID" -H "Authorization: Bearer $TOKEN2"

say "User2's list does NOT include X (expect length 0)"
curl -sS "$BASE/api/snippets" -H "Authorization: Bearer $TOKEN2" | jq 'length'
```

- [ ] **Step 2: Run**

With the server running, run: `cd backend && bash test-api.sh`
Expected (additional section output):
- GET: `status=404`
- PUT: `status=404`
- DELETE: `status=404`
- List length: `0`

- [ ] **Step 3: Commit**

```bash
git add backend/test-api.sh
git commit -m "extend integration test: cross-user isolation"
```

---

### Task 18: README + dev setup docs

**Files:**
- Create: `backend/README.md`

- [ ] **Step 1: Write `backend/README.md`**

```markdown
# greppit-backend

Haskell/Postgres backend for greppit.

## Prerequisites
- `stack`
- `dbmate`
- Postgres (local)
- `jq`, `curl` (for integration test)

## Dev setup

```
createdb greppit_dev
cd backend
DATABASE_URL="postgres://localhost/greppit_dev?sslmode=disable" \
  dbmate --migrations-dir dbmate/migrations up
stack build
```

## Run

```
./run.sh
```

Listens on `http://localhost:8085`.

## Test

```
stack test                 # unit tests
./run.sh &                 # in one shell
bash test-api.sh           # in another
```

## Endpoints

| Method | Path                          | Auth | Notes |
|--------|-------------------------------|------|-------|
| GET    | /api/health                   | no   |       |
| POST   | /api/auth/signup              | no   |       |
| POST   | /api/auth/login               | no   |       |
| GET    | /api/auth/me                  | yes  |       |
| GET    | /api/snippets?q=<terms>       | yes  | conjunctive ILIKE, top 5 by updated_at |
| POST   | /api/snippets                 | yes  |       |
| GET    | /api/snippets/:id             | yes  |       |
| PUT    | /api/snippets/:id             | yes  |       |
| DELETE | /api/snippets/:id             | yes  | returns 204 |
```

- [ ] **Step 2: Commit**

```bash
git add backend/README.md
git commit -m "add backend README with setup + endpoint table"
```

---

### Task 19: Final verification

- [ ] **Step 1: Build from scratch**

```bash
cd backend
stack clean
stack build
```

Expected: clean compile, no warnings beyond unused-imports (if any remain, fix them).

- [ ] **Step 2: Run the full unit test suite**

Run: `cd backend && stack test`
Expected: all suites green.

- [ ] **Step 3: Run the full integration test**

In one terminal: `cd backend && ./run.sh`
In another: `cd backend && bash test-api.sh`
Expected: every `say` section produces output matching its description. No error lines.

- [ ] **Step 4: Confirm plan 1 is done**

Stop the server. Report success. This plan produces a fully working backend for the greppit v1 API. Plan 2 (frontend) consumes this API.

---

## Self-Review

**Spec coverage:**
- Users table (id, email, pw_hash, created_at): Task 5, 11. ✓
- Snippets table with constraints and index: Task 5. ✓
- Email/password signup + login, JWT 7-day: Tasks 9, 12. ✓
- `/api/auth/signup`, `/api/auth/login`, `/api/auth/me`: Task 12. ✓
- Snippets CRUD: Tasks 13, 15, 16. ✓
- Search ILIKE ALL conjunctive, top 5 by updated_at, case-insensitive, empty q = most recent 5: Tasks 8, 13, 16. ✓
- Tag normalization (space-separated, lowercased): Tasks 7, 15. ✓
- Markup validation (markdown|scripta), default markdown: DB CHECK (Task 5) + handler parse (Task 15). ✓
- Cross-user 404 (no existence leak): Task 17. ✓
- CORS for the frontend: Task 4 (`corsPolicy`). ✓
- Full scripta-app-v4-style layout minus WebSocket: directory structure in Task 1 + subsequent tasks fill it. ✓
- bcrypt cost matches scripta-app-v4: `slowerBcryptHashingPolicy` in Task 9. ✓
- Dev DB + dbmate: Task 5. ✓

**No placeholders found.** No "TBD", no "similar to Task N", every code step has complete code, every command shows expected output.

**Type consistency:** `AuthUser { auUserId, auEmail }`, `Snippet { snpId, snpUserId, snpTitle, snpTags, snpMarkup, snpBody, snpCreatedAt, snpUpdatedAt }`, and `SnippetResponse` fields prefixed `spResp` used consistently across handlers and codecs. `UserId`, `SnippetId` type aliases used everywhere for IDs.

**Out-of-scope check:** WebSocket, sharing, Scripta rendering, pagination, autosave are all absent from the plan as expected.

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-04-17-greppit-backend.md`. Two execution options:

1. **Subagent-Driven (recommended)** — I dispatch a fresh subagent per task, review between tasks, fast iteration.
2. **Inline Execution** — Execute tasks in this session using `executing-plans`, batch execution with checkpoints.

Which approach?
