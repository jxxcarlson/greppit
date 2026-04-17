{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE OverloadedStrings #-}

module App
  ( startApp
  , appToHandler
  ) where

import Control.Monad.Reader (runReaderT)
import Data.Proxy (Proxy(..))
import Network.Wai (Application)
import Network.Wai.Handler.Warp (run)
import Network.Wai.Middleware.Cors
  (cors, simpleCorsResourcePolicy, corsRequestHeaders, corsMethods, corsOrigins, CorsResourcePolicy)
import Network.HTTP.Types.Method (methodGet, methodPost, methodPut, methodDelete, methodOptions)
import Servant
import Servant.Auth.Server (defaultCookieSettings)

import AppEnv (AppEnv(..), AppM)
import Service.Auth (makeJwtSettings)
import Api.Types (GreppitAPI)
import Config (Config(..))
import Db.Pool (createPool)

server :: ServerT GreppitAPI AppM
server = pure "ok"

appToHandler :: AppEnv -> AppM a -> Handler a
appToHandler env action = runReaderT action env

corsPolicy :: CorsResourcePolicy
corsPolicy = simpleCorsResourcePolicy
  { corsOrigins = Nothing
  , corsMethods = [methodGet, methodPost, methodPut, methodDelete, methodOptions]
  , corsRequestHeaders = ["Authorization", "Content-Type"]
  }

mkApp :: AppEnv -> Application
mkApp env =
  cors (const $ Just corsPolicy)
    $ serve (Proxy :: Proxy GreppitAPI)
    $ hoistServer (Proxy :: Proxy GreppitAPI) (appToHandler env) server

startApp :: Config -> IO ()
startApp config = do
  pool <- createPool (configDbUrl config)
  let jwtSettings = makeJwtSettings (configJwtSecret config)
      env = AppEnv
        { envDbPool         = pool
        , envJwtSettings    = jwtSettings
        , envCookieSettings = defaultCookieSettings
        , envPort           = configPort config
        , envJwtExpiryDays  = configJwtExpiryDays config
        }
  putStrLn $ "greppit backend listening on port " <> show (configPort config)
  run (configPort config) (mkApp env)
