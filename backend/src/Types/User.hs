module Types.User (User(..)) where

import Data.Text (Text)
import Data.Time (UTCTime)
import Types.Common (UserId)

data User = User
  { usrId         :: UserId
  , usrEmail      :: Text
  , usrPwHash     :: Text
  , usrCreatedAt  :: UTCTime
  } deriving (Show, Eq)
