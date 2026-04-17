{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeOperators #-}

module Api.Types (GreppitAPI) where

import Servant
import Api.Auth (AuthAPI)

type GreppitAPI =
       "api" :> "auth" :> AuthAPI
  :<|> "api" :> "health" :> Get '[JSON] String
