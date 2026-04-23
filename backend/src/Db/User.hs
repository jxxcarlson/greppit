{-# LANGUAGE OverloadedStrings #-}

module Db.User
  ( insertUser
  , getUserByEmail
  , getUserById
  ) where

import Data.Functor.Contravariant ((>$<))
import Data.Text (Text)
import Hasql.Statement (Statement(..))
import qualified Hasql.Encoders as E
import qualified Hasql.Decoders as D

import Types.Common (UserId)
import Types.User (User(..))

userRow :: D.Row User
userRow = User
  <$> D.column (D.nonNullable D.text)       -- id
  <*> D.column (D.nonNullable D.text)       -- email
  <*> D.column (D.nonNullable D.text)       -- pw_hash
  <*> D.column (D.nonNullable D.text)       -- username
  <*> D.column (D.nonNullable D.timestamptz) -- created_at

-- | INSERT a user. Takes (id, email, pwHash, username).
insertUser :: Statement (UserId, Text, Text, Text) ()
insertUser = Statement sql encoder D.noResult True
  where
    sql = "INSERT INTO users (id, email, pw_hash, username) VALUES ($1, $2, $3, $4)"
    encoder =
      ((\(a,_,_,_) -> a) >$< E.param (E.nonNullable E.text)) <>
      ((\(_,b,_,_) -> b) >$< E.param (E.nonNullable E.text)) <>
      ((\(_,_,c,_) -> c) >$< E.param (E.nonNullable E.text)) <>
      ((\(_,_,_,d) -> d) >$< E.param (E.nonNullable E.text))

getUserByEmail :: Statement Text (Maybe User)
getUserByEmail = Statement sql encoder decoder True
  where
    sql = "SELECT id, email, pw_hash, username, created_at FROM users WHERE email = $1"
    encoder = E.param (E.nonNullable E.text)
    decoder = D.rowMaybe userRow

getUserById :: Statement UserId (Maybe User)
getUserById = Statement sql encoder decoder True
  where
    sql = "SELECT id, email, pw_hash, username, created_at FROM users WHERE id = $1"
    encoder = E.param (E.nonNullable E.text)
    decoder = D.rowMaybe userRow
