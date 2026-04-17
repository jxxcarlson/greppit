module Config (Config(..), loadConfig) where

import Data.ByteString (ByteString)
import Data.Text (pack)
import Data.Text.Encoding (encodeUtf8)
import System.Environment (lookupEnv)

data Config = Config
  { configDbUrl         :: ByteString
  , configJwtSecret     :: ByteString
  , configJwtExpiryDays :: Int
  , configPort          :: Int
  } deriving (Show)

loadConfig :: IO Config
loadConfig = do
  dbUrl     <- envOrDefault "DATABASE_URL" "postgres://localhost/greppit_dev"
  jwtSecret <- envOrDefault "JWT_SECRET"   "dev-secret-change-in-production-min-32-chars!!"
  jwtExpiry <- envIntOrDefault "JWT_EXPIRY_DAYS" 7
  port      <- envIntOrDefault "PORT" 8085
  pure Config
    { configDbUrl         = encodeUtf8 (pack dbUrl)
    , configJwtSecret     = encodeUtf8 (pack jwtSecret)
    , configJwtExpiryDays = jwtExpiry
    , configPort          = port
    }

envOrDefault :: String -> String -> IO String
envOrDefault name def = maybe def id <$> lookupEnv name

envIntOrDefault :: String -> Int -> IO Int
envIntOrDefault name def = maybe def read <$> lookupEnv name
