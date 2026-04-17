module Main where

import Test.Hspec
import qualified Service.TagsSpec

main :: IO ()
main = hspec $ do
  describe "Service.Tags" Service.TagsSpec.spec
