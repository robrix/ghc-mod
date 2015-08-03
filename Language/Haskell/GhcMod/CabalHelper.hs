-- ghc-mod: Making Haskell development *more* fun
-- Copyright (C) 2015  Daniel Gröber <dxld ÄT darkboxed DOT org>
--
-- This program is free software: you can redistribute it and/or modify
-- it under the terms of the GNU Affero General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version.
--
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU Affero General Public License for more details.
--
-- You should have received a copy of the GNU Affero General Public License
-- along with this program.  If not, see <http://www.gnu.org/licenses/>.

{-# LANGUAGE CPP #-}
module Language.Haskell.GhcMod.CabalHelper (
    getComponents
  , getGhcMergedPkgOptions
  ) where

import Control.Applicative
import Control.Monad
import Data.Monoid
import Data.Version
import Data.Serialize (Serialize)
import Distribution.Helper
import qualified Language.Haskell.GhcMod.Types as T
import Language.Haskell.GhcMod.Types hiding (ghcProgram, ghcPkgProgram,
                                             cabalProgram)
import Language.Haskell.GhcMod.Monad.Types
import Language.Haskell.GhcMod.Utils
import Language.Haskell.GhcMod.World
import Language.Haskell.GhcMod.PathsAndFiles
import System.FilePath
import Prelude

import Paths_ghc_mod as GhcMod

-- | Only package related GHC options, sufficient for things that don't need to
-- access home modules
getGhcMergedPkgOptions :: (Applicative m, MonadIO m, GmEnv m, GmLog m)
                 => m [GHCOption]
getGhcMergedPkgOptions = chCached Cached {
  cacheFile = mergedPkgOptsCacheFile,
  cachedAction = \ _ (progs, root, _) _ -> do
    opts <- withCabal $ runQuery' progs root $ ghcMergedPkgOptions
    return ([setupConfigPath], opts)
 }

helperProgs :: Options -> Programs
helperProgs opts = Programs {
                            cabalProgram  = T.cabalProgram opts,
                            ghcProgram    = T.ghcProgram opts,
                            ghcPkgProgram = T.ghcPkgProgram opts
                          }

-- | Primary interface to cabal-helper and intended single entrypoint to
-- constructing 'GmComponent's
--
-- The Component\'s 'gmcHomeModuleGraph' will be empty and has to be resolved by
-- 'resolveGmComponents'.
getComponents :: (Applicative m, MonadIO m, GmEnv m, GmLog m)
              => m [GmComponent 'GMCRaw ChEntrypoint]
getComponents = chCached cabalHelperCache

chCached :: (Applicative m, MonadIO m, GmEnv m, GmLog m, Serialize a)
         => Cached m (Programs, FilePath, (Version, [Char])) a -> m a
chCached c = do
  root <- cradleRootDir <$> cradle
  d <- cacheInputData root
  withCabal $ cached root c d
 where
   cacheInputData root = do
               opt <- options
               return $ ( helperProgs opt
                        , root </> "dist"
                        , (gmVer, chVer)
                        )

   gmVer = GhcMod.version
   chVer = VERSION_cabal_helper

cabalHelperCache
  :: (Functor m, Applicative m, MonadIO m)
  => Cached m (Programs, FilePath, (Version, String)) [GmComponent 'GMCRaw ChEntrypoint]
cabalHelperCache = Cached {
    cacheFile = cabalHelperCacheFile,
    cachedAction = \ _ (progs, root, _) _ ->
      runQuery' progs root $ do
        q <- join7
               <$> ghcOptions
               <*> ghcPkgOptions
               <*> ghcSrcOptions
               <*> ghcLangOptions
               <*> entrypoints
               <*> entrypoints
               <*> sourceDirs
        let cs = flip map q $ curry8 (GmComponent mempty)
        return ([setupConfigPath], cs)
  }
 where
   curry8 fn (a, (b, (c, (d, (e, (f, (g, h))))))) = fn a b c d e f g h

   join7 a b c d e f = join' a . join' b . join' c . join' d . join' e . join' f
   join' :: Eq a => [(a,b)] -> [(a,c)] -> [(a,(b,c))]
   join' lb lc = [ (a, (b, c))
                 | (a, b)  <- lb
                 , (a', c) <- lc
                 , a == a'
                 ]

withCabal :: (MonadIO m, GmEnv m) => m a -> m a
withCabal action = do
    crdl <- cradle
    opts <- options
    liftIO $ whenM (isSetupConfigOutOfDate <$> getCurrentWorld crdl) $
        withDirectory_ (cradleRootDir crdl) $ do
            let pkgDbArgs = "--package-db=clear" : map pkgDbArg (cradlePkgDbStack crdl)
                progOpts =
                    [ "--with-ghc=" ++ T.ghcProgram opts ]
                    -- Only pass ghc-pkg if it was actually set otherwise we
                    -- might break cabal's guessing logic
                    ++ if T.ghcPkgProgram opts /= T.ghcPkgProgram defaultOptions
                         then [ "--with-ghc-pkg=" ++ T.ghcPkgProgram opts ]
                         else []
                    ++ pkgDbArgs
            void $ readProcess (T.cabalProgram opts) ("configure":progOpts) ""
            writeAutogenFiles $ cradleRootDir crdl </> "dist"
    action

pkgDbArg :: GhcPkgDb -> String
pkgDbArg GlobalDb      = "--package-db=global"
pkgDbArg UserDb        = "--package-db=user"
pkgDbArg (PackageDb p) = "--package-db=" ++ p
