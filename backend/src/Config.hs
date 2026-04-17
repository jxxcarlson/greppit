module Config (Config(..), loadConfig) where

import Data.ByteString (ByteString)
import Data.Text (pack)
import Data.Text.Encoding (encodeUtf8)
import System.Environment (lookupEnv)
import Text.Read (readMaybe)

data Config = Config
  { configDbUrl         :: ByteString
  , configJwtSecret     :: ByteString
  , configJwtExpiryDays :: Int
  , configPort          :: Int
  }

-- | Hand-written Show so we never print the JWT secret.
instance Show Config where
  show c = "Config { configDbUrl = " <> show (configDbUrl c)
        <> ", configJwtSecret = <redacted>"
        <> ", configJwtExpiryDays = " <> show (configJwtExpiryDays c)
        <> ", configPort = " <> show (configPort c)
        <> " }"

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
envIntOrDefault name def = do
  mv <- lookupEnv name
  case mv of
    Nothing -> pure def
    Just s  -> case readMaybe s of
      Just n  -> pure n
      Nothing -> error $ "Config: env var " <> name <> "=" <> show s <> " is not an Int"
