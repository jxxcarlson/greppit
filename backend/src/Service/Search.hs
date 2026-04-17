{-# LANGUAGE OverloadedStrings #-}

module Service.Search (termsToIlikePatterns) where

import Data.Text (Text)
import qualified Data.Text as T
import Data.Vector (Vector)
import qualified Data.Vector as V

-- | Escape LIKE wildcards so user input is matched literally.
escapeLike :: Text -> Text
escapeLike t =
  let t1 = T.replace "\\" "\\\\" t   -- first: backslashes
      t2 = T.replace "%"  "\\%"  t1  -- then: percents
      t3 = T.replace "_"  "\\_"  t2  -- then: underscores
  in  t3

-- | Split the (optional) query string on whitespace and wrap each term
-- as a case-insensitive ILIKE pattern. Returns empty on Nothing / blank.
termsToIlikePatterns :: Maybe Text -> Vector Text
termsToIlikePatterns Nothing   = V.empty
termsToIlikePatterns (Just q)  =
  V.fromList [ "%" <> escapeLike t <> "%" | t <- T.words q, not (T.null t) ]
