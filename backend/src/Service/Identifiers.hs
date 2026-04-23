{-# LANGUAGE OverloadedStrings #-}

module Service.Identifiers
  ( sanitizeUsername
  , formatZkuTimestamp
  ) where

import Data.Text (Text)
import qualified Data.Text as T
import Data.Time.Clock (UTCTime)
import Data.Time.Format (defaultTimeLocale, formatTime)

-- | Strip a string to [a-z0-9], lowercased.
-- Returns Nothing if no characters survive.
sanitizeUsername :: Text -> Maybe Text
sanitizeUsername t =
  let filtered = T.filter isAllowed (T.toLower t)
  in if T.null filtered then Nothing else Just filtered
  where
    isAllowed c = (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9')

-- | Format a UTCTime as YYYYMMDDHHMMSS (14 chars, zero-padded).
formatZkuTimestamp :: UTCTime -> Text
formatZkuTimestamp = T.pack . formatTime defaultTimeLocale "%Y%m%d%H%M%S"
