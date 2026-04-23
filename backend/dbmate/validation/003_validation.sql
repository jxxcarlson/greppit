-- Assertions that must hold on any DB after migration 003 runs.
-- Each DO block raises if an invariant fails.

-- A1: every user has a non-empty username
DO $$
DECLARE bad int;
BEGIN
  SELECT COUNT(*) INTO bad FROM users WHERE username IS NULL OR username = '';
  IF bad > 0 THEN RAISE EXCEPTION 'A1 FAIL: % users with null/empty username', bad; END IF;
END$$;

-- A2: usernames are unique
DO $$
DECLARE bad int;
BEGIN
  SELECT COUNT(*) INTO bad FROM (
    SELECT username FROM users GROUP BY username HAVING COUNT(*) > 1
  ) d;
  IF bad > 0 THEN RAISE EXCEPTION 'A2 FAIL: % duplicate usernames', bad; END IF;
END$$;

-- A3: usernames only contain [a-z0-9]
DO $$
DECLARE bad int;
BEGIN
  SELECT COUNT(*) INTO bad FROM users WHERE username !~ '^[a-z0-9]+$';
  IF bad > 0 THEN RAISE EXCEPTION 'A3 FAIL: % usernames with illegal chars', bad; END IF;
END$$;

-- A4: every snippet has a non-empty zku_id
DO $$
DECLARE bad int;
BEGIN
  SELECT COUNT(*) INTO bad FROM snippets WHERE zku_id IS NULL OR zku_id = '';
  IF bad > 0 THEN RAISE EXCEPTION 'A4 FAIL: % snippets with null/empty zku_id', bad; END IF;
END$$;

-- A5: zku_ids are unique
DO $$
DECLARE bad int;
BEGIN
  SELECT COUNT(*) INTO bad FROM (
    SELECT zku_id FROM snippets GROUP BY zku_id HAVING COUNT(*) > 1
  ) d;
  IF bad > 0 THEN RAISE EXCEPTION 'A5 FAIL: % duplicate zku_ids', bad; END IF;
END$$;

-- A6: every zku_id begins with its owner's username followed by '-'
DO $$
DECLARE bad int;
BEGIN
  SELECT COUNT(*) INTO bad
  FROM snippets s
  JOIN users u ON u.id = s.user_id
  WHERE s.zku_id NOT LIKE u.username || '-%';
  IF bad > 0 THEN RAISE EXCEPTION 'A6 FAIL: % zku_ids not prefixed by owner username', bad; END IF;
END$$;

-- A7: the 14-char timestamp segment of each zku_id matches created_at UTC
DO $$
DECLARE bad int;
BEGIN
  SELECT COUNT(*) INTO bad
  FROM snippets s
  JOIN users u ON u.id = s.user_id
  WHERE SUBSTRING(s.zku_id FROM LENGTH(u.username) + 2 FOR 14)
     <> to_char(s.created_at AT TIME ZONE 'UTC', 'YYYYMMDDHH24MISS');
  IF bad > 0 THEN RAISE EXCEPTION 'A7 FAIL: % zku_ids with wrong UTC timestamp segment', bad; END IF;
END$$;

-- Summary
SELECT 'users' AS tbl, COUNT(*) AS rows FROM users
UNION ALL
SELECT 'snippets', COUNT(*) FROM snippets;
