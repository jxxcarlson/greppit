module Config (Config(..), loadConfig, validateJwtSecret) where

import Data.ByteString (ByteString)
import qualified Data.ByteString as BS
import Data.Text (pack)
import Data.Text.Encoding (encodeUtf8)
import System.Environment (lookupEnv)
import System.Exit (die)
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
  jwtSecret <- either die pure . validateJwtSecret =<< lookupEnv "JWT_SECRET"
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

-- | JWT_SECRET must be set and at least 32 bytes (HS256). It must not be
-- the default this backend used to fall back to: that string is published
-- in this repo, so anyone could sign valid tokens with it.
validateJwtSecret :: Maybe String -> Either String String
validateJwtSecret Nothing =
  Left "Config: JWT_SECRET is not set. Put one in .env, e.g. the output of: openssl rand -base64 48"
validateJwtSecret (Just s)
  | s == publishedDefault =
      Left "Config: JWT_SECRET is the published default. Generate a new one: openssl rand -base64 48"
  | BS.length (encodeUtf8 (pack s)) < 32 =
      Left "Config: JWT_SECRET must be at least 32 bytes. Generate one: openssl rand -base64 48"
  | otherwise = Right s
  where
    publishedDefault = "dev-secret-change-in-production-min-32-chars!!"
