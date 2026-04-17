module Main where

import Config (loadConfig)

main :: IO ()
main = do
  cfg <- loadConfig
  putStrLn $ "greppit backend: loaded config with port=" <> show cfg
