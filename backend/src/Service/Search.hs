{-# LANGUAGE OverloadedStrings #-}

module Service.Search (termsToIlikePatterns) where

import Data.Text (Text)
import qualified Data.Text as T
import Data.Vector (Vector)
import qualified Data.Vector as V

-- | Split the (optional) query string on whitespace and wrap each term
-- as a case-insensitive ILIKE pattern. Returns empty on Nothing / blank.
termsToIlikePatterns :: Maybe Text -> Vector Text
termsToIlikePatterns Nothing   = V.empty
termsToIlikePatterns (Just q)  =
  V.fromList [ "%" <> t <> "%" | t <- T.words q, not (T.null t) ]
