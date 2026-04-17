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
  <$> D.column (D.nonNullable D.text)
  <*> D.column (D.nonNullable D.text)
  <*> D.column (D.nonNullable D.text)
  <*> D.column (D.nonNullable D.timestamptz)

insertUser :: Statement (UserId, Text, Text) ()
insertUser = Statement sql encoder D.noResult True
  where
    sql = "INSERT INTO users (id, email, pw_hash) VALUES ($1, $2, $3)"
    encoder =
      ((\(a,_,_) -> a) >$< E.param (E.nonNullable E.text)) <>
      ((\(_,b,_) -> b) >$< E.param (E.nonNullable E.text)) <>
      ((\(_,_,c) -> c) >$< E.param (E.nonNullable E.text))

getUserByEmail :: Statement Text (Maybe User)
getUserByEmail = Statement sql encoder decoder True
  where
    sql = "SELECT id, email, pw_hash, created_at FROM users WHERE email = $1"
    encoder = E.param (E.nonNullable E.text)
    decoder = D.rowMaybe userRow

getUserById :: Statement UserId (Maybe User)
getUserById = Statement sql encoder decoder True
  where
    sql = "SELECT id, email, pw_hash, created_at FROM users WHERE id = $1"
    encoder = E.param (E.nonNullable E.text)
    decoder = D.rowMaybe userRow
