module HasReader
  ( HasReader (..)
  , ask
  , asks
  , local
  , reader
  , magnify
  , MonadReader (..)
  , ReadStatePure (..)
  , ReadState (..)
  , module Accessors
  ) where

import Accessors
import HasReader.Internal.Class
import HasReader.Internal.Instances
