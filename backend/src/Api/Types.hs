{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeOperators #-}

module Api.Types (GreppitAPI) where

import Servant
import Servant.Auth (Auth, JWT)
import Service.Auth (AuthUser)
import Api.Auth (AuthAPI)
import Api.Snippets (SnippetsAPI)

type GreppitAPI =
       "api" :> "auth"     :> AuthAPI
  :<|> "api" :> "snippets" :> Auth '[JWT] AuthUser :> SnippetsAPI
  :<|> "api" :> "health"   :> Get '[JSON] String
