{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeOperators #-}

module Api.Types (GreppitAPI) where

import Servant

type GreppitAPI =
  "api" :> "health" :> Get '[JSON] String
