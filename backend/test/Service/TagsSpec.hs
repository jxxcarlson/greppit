{-# LANGUAGE OverloadedStrings #-}

module Service.TagsSpec (spec) where

import Test.Hspec
import qualified Service.Tags as Tags

spec :: Spec
spec = describe "Service.Tags.normalize" $ do
  it "leaves a clean single word alone" $
    Tags.normalize "elm" `shouldBe` "elm"

  it "lowercases tags" $
    Tags.normalize "Elm Howto" `shouldBe` "elm howto"

  it "collapses multiple spaces" $
    Tags.normalize "elm   howto    postgres" `shouldBe` "elm howto postgres"

  it "strips leading and trailing whitespace" $
    Tags.normalize "   elm howto   " `shouldBe` "elm howto"

  it "normalizes tabs and newlines to single spaces" $
    Tags.normalize "elm\thowto\npostgres" `shouldBe` "elm howto postgres"

  it "returns empty string for all-whitespace input" $
    Tags.normalize "   \t \n " `shouldBe` ""

  it "returns empty string for empty input" $
    Tags.normalize "" `shouldBe` ""
