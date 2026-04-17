{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeOperators #-}

module Api.Snippets (SnippetsAPI) where

import Data.Text (Text)
import Servant

import Api.RequestTypes
  ( SnippetResponse, CreateSnippetRequest, UpdateSnippetRequest )

type SnippetsAPI =
       -- GET /api/snippets?q=<terms>
       QueryParam "q" Text :> Get '[JSON] [SnippetResponse]

       -- POST /api/snippets
  :<|> ReqBody '[JSON] CreateSnippetRequest :> Post '[JSON] SnippetResponse

       -- GET /api/snippets/:id
  :<|> Capture "id" Text :> Get '[JSON] SnippetResponse

       -- PUT /api/snippets/:id
  :<|> Capture "id" Text :> ReqBody '[JSON] UpdateSnippetRequest :> Put '[JSON] SnippetResponse

       -- DELETE /api/snippets/:id
  :<|> Capture "id" Text :> DeleteNoContent
