{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE RecursiveDo #-}
module Reflex.Dom.Contrib.SimpleForm.Instances.Containers () where

import Control.Monad (join)
import Control.Monad.Reader (ReaderT, lift)
import Control.Monad.State (StateT, runStateT, modify, get, put)
import Control.Monad.Morph (hoist)

-- reflex imports
import qualified Reflex as R 
import qualified Reflex.Dom as RD
import Reflex.Dynamic.TH (mkDyn)

-- imports only to make instances
import qualified Data.List as L
import qualified Data.Map as M
import qualified Data.IntMap as IM
import qualified Data.Sequence as Seq
import qualified Data.Set as S
import Data.Hashable (Hashable)
import qualified Data.HashMap.Lazy as HML
import qualified Data.HashSet as HS

-- my libs
import qualified DataBuilder as B

-- From this lib
import Reflex.Dom.Contrib.Layout.Types (LayoutM,CssClasses,IsCssClass(..))
import Reflex.Dom.Contrib.Layout.Core() --for LayoutM instances

-- All the basic (primitive types, tuples, etc.) are in here
import Reflex.Dom.Contrib.SimpleForm.Instances.Basic()

import Reflex.Dom.Contrib.SimpleForm.Builder

-- Container instances
-- Editing/Appendability requires that the container be isomorphic to something traversable, but traversable in the (key,value) pairs for maps.
-- and the ability to make an empty traversable and insert new items/pairs.
-- Deletability requires some way of knowing which element to delete *in the traversable container rather than the original*.
-- If this uses an index, it might require some state as the traversable container is rendered.

-- I'd prefer these as classes but I can't make all the types work.  I end up with open type families and injectivity issues.
-- So, instead, I carry the dictionaries around as arguments.  That works too.  
data SFAppendableI (fa :: * ) (g :: * -> *) (b :: *) = SFAppendableI
  {
    toT::fa -> g b
  , fromT::g b -> fa
  , emptyT::g b
  , insertB::b->fa->fa
  , sizeFa::fa->Int
  }

data SFDeletableI (g :: * -> *) (b :: *) (k :: *) (s :: *) = SFDeletableI
  {
    getKey::b -> s -> k
  , initialS::s
  , updateS::s->s
  , delete::k -> g b -> g b
  }

-- This helps insure the types in Appendable and Deletable line up for any particular instance
data SFAdjustableI fa g b k s= SFAdjustableI { sfAI::SFAppendableI fa g b, sfDI::SFDeletableI g b k s }


buildAdjustableContainer::(SimpleFormC e t m,B.Builder (SimpleFormR e t m) b,Traversable g)
                          =>SFAdjustableI fa g b k s->Maybe FieldName->Maybe fa->SimpleFormR e t m fa
buildAdjustableContainer sfAdj mFN = SimpleFormR . buildSFContainer (sfAI sfAdj) (buildDeletable (sfDI sfAdj)) mFN


listAppend::a->[a]->[a]
listAppend a as = as ++ [a]

listDeleteAt::Int->[a]->[a]
listDeleteAt n as = take n as ++ drop (n+1) as

listSFA::SFAppendableI [a] [] a
listSFA = SFAppendableI id id [] listAppend L.length

listSFD::SFDeletableI [] a Int Int
listSFD = SFDeletableI (\_ n->n) 0 (+1) listDeleteAt

instance (SimpleFormC e t m,B.Builder (SimpleFormR e t m) a)=>B.Builder (SimpleFormR e t m) [a] where
  buildA = buildAdjustableContainer (SFAdjustableI listSFA listSFD)


mapSFA::Ord k=>SFAppendableI (M.Map k v) (M.Map k) (k,v)
mapSFA = SFAppendableI (M.mapWithKey (\k v->(k,v))) (\m->M.fromList $ snd <$> M.toList m) mempty (\(k,x) m->M.insert k x m) M.size

mapSFD::Ord k=>SFDeletableI (M.Map k) (k,v) k ()
mapSFD = SFDeletableI (\(k,_) _ ->k) () id M.delete

instance (SimpleFormC e t m,
          B.Builder  (SimpleFormR e t m)  k, Ord k,
          B.Builder  (SimpleFormR e t m)  a)
         =>B.Builder (SimpleFormR e t m) (M.Map k a) where
  buildA = buildAdjustableContainer (SFAdjustableI mapSFA mapSFD)

intMapSFA::SFAppendableI (IM.IntMap v) IM.IntMap (IM.Key,v)
intMapSFA = SFAppendableI (IM.mapWithKey (\k v->(k,v))) (\m->IM.fromList $ snd <$> IM.toList m) mempty (\(k,x) m->IM.insert k x m) IM.size

intMapSFD::SFDeletableI IM.IntMap (IM.Key,v) IM.Key ()
intMapSFD = SFDeletableI (\(k,_) _ ->k) () id IM.delete

instance (SimpleFormC e t m,
          B.Builder  (SimpleFormR e t m)  IM.Key,
          B.Builder  (SimpleFormR e t m)  a)
         =>B.Builder (SimpleFormR e t m) (IM.IntMap a) where
  buildA = buildAdjustableContainer (SFAdjustableI intMapSFA intMapSFD)

seqSFA::SFAppendableI (Seq.Seq a) Seq.Seq a
seqSFA = SFAppendableI id id Seq.empty (flip (Seq.|>)) Seq.length

seqSFD::SFDeletableI Seq.Seq a Int Int
seqSFD = SFDeletableI (\_ index->index) 0 (+1) (\n bs -> Seq.take n bs Seq.>< Seq.drop (n+1) bs)

instance (SimpleFormC e t m,B.Builder (SimpleFormR e t m) a)=>B.Builder (SimpleFormR e t m) (Seq.Seq a) where
  buildA = buildAdjustableContainer (SFAdjustableI seqSFA seqSFD)

-- we transform to a map since Set is not Traversable and we want map-like semantics on the as. We could fix this with lens Traversables maybe?
setSFA::Ord a=>SFAppendableI (S.Set a) (M.Map a) a
setSFA = SFAppendableI (\s ->M.fromList $ (\x->(x,x)) <$> S.toList s) (\m->S.fromList $ snd <$> M.toList m) M.empty (\x s->S.insert x s) S.size

setSFD::Ord a=>SFDeletableI (M.Map a) a a ()
setSFD = SFDeletableI (\a _ -> a) () id M.delete

instance (SimpleFormC e t m, B.Builder (SimpleFormR e t m) a,Ord a)=>B.Builder (SimpleFormR e t m) (S.Set a) where
  buildA = buildAdjustableContainer (SFAdjustableI setSFA setSFD)

hashMapSFA::(Eq k,Hashable k)=>SFAppendableI (HML.HashMap k v) (HML.HashMap k) (k,v)
hashMapSFA = SFAppendableI (HML.mapWithKey (\k v->(k,v))) (\m->HML.fromList $ snd <$> HML.toList m) mempty (\(k,x) m->HML.insert k x m) HML.size

hashMapSFD::(Eq k, Hashable k)=>SFDeletableI (HML.HashMap k) (k,v) k ()
hashMapSFD = SFDeletableI (\(k,_) _ ->k) () id HML.delete


instance (SimpleFormC e t m,
          B.Builder  (SimpleFormR e t m)  k, Eq k, Hashable k,
          B.Builder  (SimpleFormR e t m)  v)
         =>B.Builder (SimpleFormR e t m) (HML.HashMap k v) where
  buildA = buildAdjustableContainer (SFAdjustableI hashMapSFA hashMapSFD)


-- we transform to a HashMap since Set is not Traversable and we want map-like semantics on the as. We could fix this with lens Traversables maybe?
hashSetSFA::(Eq a,Hashable a)=>SFAppendableI (HS.HashSet a) (HML.HashMap a) a
hashSetSFA = SFAppendableI (\hs ->HML.fromList $ (\x->(x,x)) <$> HS.toList hs) (\hm->HS.fromList $ snd <$> HML.toList hm) HML.empty (\x hs->HS.insert x hs) HS.size

hashSetSFD::(Eq a, Hashable a)=>SFDeletableI (HML.HashMap a) a a ()
hashSetSFD = SFDeletableI (\a _ -> a) () id HML.delete

instance (SimpleFormC e t m,
          B.Builder  (SimpleFormR e t m)  a, Eq a, Hashable a)
         =>B.Builder (SimpleFormR e t m) (HS.HashSet a) where
  buildA = buildAdjustableContainer (SFAdjustableI hashSetSFA hashSetSFD)


-- the various container builder components
type BuildF e t m a = Maybe FieldName->Maybe a->SFRW e t m a

-- This feels like a lot of machinery just to get removables...but it does work...
newtype SSFR s e t m a = SSFR { unSSFR::StateT s (ReaderT e m) (DynMaybe t a) }

instance (R.Reflex t, R.MonadHold t m)=>Functor (SSFR s e t m) where
  fmap f ssfra = SSFR $ (unSSFR ssfra) >>= lift . lift . R.mapDyn (fmap f) 

instance (R.Reflex t, R.MonadHold t m)=>Applicative (SSFR s e t m) where
  pure x = SSFR $ return (R.constDyn (Just x))
  ssfrF <*> ssfrA = SSFR $ do
    dmF <- unSSFR ssfrF
    dmA <- unSSFR ssfrA
    lift . lift $ R.combineDyn (<*>) dmF dmA

liftLF'::Monad m=>(forall b.m b->m b)->StateT s m a -> StateT s m a
liftLF' = hoist 


-- unstyled, for use within other instances which will deal with the styling.
buildTraversableSFA'::(SimpleFormC e t m,B.Builder (SimpleFormR e t m) b,Traversable g)=>SFAppendableI fa g b->BuildF e t m b->BuildF e t m fa
buildTraversableSFA' cI buildOne md mfa =
  case mfa of
    Just fa -> unSF $ fromT cI <$> traverse (liftF formRow . SimpleFormR . buildOne Nothing . Just) (toT cI $ fa)
    Nothing -> return $ R.constDyn Nothing

-- styled, in case we ever want an editable container without add/remove
buildTraversableSFA::(SimpleFormC e t m,B.Builder (SimpleFormR e t m) b,Traversable g)=>SFAppendableI fa g b->BuildF e t m fa 
buildTraversableSFA aI md mfa = do
  validClasses <- validItemStyle
  formCol' (R.constDyn $ cssClassAttr validClasses) $ buildTraversableSFA' aI (\x -> unSF . B.buildA x) md mfa

buildSFContainer::(SimpleFormC e t m,B.Builder (SimpleFormR e t m) b,Traversable g)=>SFAppendableI fa g b->BuildF e t m (g b)->BuildF e t m fa
buildSFContainer aI buildTr mFN mfa = do
  validClasses <- validItemStyle
  invalidClasses <- invalidItemStyle
  buttonClasses <- buttonStyle
  mdo
    attrsDyn <- sfAttrs dmfa mFN Nothing
    let initial = maybe (Just $ emptyT aI) (Just . (toT aI)) mfa 
    dmfa <- formCol' attrsDyn $ mdo
      dmfa' <- unSF $ (fromT aI) <$> (SimpleFormR $ R.joinDyn <$> RD.widgetHold (buildTr mFN initial) (R.leftmost [newSFREv,resizedEv]))
      sizemDyn <- R.mapDyn (\mfa -> (sizeFa aI) <$> mfa) dmfa'
      let resizedEv = R.attachDynWithMaybe (\mfa ms -> maybe Nothing (const $ buildTr mFN . Just . (toT aI) <$> mfa) ms) dmfa' (R.updated $ R.nubDyn sizemDyn)
      addEv <- formRow $ do
        let emptyB = unSF $ B.buildA Nothing Nothing -- we don't pass the fieldname here since it's the name of the parent 
        dmb <- itemL $ RD.joinDyn <$> RD.widgetHold (emptyB) (fmap (const emptyB) $ R.updated dmfa')
        clickEv <-  itemR . lift $ buttonClass "+" (toCssString buttonClasses)-- need attributes for styling??
        return $ R.attachDynWithMaybe (\mb _ -> mb) dmb clickEv -- only fires if button is clicked when mb is a Just.
      let insert mfa b = (insertB aI) <$> (Just b) <*> mfa 
          newFaEv = R.attachDynWithMaybe insert dmfa' addEv -- Event t (tr a), only fires if traverable is not Nothing
          newSFREv = fmap (buildTr mFN . Just . (toT aI)) newFaEv -- Event t (SFRW e t m (g b))
      return dmfa'
    return dmfa
--    lift $ R.mapDyn (\ml -> (fromT aI) <$> ml) dmla


buildOneDeletable::(SimpleFormC e t m, B.Builder (SimpleFormR e t m) b)
                   =>SFDeletableI g b k s->Maybe FieldName->Maybe b->StateT ([R.Event t k],s) (ReaderT e m) (DynMaybe t b)
buildOneDeletable dI mFN ma = liftLF' formRow $ do
    (evs,curS) <- get
    buttonClasses <- lift buttonStyle
    dma <- lift . itemL . unSF $ B.buildA mFN ma
    ev  <- lift . itemR . lift $ buttonClass "x" (toCssString buttonClasses)
    let ev' = R.attachDynWithMaybe (\ma _ -> (getKey dI) <$> ma <*> (Just curS)) dma ev
    put ((ev':evs),(updateS dI) curS)
    return dma


buildDeletable::(SimpleFormC e t m, B.Builder (SimpleFormR e t m) b, Traversable g)=>SFDeletableI g b k s->BuildF e t m (g b)
buildDeletable dI mFN mgb = 
  case mgb of
    Nothing -> return $ R.constDyn Nothing
    Just gb -> mdo
      let f gb = do
            (dmgb',(evs,_)) <- runStateT (unSSFR $ traverse (SSFR . liftLF' formRow  . buildOneDeletable dI Nothing . Just) gb) ([],(initialS dI))
            return $ (dmgb',(R.leftmost evs))
      (ddmgb,dEv) <- join $ R.splitDyn <$> RD.widgetHold (f gb) (f <$> newgbEv)
      let dmgb = R.joinDyn ddmgb
          newgbEv = R.attachDynWithMaybe (\mgb key-> (delete dI) key <$> mgb) dmgb (R.switchPromptlyDyn dEv)
      return dmgb

{- This fails with ambiguous types, because TR and E are not injective.  Why doesn't ScopedTypeVariables help?
class SFAppendable fa where
  type Tr fa :: * -> *
  type E fa :: *
  toT'::fa -> Tr fa (E fa)
  fromT'::Tr fa (E fa) -> fa 
  emptyT' :: Tr fa (E fa)
  insertT' :: E fa -> Tr fa (E fa) -> Tr fa (E fa)

buildSFContainer'::(SimpleFormC e t m, SFAppendable fa, B.Builder (SimpleFormR e t m) (E fa), Traversable (Tr fa))
                   =>BuildF e t m (Tr fa (E fa))->BuildF e t m fa
buildSFContainer' buildTr md mfa = do
  validClasses <- validItemStyle
  invalidClasses <- invalidItemStyle
  buttonClasses <- buttonStyle
  mdo
    attrsDyn <- sfAttrs dmla md Nothing
    let initial::Maybe (Tr fa (E fa)) 
        initial = maybe (Just emptyT') (Just . toT') mfa 
    dmla <- formCol' attrsDyn $ mdo
      dmla' <- R.joinDyn <$> RD.widgetHold (buildTr md initial) newSFREv -- SFRW e t m (Dynamic t (g b))
      addEv <- formRow $ do
        let emptyA = unSF $ B.buildA md Nothing 
        dma <- itemL $ RD.joinDyn <$> RD.widgetHold (emptyA) (fmap (const emptyA) $ R.updated dmla')
        clickEv <-  itemR . lift $ buttonClass "+" (toCssString buttonClasses)-- need attributes for styling??
        return $ R.attachDynWithMaybe (\ma _ -> ma) dma clickEv -- only fires if button is clicked when a is a Just.
      let insert::Maybe (Tr fa (E fa))->Maybe (E fa)->Maybe (Tr fa (E fa))
          insert maa a = insertT' <$> (Just a) <*> maa 
          newTrEv = R.attachDynWithMaybe insert dmla' addEv -- Event t (tr a), only fires if traverable is not Nothing
          newSFREv = fmap (buildTr md . Just) newTrEv -- Event t (SFRW e t m (g b)))
      return dmla'
    lift $ R.mapDyn (\ml -> fromT' <$> ml) dmla
-}
