{-# LANGUAGE OverloadedStrings #-}
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
  , snpTags      :: Text
  , snpMarkup    :: Markup
  , snpBody      :: Text
  , snpCreatedAt :: UTCTime
  , snpUpdatedAt :: UTCTime
  } deriving (Show, Eq)
