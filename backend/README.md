# greppit-backend

Haskell/Postgres backend for greppit.

## Prerequisites

- `stack` (GHC 9.6.x via lts-22.43)
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

Note: `run.sh` defaults to `DATABASE_URL=host=localhost dbname=greppit_dev` but respects an outer `DATABASE_URL` if one is exported in your shell. If your shell exports `DATABASE_URL` for another project, either `unset DATABASE_URL` or prefix:

```
DATABASE_URL="postgres://localhost/greppit_dev" ./run.sh
```

## Test

```
stack test                 # unit tests (Tags, Search, Auth)
./run.sh &                 # in one shell
bash test-api.sh           # in another
```

`test-api.sh` runs the full integration suite: signup, login, /me, CRUD, search, cross-user isolation.

## Endpoints

| Method | Path                      | Auth | Notes |
|--------|---------------------------|------|-------|
| GET    | /api/health               | no   |       |
| POST   | /api/auth/signup          | no   | { email, password } → { token, user } |
| POST   | /api/auth/login           | no   | { email, password } → { token, user } |
| GET    | /api/auth/me              | yes  |       |
| GET    | /api/snippets?q=<terms>   | yes  | conjunctive ILIKE, top 5 by updated_at |
| POST   | /api/snippets             | yes  | { title, tags, markup, body } |
| GET    | /api/snippets/:id         | yes  |       |
| PUT    | /api/snippets/:id         | yes  | same shape as POST |
| DELETE | /api/snippets/:id         | yes  | returns 204 |

## Environment variables

| Var | Default | Notes |
|-----|---------|-------|
| `DATABASE_URL` | `postgres://localhost/greppit_dev` | libpq connection string (URL or keyword format) |
| `JWT_SECRET` | `dev-secret-change-in-production-min-32-chars!!` | HS256-signed; must be ≥ 32 bytes in production |
| `JWT_EXPIRY_DAYS` | `7` | token lifetime |
| `PORT` | `8085` |  |

## Project layout

```
backend/
  app/Main.hs              -- startup
  src/
    App.hs                 -- Servant server, CORS, hoist to AppM
    AppEnv.hs              -- Reader env
    AppError.hs            -- domain errors + JSON responses
    Config.hs              -- env parsing; Show redacts the JWT secret
    Api/
      Auth.hs, RequestTypes.hs, Snippets.hs, Types.hs
    Handler/
      Auth.hs, Snippets.hs
    Service/
      Auth.hs              -- bcrypt + JWT
      Search.hs            -- termsToIlikePatterns
      Tags.hs              -- normalize
    Db/
      Pool.hs, Snippet.hs, User.hs
    Types/
      Common.hs, Snippet.hs, User.hs
  dbmate/migrations/
    001_initial_schema.sql
  test/
    Spec.hs, Service/{Tags,Search,Auth}Spec.hs
  run.sh, test-api.sh
```
