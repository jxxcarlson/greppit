{-# LANGUAGE OverloadedStrings #-}

module Service.AuthSpec (spec) where

import Test.Hspec
import Data.Maybe (isJust, fromJust)
import qualified Service.Auth as Auth

spec :: Spec
spec = describe "Service.Auth password hashing" $ do
  it "hashPassword returns Just on non-empty input" $ do
    h <- Auth.hashPassword "hunter2"
    h `shouldSatisfy` isJust

  it "checkPassword accepts the original password" $ do
    h <- fromJust <$> Auth.hashPassword "hunter2"
    Auth.checkPassword "hunter2" h `shouldBe` True

  it "checkPassword rejects a different password" $ do
    h <- fromJust <$> Auth.hashPassword "hunter2"
    Auth.checkPassword "wrong" h `shouldBe` False
