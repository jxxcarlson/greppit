-- migrate:up

-- dbmate wraps each migration in its own transaction, so no explicit
-- BEGIN/COMMIT here: doing so produces `unexpected transaction status idle`.

-- === Users: add username =======================================

ALTER TABLE users ADD COLUMN username TEXT;

WITH base AS (
  SELECT
    id,
    LOWER(REGEXP_REPLACE(SPLIT_PART(email, '@', 1), '[^a-z0-9]', '', 'gi')) AS base_name,
    created_at
  FROM users
),
numbered AS (
  SELECT
    id,
    base_name,
    ROW_NUMBER() OVER (PARTITION BY base_name ORDER BY created_at, id) AS rn
  FROM base
)
UPDATE users u
SET username = CASE WHEN n.rn = 1 THEN n.base_name
                    ELSE n.base_name || n.rn::text END
FROM numbered n
WHERE u.id = n.id;

DO $$
DECLARE bad int;
BEGIN
  SELECT COUNT(*) INTO bad FROM users WHERE username IS NULL OR username = '';
  IF bad > 0 THEN
    RAISE EXCEPTION 'Migration 003: % users produced empty usernames; inspect users.email before retrying', bad;
  END IF;
END$$;

ALTER TABLE users ALTER COLUMN username SET NOT NULL;
ALTER TABLE users ADD CONSTRAINT users_username_key UNIQUE (username);

-- === Snippets: add zku_id ======================================

ALTER TABLE snippets ADD COLUMN zku_id TEXT;

WITH base AS (
  SELECT
    s.id,
    u.username || '-' || to_char(s.created_at AT TIME ZONE 'UTC', 'YYYYMMDDHH24MISS') AS base_id,
    s.created_at
  FROM snippets s
  JOIN users u ON u.id = s.user_id
),
numbered AS (
  SELECT
    id,
    base_id,
    ROW_NUMBER() OVER (PARTITION BY base_id ORDER BY created_at, id) AS rn
  FROM base
)
UPDATE snippets s
SET zku_id = CASE WHEN n.rn = 1 THEN n.base_id
                  ELSE n.base_id || '-' || n.rn::text END
FROM numbered n
WHERE s.id = n.id;

ALTER TABLE snippets ALTER COLUMN zku_id SET NOT NULL;
ALTER TABLE snippets ADD CONSTRAINT snippets_zku_id_key UNIQUE (zku_id);

-- migrate:down

ALTER TABLE snippets DROP CONSTRAINT IF EXISTS snippets_zku_id_key;
ALTER TABLE snippets DROP COLUMN IF EXISTS zku_id;

ALTER TABLE users DROP CONSTRAINT IF EXISTS users_username_key;
ALTER TABLE users DROP COLUMN IF EXISTS username;
