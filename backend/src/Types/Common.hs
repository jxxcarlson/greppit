module Types.Common
  ( UserId
  , SnippetId
  ) where

import Data.Text (Text)

type UserId    = Text
-- | An opaque identifier for a snippet: accepts either the internal UUID
-- `snippets.id` or the external `snippets.zku_id` wherever it appears in
-- a path capture or Db.Snippet statement parameter.
type SnippetId = Text
