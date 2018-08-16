{-# OPTIONS_GHC -Wno-simplifiable-class-constraints #-}
{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE DerivingVia #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE FunctionalDependencies #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE InstanceSigs #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE MagicHash #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeInType #-}
{-# LANGUAGE UnboxedTuples #-}
{-# LANGUAGE UndecidableInstances #-}

module HasError
  ( HasThrow (..)
  , throw
  , HasCatch (..)
  , catch
  , catchJust
  , MonadError (..)
  , MonadThrow (..)
  , MonadCatch (..)
  , SafeExceptions (..)
  , MonadUnliftIO (..)
  , Tagged (..)
  , module Accessors
  , Exception (..)
  , Typeable
  ) where

import Control.Exception (Exception (..))
import qualified Control.Exception.Safe as Safe
import Control.Lens (preview, review)
import Control.Monad ((<=<))
import qualified Control.Monad.Catch as Catch
import qualified Control.Monad.Except as Except
import Control.Monad.IO.Class (MonadIO)
import qualified Control.Monad.IO.Unlift as UnliftIO
import Control.Monad.Primitive (PrimMonad)
import Control.Monad.Trans.Class (MonadTrans, lift)
import Control.Monad.Trans.Control (MonadTransControl (..))
import Data.Coerce (coerce)
import qualified Data.Generics.Sum.Constructors as Generic
import Data.Typeable (Typeable)
import GHC.Exts (Proxy#, proxy#)
import qualified UnliftIO.Exception as UnliftIO

import Accessors


class Monad m
  => HasThrow (tag :: k) (e :: *) (m :: * -> *) | tag m -> e
  where
    -- | Use 'throw' instead.
    throw_ :: Proxy# tag -> e -> m a

-- | Throw an exception.
throw :: forall tag e m a. HasThrow tag e m => e -> m a
throw = throw_ (proxy# @_ @tag)
{-# INLINE throw #-}


class HasThrow tag e m
  => HasCatch (tag :: k) (e :: *) (m :: * -> *) | tag m -> e
  where
    -- | Use 'catch' instead.
    catch_ :: Proxy# tag -> m a -> (e -> m a) -> m a
    -- | Use 'catchJust' instead.
    catchJust_ :: Proxy# tag -> (e -> Maybe b) -> m a -> (b -> m a) -> m a

-- | Provide a handler for exceptions thrown in the given action.
catch :: forall tag e m a. HasCatch tag e m => m a -> (e -> m a) -> m a
catch = catch_ (proxy# @_ @tag)
{-# INLINE catch #-}

-- | Like 'catch', but only handle the exception if the provided function
-- returns 'Just'.
catchJust :: forall tag e m a b. HasCatch tag e m
  => (e -> Maybe b) -> m a -> (b -> m a) -> m a
catchJust = catchJust_ (proxy# @_ @tag)
{-# INLINE catchJust #-}


-- XXX: Does it make sense to add a HasMask capability similar to @MonadMask@?
--   What would the meaning of the tag be?


newtype Tagged (tag :: k) (e :: *) = Tagged e
  deriving (Eq, Ord, Typeable, Show)
instance (Typeable k, Typeable tag, Exception e)
  => Exception (Tagged (tag :: k) e)


-- | Derive 'HasError from @m@'s 'Control.Monad.Except.MonadError' instance.
newtype MonadError m (a :: *) = MonadError (m a)
  deriving (Functor, Applicative, Monad, MonadIO, PrimMonad)
instance Except.MonadError (Tagged tag e) m
  => HasThrow tag e (MonadError m)
  where
    throw_ :: forall a. Proxy# tag -> e -> MonadError m a
    throw_ _ = coerce @(Tagged tag e -> m a) $ Except.throwError
    {-# INLINE throw_ #-}
instance Except.MonadError (Tagged tag e) m
  => HasCatch tag e (MonadError m)
  where
    catch_ :: forall a.
      Proxy# tag -> MonadError m a -> (e -> MonadError m a) -> MonadError m a
    catch_ _ = coerce @(m a -> (Tagged tag e -> m a) -> m a) $
      Except.catchError
    {-# INLINE catch_ #-}
    catchJust_ :: forall a b.
      Proxy# tag
      -> (e -> Maybe b)
      -> MonadError m a
      -> (b -> MonadError m a)
      -> MonadError m a
    catchJust_ tag f m h = catch_ tag m $ \e -> maybe (throw_ tag e) h $ f e
    {-# INLINE catchJust_ #-}


-- | Derive 'HasThrow' from @m@'s 'Control.Monad.Catch.MonadThrow' instance.
newtype MonadThrow (e :: *) m (a :: *) = MonadThrow (m a)
  deriving (Functor, Applicative, Monad, MonadIO, PrimMonad)
instance
  ( Typeable k, Typeable tag, Catch.Exception e, Catch.MonadThrow m )
  => HasThrow (tag :: k) e (MonadThrow e m)
  where
    throw_ :: forall a. Proxy# tag -> e -> MonadThrow e m a
    throw_ _ = coerce @(Tagged tag e -> m a) $ Catch.throwM
    {-# INLINE throw_ #-}


-- | Derive 'HasCatch from @m@'s 'Control.Monad.Catch.MonadCatch instance.
newtype MonadCatch (e :: *) m (a :: *) = MonadCatch (m a)
  deriving (Functor, Applicative, Monad, MonadIO, PrimMonad)
  deriving (HasThrow tag e) via MonadThrow e m
instance
  ( Typeable k, Typeable tag, Catch.Exception e, Catch.MonadCatch m )
  => HasCatch (tag :: k) e (MonadCatch e m)
  where
    catch_ :: forall a.
      Proxy# tag
      -> MonadCatch e m a
      -> (e -> MonadCatch e m a)
      -> MonadCatch e m a
    catch_ _ = coerce @(m a -> (Tagged tag e -> m a) -> m a) $
      Catch.catch
    {-# INLINE catch_ #-}
    catchJust_ :: forall a b.
      Proxy# tag
      -> (e -> Maybe b)
      -> MonadCatch e m a
      -> (b -> MonadCatch e m a)
      -> MonadCatch e m a
    catchJust_ _ =
      coerce @((Tagged tag e -> Maybe b) -> m a -> (b -> m a) -> m a) $
        Catch.catchJust
    {-# INLINE catchJust_ #-}


-- | Derive 'HasError' using the functionality from the @safe-exceptions@
-- package.
newtype SafeExceptions (e :: *) m (a :: *) = SafeExceptions (m a)
  deriving (Functor, Applicative, Monad, MonadIO, PrimMonad)
instance
  ( Typeable k, Typeable tag, Safe.Exception e, Safe.MonadThrow m )
  => HasThrow (tag :: k) e (SafeExceptions e m)
  where
    throw_ :: forall a. Proxy# tag -> e -> SafeExceptions e m a
    throw_ _ = coerce @(Tagged tag e -> m a) $ Safe.throw
    {-# INLINE throw_ #-}
instance
  ( Typeable k, Typeable tag, Safe.Exception e, Safe.MonadCatch m )
  => HasCatch (tag :: k) e (SafeExceptions e m)
  where
    catch_ :: forall a.
      Proxy# tag
      -> SafeExceptions e m a
      -> (e -> SafeExceptions e m a)
      -> SafeExceptions e m a
    catch_ _ = coerce @(m a -> (Tagged tag e -> m a) -> m a) $
      Safe.catch
    {-# INLINE catch_ #-}
    catchJust_ :: forall a b.
      Proxy# tag
      -> (e -> Maybe b)
      -> SafeExceptions e m a
      -> (b -> SafeExceptions e m a)
      -> SafeExceptions e m a
    catchJust_ _ =
      coerce @((Tagged tag e -> Maybe b) -> m a -> (b -> m a) -> m a) $
        Safe.catchJust
    {-# INLINE catchJust_ #-}


-- | Derive 'HasError' using the functionality from the @unliftio@ package.
newtype MonadUnliftIO (e :: *) m (a :: *) = MonadUnliftIO (m a)
  deriving (Functor, Applicative, Monad, MonadIO, PrimMonad)
instance
  ( Typeable k, Typeable tag, UnliftIO.Exception e, MonadIO m )
  => HasThrow (tag :: k) e (MonadUnliftIO e m)
  where
    throw_ :: forall a. Proxy# tag -> e -> MonadUnliftIO e m a
    throw_ _ = coerce @(e -> m a) $ UnliftIO.throwIO
    {-# INLINE throw_ #-}
instance
  ( Typeable k, Typeable tag, UnliftIO.Exception e, UnliftIO.MonadUnliftIO m )
  => HasCatch (tag :: k) e (MonadUnliftIO e m)
  where
    catch_ :: forall a.
      Proxy# tag
      -> MonadUnliftIO e m a
      -> (e -> MonadUnliftIO e m a)
      -> MonadUnliftIO e m a
    catch_ _ = coerce @(m a -> (Tagged tag e -> m a) -> m a) $
      UnliftIO.catch
    {-# INLINE catch_ #-}
    catchJust_ :: forall a b.
      Proxy# tag
      -> (e -> Maybe b)
      -> MonadUnliftIO e m a
      -> (b -> MonadUnliftIO e m a)
      -> MonadUnliftIO e m a
    catchJust_ _ =
      coerce @((Tagged tag e -> Maybe b) -> m a -> (b -> m a) -> m a) $
        UnliftIO.catchJust
    {-# INLINE catchJust_ #-}


-- | Wrap the exception @e@ with the constructor @ctor@ to throw an exception
-- of type @sum@.
instance
  -- The constraint raises @-Wsimplifiable-class-constraints@. This could
  -- be avoided by instead placing @AsConstructor'@s constraints here.
  -- Unfortunately, it uses non-exported symbols from @generic-lens@.
  (Generic.AsConstructor' ctor sum e, HasThrow tag sum m)
  => HasThrow tag e (Ctor ctor m)
  where
    throw_ :: forall a. Proxy# tag -> e -> Ctor ctor m a
    throw_ _ = coerce @(e -> m a) $
      throw @tag . review (Generic._Ctor' @ctor @sum)
    {-# INLINE throw_ #-}


-- | Catch an exception of type @sum@ if its constructor matches @ctor@.
instance
  -- The constraint raises @-Wsimplifiable-class-constraints@. This could
  -- be avoided by instead placing @AsConstructor'@s constraints here.
  -- Unfortunately, it uses non-exported symbols from @generic-lens@.
  (Generic.AsConstructor' ctor sum e, HasCatch tag sum m)
  => HasCatch tag e (Ctor ctor m)
  where
    catch_ :: forall a.
      Proxy# tag -> Ctor ctor m a -> (e -> Ctor ctor m a) -> Ctor ctor m a
    catch_ _ = coerce @(m a -> (e -> m a) -> m a) $
      catchJust @tag @sum $ preview (Generic._Ctor' @ctor @sum)
    {-# INLINE catch_ #-}
    catchJust_ :: forall a b.
      Proxy# tag
      -> (e -> Maybe b)
      -> Ctor ctor m a
      -> (b -> Ctor ctor m a)
      -> Ctor ctor m a
    catchJust_ _ = coerce @((e -> Maybe b) -> m a -> (b -> m a) -> m a) $ \f ->
      catchJust @tag @sum $ f <=< preview (Generic._Ctor' @ctor @sum)
    {-# INLINE catchJust_ #-}


instance
  ( HasThrow tag e m, MonadTrans t, Monad (t m) )
  => HasThrow tag e (Lift (t m))
  where
    throw_ :: forall a. Proxy# tag -> e -> Lift (t m) a
    throw_ tag = coerce @(e -> t m a) $ lift . throw_ tag
    {-# INLINE throw_ #-}


instance
  ( HasCatch tag e m, MonadTransControl t, Monad (t m) )
  => HasCatch tag e (Lift (t m))
  where
    catch_ :: forall a.
      Proxy# tag
      -> Lift (t m) a
      -> (e -> Lift (t m) a)
      -> Lift (t m) a
    catch_ tag = coerce @(t m a -> (e -> t m a) -> t m a) $ \m h ->
      liftWith (\run -> catch_ tag (run m) (run . h)) >>= restoreT . pure
    {-# INLINE catch_ #-}
    catchJust_ :: forall a b.
      Proxy# tag
      -> (e -> Maybe b)
      -> Lift (t m) a
      -> (b -> Lift (t m) a)
      -> Lift (t m) a
    catchJust_ tag =
      coerce @((e -> Maybe b) -> t m a -> (b -> t m a) -> t m a) $ \f m h ->
        liftWith (\run -> catchJust_ tag f (run m) (run . h)) >>= restoreT . pure
