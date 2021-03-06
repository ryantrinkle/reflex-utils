{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE FunctionalDependencies #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE TypeOperators #-}
module Reflex.Dom.Contrib.Layout.Types where

import Control.Lens (makeLenses,makeClassy)
import qualified Reflex as R
import Reflex.Dom ((=:))
import qualified Data.Map as M
import qualified GHCJS.DOM.Element as E
import Control.Monad.State (StateT)
import Control.Monad.Reader (ReaderT)

--import Data.Default (Default(..))

class IsCssClass a where
  toCssString::a->String

toStaticAttributes::IsCssClass a=>a->M.Map String String
toStaticAttributes x = ("class" =: toCssString x)

data CssClass = CssClass String deriving (Show,Ord,Eq)
instance IsCssClass CssClass where
  toCssString (CssClass c) = c

data CssClasses = CssClasses [CssClass] deriving (Show,Ord,Eq)
instance IsCssClass CssClasses where
  toCssString (CssClasses cs) = unwords $ toCssString <$> cs

instance Monoid CssClasses where
  mempty = CssClasses []
  (CssClasses a) `mappend` (CssClasses b) = CssClasses (a `mappend` b) 

emptyCss::CssClasses
emptyCss = CssClasses []


type CssGridRowClass = CssClass
type CssColumnClasses = CssClasses
type GridColWidth = Int

data CssGridConfig = CssGridConfig { _gcGridRow::CssClass, _gcGridColumns::CssClasses } deriving (Show)

type LayoutClassKey = String
type LayoutClassMap = M.Map LayoutClassKey CssClasses
data LayoutClassDynamic t = LayoutClassDynamic { _lcdInitDyn::R.Dynamic t CssClasses, _lcdEvent::R.Event t CssUpdate }
type LayoutClassDynamicMap t = M.Map LayoutClassKey (LayoutClassDynamic t)

data LayoutConfig t = LayoutConfig { _lcGridConfig::CssGridConfig, _lcStaticCssMap::LayoutClassMap, _lcDynamicCssMap::LayoutClassDynamicMap t }

data CssUpdate = UpdateDynamic CssClasses | AddToDynamic CssClasses deriving (Eq,Show)


data LayoutPropertyKey = LPK_Width deriving (Ord,Eq,Show)
data LayoutProperty = LP_Width { lpWidth::Int } deriving (Show)
type LayoutPropertyMap = M.Map LayoutPropertyKey LayoutProperty



type LayoutF t = LayoutConfig t->LayoutTree t->LayoutTree t

data LayoutDescription t = LayoutDescription { _ldLayoutF::LayoutF t
                                             , _ldProperties::LayoutPropertyMap
                                             , _ldLayoutClassKeys::[LayoutClassKey]
                                             } 


data LayoutInfo t = LayoutInfo { _liDescription::LayoutDescription t
                               , _liNewClasses::CssClasses
                               , _liDynamicCss::Maybe (R.Dynamic t CssClasses)
                               , _liElt::Maybe E.Element
                               } 


data LayoutTree t = LayoutNode { _lnInfo::LayoutInfo t, _lnChildren::[LayoutTree t]} --Rose Tree


data LayoutS t = LayoutS {  _lsTree::LayoutTree t
                          , _lsClassMap::LayoutClassMap
                          , _lsDynamicCssMap::LayoutClassDynamicMap t
                         }


type LayoutM t m = StateT (LayoutS t) (ReaderT (LayoutConfig t) m)


makeClassy ''CssGridConfig
makeClassy ''LayoutConfig
makeClassy ''LayoutClassDynamic
makeClassy ''LayoutDescription
makeClassy ''LayoutInfo
makeClassy ''LayoutTree
makeClassy ''LayoutS


