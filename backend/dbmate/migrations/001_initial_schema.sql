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
