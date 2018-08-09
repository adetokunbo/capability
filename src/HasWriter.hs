{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DerivingVia #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE FunctionalDependencies #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE InstanceSigs #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE MagicHash #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE PolyKinds #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE UndecidableInstances #-}

module HasWriter
  ( HasWriter (..)
  , writer
  , tell
  , listen
  , pass
  , WriterLog (..)
  ) where

import Control.Monad.IO.Class (MonadIO)
import Data.Coerce (coerce)
import GHC.Exts (Proxy#, proxy#)

import HasState


class (Monoid w, Monad m)
  => HasWriter (tag :: k) (w :: *) (m :: * -> *) | tag m -> w
  where
    writer_ :: Proxy# tag -> (a, w) -> m a
    tell_ :: Proxy# tag -> w -> m ()
    listen_ :: Proxy# tag -> m a -> m (a, w)
    pass_ :: Proxy# tag -> m (a, w -> w) -> m a

writer :: forall tag w m a. HasWriter tag w m => (a, w) -> m a
writer = writer_ (proxy# @_ @tag)

tell :: forall tag w m. HasWriter tag w m => w -> m ()
tell = tell_ (proxy# @_ @tag)

listen :: forall tag w m a. HasWriter tag w m => m a -> m (a, w)
listen = listen_ (proxy# @_ @tag)

pass :: forall tag w m a. HasWriter tag w m => m (a, w -> w) -> m a
pass = pass_ (proxy# @_ @tag)


newtype WriterLog m a = WriterLog (m a)
  deriving (Functor, Applicative, Monad, MonadIO)
instance (Monoid w, HasState tag w m)
  => HasWriter tag w (WriterLog m)
  where
    writer_ :: forall a. Proxy# tag -> (a, w) -> WriterLog m a
    writer_ _ (a, w) = coerce @(m a) $ modify' @tag (<> w) >> pure a
    tell_ _ w = coerce @(m ()) $ modify' @tag (<> w)
    listen_ :: forall a. Proxy# tag -> WriterLog m a -> WriterLog m (a, w)
    listen_ _ m = coerce @(m (a, w)) $ do
      w0 <- get @tag
      put @tag mempty
      a <- coerce m
      w <- get @tag
      put @tag $! w0 <> w
      pure (a, w)
    pass_ :: forall a. Proxy# tag -> WriterLog m (a, w -> w) -> WriterLog m a
    pass_ _ m = coerce @(m a) $ do
      w0 <- get @tag
      put @tag mempty
      (a, f) <- coerce @_ @(m (a, w -> w)) m
      w <- get @tag
      put @tag $! w0 <> f w
      pure a
