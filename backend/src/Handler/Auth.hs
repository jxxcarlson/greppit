{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}

module Handler.Auth
  ( signupHandler
  , loginHandler
  , meHandler
  , requireAuthUser
  , uniqueViolationConstraint
  ) where

import Control.Monad.IO.Class (liftIO)
import Control.Monad.Reader (asks)
import qualified Data.ByteString.Lazy as LBS
import Data.ByteString (ByteString)
import Data.Text (Text)
import qualified Data.Text as T
import Data.Text.Encoding (decodeUtf8, decodeUtf8Lenient)
import Data.Time.Clock (getCurrentTime, UTCTime, addUTCTime)
import qualified Data.UUID as UUID
import qualified Data.UUID.V4 as UUID
import Servant (throwError)
import Servant.Auth.Server (AuthResult(..), makeJWT)
import qualified Hasql.Pool as Pool
import qualified Hasql.Session as Session

import AppEnv (AppEnv(..), AppM)
import AppError (AppError(..), appErrorToServantErr)
import Api.RequestTypes
  ( SignupRequest(..), LoginRequest(..), AuthResponse(..), UserResponse(..) )
import Service.Auth (AuthUser(..), hashPassword, checkPassword)
import Service.Identifiers (sanitizeUsername)
import Types.Common (UserId)
import Types.User (User(..))
import qualified Db.User as Db

-- | Require an Authenticated result; return the whole AuthUser.
requireAuthUser :: AuthResult AuthUser -> AppM AuthUser
requireAuthUser (Authenticated au) = pure au
requireAuthUser _                  = throwError $ appErrorToServantErr Unauthorized

signupHandler :: SignupRequest -> AppM AuthResponse
signupHandler req = do
  pool        <- asks envDbPool
  jwtSettings <- asks envJwtSettings
  expDays     <- asks envJwtExpiryDays
  base <- case sanitizeUsername (localPart (srEmail req)) of
    Just b  -> pure b
    Nothing -> throwError $ appErrorToServantErr
                 (InvalidInput "We couldn't create a username from your email. Please use an email that contains letters or numbers before the '@' sign.")
  userId <- liftIO $ UUID.toText <$> UUID.nextRandom
  mHash  <- liftIO $ hashPassword (srPassword req)
  case mHash of
    Nothing   ->
      throwError $ appErrorToServantErr (InternalError "password hashing failed")
    Just hash -> do
      chosen <- tryInsertUser pool userId (srEmail req) hash (usernameCandidates base)
      let au = AuthUser userId (srEmail req) chosen
      expTime <- liftIO $ expiryFromNow expDays
      eTok <- liftIO $ makeJWT au jwtSettings (Just expTime)
      case eTok of
        Left _ ->
          throwError $ appErrorToServantErr (InternalError "token generation failed")
        Right tokBS -> pure AuthResponse
          { arToken = decodeUtf8 (LBS.toStrict tokBS)
          , arUser  = UserResponse userId (srEmail req) chosen
          }

loginHandler :: LoginRequest -> AppM AuthResponse
loginHandler req = do
  pool        <- asks envDbPool
  jwtSettings <- asks envJwtSettings
  expDays     <- asks envJwtExpiryDays
  result <- liftIO $ Pool.use pool $ Session.statement
              (lrEmail req) Db.getUserByEmail
  case result of
    Left _ ->
      throwError $ appErrorToServantErr (InternalError "database error")
    Right Nothing ->
      throwError $ appErrorToServantErr Unauthorized
    Right (Just user)
      | checkPassword (lrPassword req) (usrPwHash user) -> do
          let au = AuthUser (usrId user) (usrEmail user) (usrUsername user)
          expTime <- liftIO $ expiryFromNow expDays
          eTok <- liftIO $ makeJWT au jwtSettings (Just expTime)
          case eTok of
            Left _ -> throwError $ appErrorToServantErr (InternalError "token generation failed")
            Right tokBS -> pure AuthResponse
              { arToken = decodeUtf8 (LBS.toStrict tokBS)
              , arUser  = UserResponse (usrId user) (usrEmail user) (usrUsername user)
              }
      | otherwise -> throwError $ appErrorToServantErr Unauthorized

meHandler :: AuthResult AuthUser -> AppM UserResponse
meHandler (Authenticated au) =
  pure $ UserResponse (auUserId au) (auEmail au) (auUsername au)
meHandler _ =
  throwError $ appErrorToServantErr Unauthorized

-- | Compute an expiry time N days from now.
expiryFromNow :: Int -> IO UTCTime
expiryFromNow days = do
  now <- getCurrentTime
  pure $ addUTCTime (fromIntegral days * 86400) now

-- | Extract the local-part of an email (everything before '@').
localPart :: Text -> Text
localPart = T.takeWhile (/= '@')

-- | Candidate usernames: [base, base<>"2", ..., base<>"100"].
usernameCandidates :: Text -> [Text]
usernameCandidates base = base : [base <> T.pack (show n) | n <- [(2 :: Int) .. 100]]

-- | Try inserting a user with each candidate username. On 23505 against
-- users_username_key, advance to the next candidate. On 23505 against
-- users_email_key, fail with 409. On exhaustion, fail with 500.
tryInsertUser
  :: Pool.Pool
  -> UserId
  -> Text       -- email
  -> Text       -- pwHash
  -> [Text]     -- candidate usernames
  -> AppM Text  -- chosen username
tryInsertUser _ _ _ _ [] =
  throwError $ appErrorToServantErr (InternalError "could not derive a unique username")
tryInsertUser pool uid email pw (candidate:rest) = do
  result <- liftIO $ Pool.use pool $ Session.statement
              (uid, email, pw, candidate) Db.insertUser
  case result of
    Right () -> pure candidate
    Left err -> case uniqueViolationConstraint err of
      Just "users_email_key"    ->
        throwError $ appErrorToServantErr (Conflict "email already registered")
      Just "users_username_key" ->
        tryInsertUser pool uid email pw rest
      _ ->
        throwError $ appErrorToServantErr (InternalError "database error")

-- | For a Postgres unique-violation (SQLSTATE 23505), return the constraint
-- name. For any other error, return Nothing.
uniqueViolationConstraint :: Pool.UsageError -> Maybe Text
uniqueViolationConstraint = \case
  Pool.SessionUsageError (Session.QueryError _ _
    (Session.ResultError (Session.ServerError code msg _ _ _)))
      | code == "23505" -> extractConstraint msg
      | otherwise       -> Nothing
  _ -> Nothing
  where
    -- Postgres message format (all locales quote the constraint name):
    --   duplicate key value violates unique constraint "NAME"
    -- splitOn "\"" yields [before, NAME, after]. We take element 1.
    -- Lenient UTF-8 decoding avoids a partial-function crash if lc_messages
    -- is ever set to a non-UTF-8 locale.
    extractConstraint :: ByteString -> Maybe Text
    extractConstraint bs = case T.splitOn "\"" (decodeUtf8Lenient bs) of
      (_ : name : _) -> Just name
      _              -> Nothing
