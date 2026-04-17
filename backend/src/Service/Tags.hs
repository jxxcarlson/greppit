{-# LANGUAGE OverloadedStrings #-}

module Service.Tags (normalize) where

import Data.Text (Text)
import qualified Data.Text as T

-- | Lowercase, split on whitespace runs, rejoin with single spaces.
-- Returns "" for all-whitespace / empty input.
normalize :: Text -> Text
normalize = T.unwords . T.words . T.toLower
