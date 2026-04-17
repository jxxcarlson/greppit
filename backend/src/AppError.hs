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
appErrorToServantErr NotFound            = jsonBody "not_found"      "Not found"     err404
appErrorToServantErr Forbidden           = jsonBody "forbidden"      "Forbidden"     err403
appErrorToServantErr Unauthorized        = jsonBody "unauthorized"   "Unauthorized"  err401
appErrorToServantErr (Conflict msg)      = jsonBody "conflict"       msg             err409
appErrorToServantErr (InvalidInput msg)  = jsonBody "invalid_input"  msg             err400
appErrorToServantErr (InternalError msg) = jsonBody "internal_error" msg             err500

jsonBody :: Text -> Text -> ServerError -> ServerError
jsonBody tag msg e = e
  { errBody    = encode $ object ["error" .= tag, "message" .= msg]
  , errHeaders = [("Content-Type", "application/json")]
  }
