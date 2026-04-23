{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}

module Api.RequestTypes where

import Data.Aeson
  ( FromJSON(..), ToJSON(..), genericParseJSON, genericToJSON
  , defaultOptions, Options(..)
  )
import Data.Char (toLower)
import Data.Text (Text)
import Data.Time (UTCTime)
import GHC.Generics (Generic)

import Types.Common (UserId, SnippetId)

-- Strip a fixed prefix from Haskell field names when (de)serializing JSON,
-- then lower-case the next character. E.g. `srEmail` -> `email`.
stripPrefixOptions :: Int -> Options
stripPrefixOptions prefixLen = defaultOptions
  { fieldLabelModifier = \s ->
      case drop prefixLen s of
        []     -> s
        (c:cs) -> toLower c : cs
  }

-- Auth
data SignupRequest = SignupRequest
  { srEmail    :: Text
  , srPassword :: Text
  } deriving (Show, Generic)
instance FromJSON SignupRequest where
  parseJSON = genericParseJSON (stripPrefixOptions 2)

data LoginRequest = LoginRequest
  { lrEmail    :: Text
  , lrPassword :: Text
  } deriving (Show, Generic)
instance FromJSON LoginRequest where
  parseJSON = genericParseJSON (stripPrefixOptions 2)

data UserResponse = UserResponse
  { urId       :: UserId
  , urEmail    :: Text
  , urUsername :: Text
  } deriving (Show, Generic)
instance ToJSON UserResponse where
  toJSON = genericToJSON (stripPrefixOptions 2)

data AuthResponse = AuthResponse
  { arToken :: Text
  , arUser  :: UserResponse
  } deriving (Show, Generic)
instance ToJSON AuthResponse where
  toJSON = genericToJSON (stripPrefixOptions 2)

-- Snippets
data SnippetResponse = SnippetResponse
  { spRespId        :: SnippetId
  , spRespUserId    :: UserId
  , spRespZkuId     :: Text
  , spRespTitle     :: Text
  , spRespTags      :: Text
  , spRespMarkup    :: Text
  , spRespBody      :: Text
  , spRespCreatedAt :: UTCTime
  , spRespUpdatedAt :: UTCTime
  } deriving (Show, Generic)
instance ToJSON SnippetResponse where
  toJSON = genericToJSON (stripPrefixOptions 6)   -- strip "spResp"

data CreateSnippetRequest = CreateSnippetRequest
  { csrTitle  :: Text
  , csrTags   :: Text
  , csrMarkup :: Text
  , csrBody   :: Text
  } deriving (Show, Generic)
instance FromJSON CreateSnippetRequest where
  parseJSON = genericParseJSON (stripPrefixOptions 3)

data UpdateSnippetRequest = UpdateSnippetRequest
  { usrTitle  :: Text
  , usrTags   :: Text
  , usrMarkup :: Text
  , usrBody   :: Text
  } deriving (Show, Generic)
instance FromJSON UpdateSnippetRequest where
  parseJSON = genericParseJSON (stripPrefixOptions 3)
