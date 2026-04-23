{-# LANGUAGE OverloadedStrings #-}
module Types.Snippet (Snippet(..), Markup(..), parseMarkup, markupText) where

import Data.Text (Text)
import Data.Time (UTCTime)
import Types.Common (UserId, SnippetId)

data Markup = Markdown | Scripta | PlainText
  deriving (Show, Eq)

parseMarkup :: Text -> Maybe Markup
parseMarkup "markdown"  = Just Markdown
parseMarkup "scripta"   = Just Scripta
parseMarkup "plaintext" = Just PlainText
parseMarkup _           = Nothing

markupText :: Markup -> Text
markupText Markdown  = "markdown"
markupText Scripta   = "scripta"
markupText PlainText = "plaintext"

-- NOTE: Field order matters. `Db.Snippet.snippetRow` is a positional
-- applicative decoder that depends on this order matching the DB column
-- order `id, user_id, zku_id, title, tags, markup, body, created_at,
-- updated_at`. Reordering fields here without updating `snippetRow` and
-- every SELECT column list in `Db.Snippet` will silently produce
-- type-correct but semantically garbage rows.
data Snippet = Snippet
  { snpId        :: SnippetId
  , snpUserId    :: UserId
  , snpZkuId     :: Text
  , snpTitle     :: Text
  , snpTags      :: Text
  , snpMarkup    :: Markup
  , snpBody      :: Text
  , snpCreatedAt :: UTCTime
  , snpUpdatedAt :: UTCTime
  } deriving (Show, Eq)
