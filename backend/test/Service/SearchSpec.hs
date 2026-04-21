{-# LANGUAGE OverloadedStrings #-}

module Service.SearchSpec (spec) where

import Test.Hspec
import qualified Data.Vector as V
import qualified Service.Search as Search

spec :: Spec
spec = do
  describe "Service.Search.termsToIlikePatterns" $ do
    it "returns empty vector for Nothing" $
      Search.termsToIlikePatterns Nothing `shouldBe` V.empty

    it "returns empty vector for empty string" $
      Search.termsToIlikePatterns (Just "") `shouldBe` V.empty

    it "returns empty vector for whitespace-only" $
      Search.termsToIlikePatterns (Just "   \t  ") `shouldBe` V.empty

    it "wraps a single term in percent signs" $
      Search.termsToIlikePatterns (Just "elm") `shouldBe` V.fromList ["%elm%"]

    it "splits multiple terms and wraps each" $
      Search.termsToIlikePatterns (Just "elm howto")
        `shouldBe` V.fromList ["%elm%", "%howto%"]

    it "collapses multiple whitespace" $
      Search.termsToIlikePatterns (Just "  elm   howto  ")
        `shouldBe` V.fromList ["%elm%", "%howto%"]

    it "escapes percent sign so literal % matches" $
      Search.termsToIlikePatterns (Just "50%")
        `shouldBe` V.fromList ["%50\\%%"]

    it "escapes underscore so literal _ matches" $
      Search.termsToIlikePatterns (Just "a_b")
        `shouldBe` V.fromList ["%a\\_b%"]

    it "escapes backslash" $
      Search.termsToIlikePatterns (Just "a\\b")
        `shouldBe` V.fromList ["%a\\\\b%"]

  describe "Service.Search.isAllSentinel" $ do
    it "is False for Nothing"          $ Search.isAllSentinel Nothing               `shouldBe` False
    it "is False for empty string"     $ Search.isAllSentinel (Just "")             `shouldBe` False
    it "is False for whitespace only"  $ Search.isAllSentinel (Just "   ")          `shouldBe` False
    it "is True for @all exact"        $ Search.isAllSentinel (Just "@all")         `shouldBe` True
    it "is True for @all with spaces"  $ Search.isAllSentinel (Just "  @all  ")     `shouldBe` True
    it "is True for @ALL (upper)"      $ Search.isAllSentinel (Just "@ALL")         `shouldBe` True
    it "is True for mixed case @All"   $ Search.isAllSentinel (Just "@All")         `shouldBe` True
    it "is False for @all with other terms" $
      Search.isAllSentinel (Just "@all foo")        `shouldBe` False
    it "is False for foo @all"         $ Search.isAllSentinel (Just "foo @all")     `shouldBe` False
    it "is False for @alll"            $ Search.isAllSentinel (Just "@alll")        `shouldBe` False
    it "is False for all (no @)"       $ Search.isAllSentinel (Just "all")          `shouldBe` False
