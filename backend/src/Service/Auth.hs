{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE DeriveGeneric #-}

module Service.Auth
  ( AuthUser(..)
  , hashPassword
  , checkPassword
  , makeJwtSettings
  ) where

import Crypto.BCrypt (hashPasswordUsingPolicy, slowerBcryptHashingPolicy, validatePassword)
import Data.Aeson (FromJSON, ToJSON)
import Data.ByteString (ByteString)
import Data.Text (Text)
import Data.Text.Encoding (encodeUtf8, decodeUtf8)
import GHC.Generics (Generic)
import Servant.Auth.Server (FromJWT, ToJWT, JWTSettings, defaultJWTSettings)
import Crypto.JOSE.JWK (fromOctets)

import Types.Common (UserId)

data AuthUser = AuthUser
  { auUserId :: UserId
  , auEmail  :: Text
  } deriving (Show, Eq, Generic)

instance FromJSON AuthUser
instance ToJSON   AuthUser
instance FromJWT  AuthUser
instance ToJWT    AuthUser

hashPassword :: Text -> IO (Maybe Text)
hashPassword password = do
  result <- hashPasswordUsingPolicy slowerBcryptHashingPolicy (encodeUtf8 password)
  pure (decodeUtf8 <$> result)

checkPassword :: Text -> Text -> Bool
checkPassword password hash =
  validatePassword (encodeUtf8 hash) (encodeUtf8 password)

makeJwtSettings :: ByteString -> JWTSettings
makeJwtSettings secret = defaultJWTSettings (fromOctets secret)
