{-# LANGUAGE UndecidableInstances #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE ExistentialQuantification #-}
{-# LANGUAGE ViewPatterns #-}
{-# LANGUAGE CPP #-}

{-# OPTIONS_GHC -Wall #-}
{-# OPTIONS_GHC -fno-warn-unused-imports #-}  -- TEMP

-- | Linear maps as constrained category

module LMap where

import Prelude hiding (id,(.))

import Data.Constraint

import Data.MemoTrie      (HasTrie(..),(:->:))
import Data.AdditiveGroup (Sum(..), AdditiveGroup(..))

import ConCat
import Ring
import Basis

class    (Ring u, Scalar u ~ s, HasBasis u, HasTrie (Basis u)) => OkL s u
instance (Ring u, Scalar u ~ s, HasBasis u, HasTrie (Basis u)) => OkL s u

type LMap' u v = Basis u :->: v

-- | Linear map, represented as an optional memo-trie from basis to
-- values
data LMap s u v = (OkL s u, OkL s v) => LMap { unLMap :: LMap' u v }

-- scale1 :: LMap s s s
-- scale1 = LMap (trie id)

-- The OkL constraints on u & v allow okay to work.

-- deriving instance (HasTrie (Basis u), AdditiveGroup v) => AdditiveGroup (u :-* v)

-- instance (HasTrie (Basis u), OkL v) =>
--          OkL (u :-* v) where
--   type Scalar (u :-* v) = Scalar v
--   (*^) s = fmap (s *^)

-- | Function (assumed linear) as linear map.
linear :: (OkL s u, OkL s v) => (u -> v) -> LMap s u v
linear f = LMap (trie (f . basisValue))

-- | Apply a linear map to a vector.
lapply :: (OkL s u, OkL s v) =>
          LMap s u v -> (u -> v)
lapply (LMap tr) = linearCombo . fmap (first (untrie tr)) . decompose

-- | Compose linear maps
(*.*) :: (OkL s v, OkL s w) =>
         LMap s v w -> LMap s u v -> LMap s u w
vw *.* LMap uv = LMap (trie (lapply vw . untrie uv))


{--------------------------------------------------------------------
    Category instances
--------------------------------------------------------------------}

#define OKAY OD Dict
#define OKAY2 (OKAY,OKAY)

#define OK (okay -> OKAY2)

instance Category (LMap s) where
  type Ok (LMap s) = OkL s
  okay (LMap _) = OKAY2
  id = linear id   
  vw@OK . uv@OK = vw *.* uv

--   vw@OK . uv@OK = LMap (trie (lapply vw . untrie (unLMap uv)))

-- Oh!! Can I move @OK into (.) and all other methods that take arrows?
