{-# LANGUAGE OverloadedStrings #-}

module Handler.Snippets
  ( listSnippetsHandler
  , createSnippetHandler
  , getSnippetHandler
  , updateSnippetHandler
  , deleteSnippetHandler
  ) where

import Control.Monad.IO.Class (liftIO)
import Control.Monad.Reader (asks)
import Data.Text (Text)
import qualified Data.UUID as UUID
import qualified Data.UUID.V4 as UUID
import qualified Data.Vector as V
import Servant (NoContent(..), throwError)
import Servant.Auth.Server (AuthResult(..))
import qualified Hasql.Pool as Pool
import qualified Hasql.Session as Session

import AppEnv (AppEnv(..), AppM)
import AppError (AppError(..), appErrorToServantErr)
import Api.RequestTypes
  ( SnippetResponse(..)
  , CreateSnippetRequest(..)
  , UpdateSnippetRequest(..)
  )
import Service.Auth (AuthUser(..))
import qualified Service.Search as Search
import qualified Service.Tags as Tags
import qualified Db.Snippet as Db
import Types.Common (SnippetId, UserId)
import Types.Snippet (Snippet(..), parseMarkup, markupText)

-- | Extract the current user id from a Servant.Auth AuthResult, or 401.
requireUser :: AuthResult AuthUser -> AppM UserId
requireUser (Authenticated au) = pure (auUserId au)
requireUser _ = throwError $ appErrorToServantErr Unauthorized

-- | Convert a Snippet domain value into its JSON response.
toResp :: Snippet -> SnippetResponse
toResp s = SnippetResponse
  { spRespId        = snpId s
  , spRespUserId    = snpUserId s
  , spRespTitle     = snpTitle s
  , spRespTags      = snpTags s
  , spRespMarkup    = markupText (snpMarkup s)
  , spRespBody      = snpBody s
  , spRespCreatedAt = snpCreatedAt s
  , spRespUpdatedAt = snpUpdatedAt s
  }

-- | Validate the markup string from the client.
parseMarkupOrFail :: Text -> AppM Text
parseMarkupOrFail t = case parseMarkup t of
  Just _  -> pure t
  Nothing -> throwError $ appErrorToServantErr
               (InvalidInput "markup must be \"markdown\", \"plaintext\", or \"scripta\"")

listSnippetsHandler
  :: AuthResult AuthUser -> Maybe Text -> AppM [SnippetResponse]
listSnippetsHandler auth mq = do
  userId <- requireUser auth
  pool   <- asks envDbPool
  result <- liftIO $ Pool.use pool $
    if Search.isAllSentinel mq
      then Session.statement userId Db.listAllSnippets
      else let patterns = Search.termsToIlikePatterns mq
           in Session.statement (userId, patterns) Db.searchSnippets
  case result of
    Left _    -> throwError $ appErrorToServantErr (InternalError "database error")
    Right vec -> pure $ map toResp (V.toList vec)

createSnippetHandler
  :: AuthResult AuthUser -> CreateSnippetRequest -> AppM SnippetResponse
createSnippetHandler auth req = do
  userId <- requireUser auth
  pool   <- asks envDbPool
  _      <- parseMarkupOrFail (csrMarkup req)
  let normTags = Tags.normalize (csrTags req)
  sid <- liftIO $ UUID.toText <$> UUID.nextRandom
  insRes <- liftIO $ Pool.use pool $ Session.statement
              (sid, userId, csrTitle req, normTags, csrMarkup req, csrBody req)
              Db.insertSnippet
  case insRes of
    Left _   -> throwError $ appErrorToServantErr (InternalError "database error")
    Right () -> do
      -- Re-fetch so we return the DB-populated timestamps.
      g <- liftIO $ Pool.use pool $
             Session.statement (sid, userId) Db.getSnippetById
      case g of
        Right (Just s) -> pure (toResp s)
        _ -> throwError $ appErrorToServantErr (InternalError "snippet vanished after insert")

getSnippetHandler
  :: AuthResult AuthUser -> SnippetId -> AppM SnippetResponse
getSnippetHandler auth sid = do
  userId <- requireUser auth
  pool   <- asks envDbPool
  r      <- liftIO $ Pool.use pool $
              Session.statement (sid, userId) Db.getSnippetById
  case r of
    Left _          -> throwError $ appErrorToServantErr (InternalError "database error")
    Right Nothing   -> throwError $ appErrorToServantErr NotFound
    Right (Just s)  -> pure (toResp s)

updateSnippetHandler
  :: AuthResult AuthUser -> SnippetId -> UpdateSnippetRequest -> AppM SnippetResponse
updateSnippetHandler auth sid req = do
  userId <- requireUser auth
  pool   <- asks envDbPool
  _      <- parseMarkupOrFail (usrMarkup req)
  let normTags = Tags.normalize (usrTags req)
  updRes <- liftIO $ Pool.use pool $ Session.statement
              (sid, userId, usrTitle req, normTags, usrMarkup req, usrBody req)
              Db.updateSnippet
  case updRes of
    Left _        -> throwError $ appErrorToServantErr (InternalError "database error")
    Right 0       -> throwError $ appErrorToServantErr NotFound
    Right _       -> do
      g <- liftIO $ Pool.use pool $
             Session.statement (sid, userId) Db.getSnippetById
      case g of
        Right (Just s) -> pure (toResp s)
        _              -> throwError $ appErrorToServantErr (InternalError "snippet vanished after update")

deleteSnippetHandler
  :: AuthResult AuthUser -> SnippetId -> AppM NoContent
deleteSnippetHandler auth sid = do
  userId <- requireUser auth
  pool   <- asks envDbPool
  r      <- liftIO $ Pool.use pool $
              Session.statement (sid, userId) Db.deleteSnippet
  case r of
    Left _   -> throwError $ appErrorToServantErr (InternalError "database error")
    Right 0  -> throwError $ appErrorToServantErr NotFound
    Right _  -> pure NoContent
