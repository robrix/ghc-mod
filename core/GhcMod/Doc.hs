{-# LANGUAGE CPP #-}
module GhcMod.Doc where

import DynFlags
import GHC
import GhcMod.Gap (withStyle, showDocWith)
import Outputable
import Pretty (Mode(..))

showPage :: DynFlags -> PprStyle -> SDoc -> String
showPage dflag style = showDocWith dflag PageMode . withStyle dflag style

showOneLine :: DynFlags -> PprStyle -> SDoc -> String
showOneLine dflag style = showDocWith dflag OneLineMode . withStyle dflag style

getStyle :: GhcMonad m => m PprStyle
getStyle = do
    unqual <- getPrintUnqual
#if __GLASGOW_HASKELL__ >= 802
    dflags <- getDynFlags
    return $ mkUserStyle dflags unqual AllTheWay
#else
    return $ mkUserStyle unqual AllTheWay
#endif

styleUnqualified :: DynFlags -> PprStyle
#if __GLASGOW_HASKELL__ >= 802
styleUnqualified dflags = mkUserStyle dflags neverQualify AllTheWay
#else
styleUnqualified _ = mkUserStyle neverQualify AllTheWay
#endif
