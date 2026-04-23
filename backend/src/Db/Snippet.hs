{-# LANGUAGE OverloadedStrings #-}

module Db.Snippet
  ( insertSnippet
  , getSnippetById
  , updateSnippet
  , deleteSnippet
  , searchSnippets
  , listAllSnippets
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
-- Columns: id, user_id, zku_id, title, tags, markup, body, created_at, updated_at
snippetRow :: D.Row Snippet
snippetRow = Snippet
  <$> D.column (D.nonNullable D.text)        -- id
  <*> D.column (D.nonNullable D.text)        -- user_id
  <*> D.column (D.nonNullable D.text)        -- zku_id
  <*> D.column (D.nonNullable D.text)        -- title
  <*> D.column (D.nonNullable D.text)        -- tags
  <*> D.column (D.nonNullable (D.refine refineMarkup D.text))
  <*> D.column (D.nonNullable D.text)        -- body
  <*> D.column (D.nonNullable D.timestamptz) -- created_at
  <*> D.column (D.nonNullable D.timestamptz) -- updated_at
  where
    refineMarkup :: Text -> Either Text Markup
    refineMarkup t = case parseMarkup t of
      Just m  -> Right m
      Nothing -> Left ("unknown markup: " <> t)

-- | INSERT a snippet. Takes (id, userId, zkuId, title, tags, markup, body).
-- created_at / updated_at default to now() on the DB side.
insertSnippet :: Statement (SnippetId, UserId, Text, Text, Text, Text, Text) ()
insertSnippet = Statement sql encoder D.noResult True
  where
    sql = "INSERT INTO snippets (id, user_id, zku_id, title, tags, markup, body) \
          \VALUES ($1, $2, $3, $4, $5, $6, $7)"
    encoder =
      ((\(a,_,_,_,_,_,_) -> a) >$< E.param (E.nonNullable E.text)) <>
      ((\(_,b,_,_,_,_,_) -> b) >$< E.param (E.nonNullable E.text)) <>
      ((\(_,_,c,_,_,_,_) -> c) >$< E.param (E.nonNullable E.text)) <>
      ((\(_,_,_,d,_,_,_) -> d) >$< E.param (E.nonNullable E.text)) <>
      ((\(_,_,_,_,e,_,_) -> e) >$< E.param (E.nonNullable E.text)) <>
      ((\(_,_,_,_,_,f,_) -> f) >$< E.param (E.nonNullable E.text)) <>
      ((\(_,_,_,_,_,_,g) -> g) >$< E.param (E.nonNullable E.text))

-- | Fetch a snippet scoped to a user, by either its UUID `id`
-- or its external `zku_id`. Returns Nothing if not owned / missing.
getSnippetById :: Statement (SnippetId, UserId) (Maybe Snippet)
getSnippetById = Statement sql encoder (D.rowMaybe snippetRow) True
  where
    sql = "SELECT id, user_id, zku_id, title, tags, markup, body, created_at, updated_at \
          \FROM snippets WHERE (id = $1 OR zku_id = $1) AND user_id = $2"
    encoder =
      (fst >$< E.param (E.nonNullable E.text)) <>
      (snd >$< E.param (E.nonNullable E.text))

-- | UPDATE a snippet's mutable fields. Also bumps updated_at = now().
-- zku_id is NOT part of the SET list — it's immutable by design.
-- Matches on either the UUID `id` or the `zku_id`.
-- Takes (id, userId, title, tags, markup, body). Returns rows affected.
updateSnippet :: Statement (SnippetId, UserId, Text, Text, Text, Text) Int
updateSnippet = Statement sql encoder (fromIntegral <$> D.rowsAffected) True
  where
    sql = "UPDATE snippets \
          \SET title = $3, tags = $4, markup = $5, body = $6, updated_at = now() \
          \WHERE (id = $1 OR zku_id = $1) AND user_id = $2"
    encoder =
      ((\(a,_,_,_,_,_) -> a) >$< E.param (E.nonNullable E.text)) <>
      ((\(_,b,_,_,_,_) -> b) >$< E.param (E.nonNullable E.text)) <>
      ((\(_,_,c,_,_,_) -> c) >$< E.param (E.nonNullable E.text)) <>
      ((\(_,_,_,d,_,_) -> d) >$< E.param (E.nonNullable E.text)) <>
      ((\(_,_,_,_,e,_) -> e) >$< E.param (E.nonNullable E.text)) <>
      ((\(_,_,_,_,_,f) -> f) >$< E.param (E.nonNullable E.text))

-- | DELETE a snippet scoped to a user. Matches on UUID `id` or `zku_id`.
-- Returns rows affected (0 or 1).
deleteSnippet :: Statement (SnippetId, UserId) Int
deleteSnippet = Statement sql encoder (fromIntegral <$> D.rowsAffected) True
  where
    sql = "DELETE FROM snippets WHERE (id = $1 OR zku_id = $1) AND user_id = $2"
    encoder =
      (fst >$< E.param (E.nonNullable E.text)) <>
      (snd >$< E.param (E.nonNullable E.text))

-- | Search / list. `patterns` is a Vector of ILIKE patterns (each "%term%");
-- empty vector means "no predicates". Uses Postgres ILIKE ALL over an array.
-- Always returns the 5 most recently updated matches.
searchSnippets :: Statement (UserId, Vector Text) (Vector Snippet)
searchSnippets = Statement sql encoder (D.rowVector snippetRow) True
  where
    sql = "SELECT id, user_id, zku_id, title, tags, markup, body, created_at, updated_at \
          \FROM snippets \
          \WHERE user_id = $1 \
          \  AND (title || ' ' || tags || ' ' || body) ILIKE ALL ($2 :: text[]) \
          \ORDER BY updated_at DESC \
          \LIMIT 5"
    encoder =
      (fst >$< E.param (E.nonNullable E.text)) <>
      (snd >$< E.param (E.nonNullable
        (E.array (E.dimension foldl (E.element (E.nonNullable E.text))))))

-- | List every snippet owned by the user, newest-updated first.
-- No text filter. No LIMIT. Used by the @all sentinel path.
listAllSnippets :: Statement UserId (Vector Snippet)
listAllSnippets = Statement sql encoder (D.rowVector snippetRow) True
  where
    sql = "SELECT id, user_id, zku_id, title, tags, markup, body, created_at, updated_at \
          \FROM snippets \
          \WHERE user_id = $1 \
          \ORDER BY updated_at DESC"
    encoder = E.param (E.nonNullable E.text)
