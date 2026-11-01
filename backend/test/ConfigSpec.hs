module ConfigSpec (spec) where

import Data.Either (isLeft)
import Test.Hspec
import Config (validateJwtSecret)

spec :: Spec
spec = describe "Config.validateJwtSecret" $ do
  it "rejects a missing secret" $
    validateJwtSecret Nothing `shouldSatisfy` isLeft

  it "rejects the published default" $
    validateJwtSecret (Just "dev-secret-change-in-production-min-32-chars!!") `shouldSatisfy` isLeft

  it "rejects a secret shorter than 32 bytes" $
    validateJwtSecret (Just (replicate 31 'x')) `shouldSatisfy` isLeft

  it "accepts a 32-byte secret" $
    validateJwtSecret (Just (replicate 32 'x')) `shouldBe` Right (replicate 32 'x')

  it "counts bytes, not characters" $
    -- 16 two-byte characters = 32 bytes
    validateJwtSecret (Just (replicate 16 'é')) `shouldSatisfy` (not . isLeft)
