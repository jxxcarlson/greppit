module Main where

import Test.Hspec
import qualified Service.TagsSpec
import qualified Service.SearchSpec

main :: IO ()
main = hspec $ do
  describe "Service.Tags"   Service.TagsSpec.spec
  describe "Service.Search" Service.SearchSpec.spec
