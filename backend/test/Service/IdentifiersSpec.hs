{-# LANGUAGE OverloadedStrings #-}

module Service.IdentifiersSpec (spec) where

import Test.Hspec
import Data.Time (UTCTime(..), fromGregorian, TimeOfDay(..), timeOfDayToTime)

import Service.Identifiers (sanitizeUsername, formatZkuTimestamp)

spec :: Spec
spec = do
  describe "sanitizeUsername" $ do
    it "passes through a clean lowercase local-part" $
      sanitizeUsername "jxxcarlson" `shouldBe` Just "jxxcarlson"
    it "strips dots, plus-tag, and mixed case" $
      sanitizeUsername "J.Smith+tag" `shouldBe` Just "jsmithtag"
    it "preserves digits" $
      sanitizeUsername "user123" `shouldBe` Just "user123"
    it "preserves digit-only input" $
      sanitizeUsername "12345" `shouldBe` Just "12345"
    it "strips non-ASCII letters, keeps ASCII letters around them" $
      sanitizeUsername "jörg" `shouldBe` Just "jrg"
    it "returns Nothing for empty input" $
      sanitizeUsername "" `shouldBe` Nothing
    it "returns Nothing for whitespace-only input" $
      sanitizeUsername "   " `shouldBe` Nothing
    it "returns Nothing for symbol-only input" $
      sanitizeUsername "!!!" `shouldBe` Nothing

  describe "formatZkuTimestamp" $ do
    it "formats a UTCTime as 14-digit YYYYMMDDHHMMSS" $
      let t = UTCTime (fromGregorian 2026 4 23)
                      (timeOfDayToTime (TimeOfDay 14 30 22))
      in formatZkuTimestamp t `shouldBe` "20260423143022"
    it "zero-pads single-digit months and hours" $
      let t = UTCTime (fromGregorian 2026 1 5)
                      (timeOfDayToTime (TimeOfDay 7 3 9))
      in formatZkuTimestamp t `shouldBe` "20260105070309"
    it "truncates fractional seconds (no rounding, no decimal point)" $
      let t = UTCTime (fromGregorian 2026 4 23)
                      (timeOfDayToTime (TimeOfDay 14 30 22.9999))
      in formatZkuTimestamp t `shouldBe` "20260423143022"
