{-# LANGUAGE OverloadedStrings #-}

module Handler.Auth
  ( signupHandler
  , loginHandler
  , meHandler
  ) where

import Control.Monad.IO.Class (liftIO)
import Control.Monad.Reader (asks)
import qualified Data.ByteString.Lazy as LBS
import Data.Text.Encoding (decodeUtf8)
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
import Types.User (User(..))
import qualified Db.User as Db

signupHandler :: SignupRequest -> AppM AuthResponse
signupHandler req = do
  pool        <- asks envDbPool
  jwtSettings <- asks envJwtSettings
  expDays     <- asks envJwtExpiryDays
  userId      <- liftIO $ UUID.toText <$> UUID.nextRandom
  mHash       <- liftIO $ hashPassword (srPassword req)
  case mHash of
    Nothing ->
      throwError $ appErrorToServantErr (InternalError "password hashing failed")
    Just hash -> do
      result <- liftIO $ Pool.use pool $ Session.statement
                  (userId, srEmail req, hash) Db.insertUser
      case result of
        Left err
          | isUniqueViolation err ->
              throwError $ appErrorToServantErr (Conflict "email already registered")
          | otherwise ->
              throwError $ appErrorToServantErr (InternalError "database error")
        Right () -> do
          let au = AuthUser userId (srEmail req)
          expTime <- liftIO $ expiryFromNow expDays
          eTok <- liftIO $ makeJWT au jwtSettings (Just expTime)
          case eTok of
            Left _ ->
              throwError $ appErrorToServantErr (InternalError "token generation failed")
            Right tokBS -> pure AuthResponse
              { arToken = decodeUtf8 (LBS.toStrict tokBS)
              , arUser  = UserResponse userId (srEmail req)
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
          let au = AuthUser (usrId user) (usrEmail user)
          expTime <- liftIO $ expiryFromNow expDays
          eTok <- liftIO $ makeJWT au jwtSettings (Just expTime)
          case eTok of
            Left _ -> throwError $ appErrorToServantErr (InternalError "token generation failed")
            Right tokBS -> pure AuthResponse
              { arToken = decodeUtf8 (LBS.toStrict tokBS)
              , arUser  = UserResponse (usrId user) (usrEmail user)
              }
      | otherwise -> throwError $ appErrorToServantErr Unauthorized

meHandler :: AuthResult AuthUser -> AppM UserResponse
meHandler (Authenticated au) =
  pure $ UserResponse (auUserId au) (auEmail au)
meHandler _ =
  throwError $ appErrorToServantErr Unauthorized

-- | Compute an expiry time N days from now.
expiryFromNow :: Int -> IO UTCTime
expiryFromNow days = do
  now <- getCurrentTime
  pure $ addUTCTime (fromIntegral days * 86400) now

-- | Is this pool error a Postgres unique_violation (SQLSTATE 23505)?
isUniqueViolation :: Pool.UsageError -> Bool
isUniqueViolation (Pool.SessionUsageError (Session.QueryError _ _ (Session.ResultError (Session.ServerError code _ _ _ _)))) =
  code == "23505"
isUniqueViolation _ = False
