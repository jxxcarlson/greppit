{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeOperators #-}

module Api.Auth (AuthAPI) where

import Servant
import Servant.Auth (Auth, JWT)
import Api.RequestTypes (SignupRequest, LoginRequest, AuthResponse, UserResponse)
import Service.Auth (AuthUser)

type AuthAPI =
       "signup" :> ReqBody '[JSON] SignupRequest :> Post '[JSON] AuthResponse
  :<|> "login"  :> ReqBody '[JSON] LoginRequest  :> Post '[JSON] AuthResponse
  :<|> "me"     :> Auth '[JWT] AuthUser :> Get '[JSON] UserResponse
