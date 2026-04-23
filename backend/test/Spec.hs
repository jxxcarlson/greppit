module Main where

import Test.Hspec
import qualified Service.TagsSpec
import qualified Service.SearchSpec
import qualified Service.AuthSpec
import qualified Service.IdentifiersSpec

main :: IO ()
main = hspec $ do
  describe "Service.Tags"         Service.TagsSpec.spec
  describe "Service.Search"       Service.SearchSpec.spec
  describe "Service.Auth"         Service.AuthSpec.spec
  describe "Service.Identifiers"  Service.IdentifiersSpec.spec
