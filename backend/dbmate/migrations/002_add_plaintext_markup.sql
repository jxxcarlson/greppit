-- migrate:up

ALTER TABLE snippets DROP CONSTRAINT snippets_markup_check;
ALTER TABLE snippets ADD CONSTRAINT snippets_markup_check
  CHECK (markup IN ('markdown', 'scripta', 'plaintext'));

-- migrate:down

-- This is a lossy down-migration: any rows with markup='plaintext' will be
-- rewritten to 'markdown' before the constraint tightens, to avoid a check
-- violation during rollback.
UPDATE snippets SET markup = 'markdown' WHERE markup = 'plaintext';
ALTER TABLE snippets DROP CONSTRAINT snippets_markup_check;
ALTER TABLE snippets ADD CONSTRAINT snippets_markup_check
  CHECK (markup IN ('markdown', 'scripta'));
