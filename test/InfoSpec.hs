module InfoSpec where

import Cradle
import Expectation
import Info
import Test.Hspec
import Types

spec :: Spec
spec = do
    describe "typeExpr" $ do
        it "shows types of the expression and its outers" $ do
            withDirectory "test/data/ghc-mod-check" $ do
                cradle <- findCradle Nothing
                res <- typeExpr defaultOptions cradle "Data.Foo" 9 5 "Data/Foo.hs"
                res `shouldBe` "9 5 11 40 \"Int -> a -> a -> a\"\n7 1 11 40 \"Int -> Integer\"\n"
