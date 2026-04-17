{-# LANGUAGE OverloadedStrings #-}

module AppError
  ( AppError(..)
  , appErrorToServantErr
  ) where

import Data.Aeson (object, (.=), encode)
import Data.Text (Text)
import Servant (ServerError(..), err400, err401, err403, err404, err409, err500)

data AppError
  = NotFound
  | Forbidden
  | Unauthorized
  | Conflict Text
  | InvalidInput Text
  | InternalError Text
  deriving (Show, Eq)

appErrorToServantErr :: AppError -> ServerError
appErrorToServantErr NotFound =
  err404 { errBody = encode $ object
    ["error" .= ("not_found" :: Text), "message" .= ("Not found" :: Text)] }
appErrorToServantErr Forbidden =
  err403 { errBody = encode $ object
    ["error" .= ("forbidden" :: Text), "message" .= ("Forbidden" :: Text)] }
appErrorToServantErr Unauthorized =
  err401 { errBody = encode $ object
    ["error" .= ("unauthorized" :: Text), "message" .= ("Unauthorized" :: Text)] }
appErrorToServantErr (Conflict msg) =
  err409 { errBody = encode $ object
    ["error" .= ("conflict" :: Text), "message" .= msg] }
appErrorToServantErr (InvalidInput msg) =
  err400 { errBody = encode $ object
    ["error" .= ("invalid_input" :: Text), "message" .= msg] }
appErrorToServantErr (InternalError msg) =
  err500 { errBody = encode $ object
    ["error" .= ("internal_error" :: Text), "message" .= msg] }
