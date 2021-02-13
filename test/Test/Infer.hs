module Test.Infer
  ( spec,
  )
where

import Mlatu (fragmentFromSource)
import Mlatu.Dictionary qualified as Dictionary
import Mlatu.Enter qualified as Enter
import Mlatu.Entry qualified as Entry
import Mlatu.Informer (checkpoint)
import Mlatu.InstanceCheck (instanceCheck)
import Mlatu.Instantiated (Instantiated (Instantiated))
import Mlatu.Kind (Kind (..))
import Mlatu.Monad (runMlatu)
import Mlatu.Name (GeneralName (..), Qualified (..))
import Mlatu.Origin qualified as Origin
import Mlatu.Report qualified as Report
import Mlatu.Term qualified as Term
import Mlatu.Type (Type (..), TypeId (..), Var (..))
import Mlatu.Type qualified as Type
import Mlatu.Vocabulary qualified as Vocabulary
import Relude hiding (Type)
import Test.Common (Sign (..))
import Test.HUnit (assertBool, assertFailure)
import Test.Hspec (Spec, describe, it)
import Text.PrettyPrint qualified as Pretty
import Text.PrettyPrint.HughesPJClass (Pretty (..))

spec :: Spec
spec = do
  describe "with trivial programs" $ do
    it "typechecks empty program" $ do
      testTypecheck
        Positive
        "define test (->) {}"
        $ Type.fun o r r e

    it "typechecks single literals" $ do
      testTypecheck
        Positive
        "define test (-> Int32) { 0 }"
        $ Type.fun o r (Type.prod o r int) e

      testTypecheck
        Positive
        "define test (-> Float64) { 1.0 }"
        $ Type.fun o r (Type.prod o r float) e

    it "typechecks compound literals" $ do
      testTypecheck
        Positive
        "type Pair[A, B] { case pair (A, B) }\n\
        \define => [K, V] (K, V -> Pair[K, V]) { pair }\n\
        \about => { operator { right 1 } }\n\
        \define test (-> List[Pair[Int32, Int32]]) { [1 => 1, 2 => 2, 3 => 3] }"
        $ Type.fun o r (Type.prod o r (ctor "List" :@ (ctor "Pair" :@ int :@ int))) e

    it "typechecks intrinsics" $ do
      testTypecheck
        Positive
        "define test [R..., S..., +P] (R... -> S... +P) { _::mlatu::magic }"
        $ Type.fun o r s e

      testTypecheck
        Positive
        "define test (-> Int32) { 1 2 _::mlatu::add_int }"
        $ Type.fun o r (Type.prod o r int) e

    it "typechecks data types" $ do
      testTypecheck
        Positive
        "type Unit { case unit }\n\
        \define test (-> Unit) { unit }"
        $ Type.fun o r (Type.prod o r (ctor "Unit")) e

      testTypecheck
        Positive
        "type Unit { case unit () }\n\
        \define test (-> Unit) { unit }"
        $ Type.fun o r (Type.prod o r (ctor "Unit")) e

    it "typechecks definitions" $ do
      testTypecheck
        Positive
        "define one (-> Int32) { 1 }\n\
        \define test (-> Int32) { one }"
        $ Type.fun o r (Type.prod o r int) e

      testTypecheck
        Positive
        "define one (-> Int32) { 1 }\n\
        \define two (-> Int32) { 2 }\n\
        \define test (-> Int32) { one two _::mlatu::add_int }"
        $ Type.fun o r (Type.prod o r int) e

      testTypecheck
        Positive
        "define up (Int32 -> Int32) { 1 _::mlatu::add_int }\n\
        \define down (Int32 -> Int32) { -1 _::mlatu::add_int }\n\
        \define test (-> Int32) { 1 up 2 down _::mlatu::add_int }"
        $ Type.fun o r (Type.prod o r int) e

    it "typechecks operators" $ do
      testTypecheck
        Positive
        "define + (Int32, Int32 -> Int32) { _::mlatu::add_int }\n\
        \define test (-> Int32) { 1 + 1 }"
        $ Type.fun o r (Type.prod o r int) e

      testTypecheck
        Positive
        "define + (Int32, Int32 -> Int32) { _::mlatu::add_int }\n\
        \about +:\n\
        \  operator:\n\
        \    right 5\n\
        \define test (-> Int32) { 1 + 1 }"
        $ Type.fun o r (Type.prod o r int) e

      testTypecheck
        Positive
        "define + (Int32, Int32 -> Int32) { _::mlatu::add_int }\n\
        \about +:\n\
        \  operator:\n\
        \    right\n\
        \define test (-> Int32) { 1 + 1 }"
        $ Type.fun o r (Type.prod o r int) e

      testTypecheck
        Positive
        "define + (Int32, Int32 -> Int32) { _::mlatu::add_int }\n\
        \about +:\n\
        \  operator:\n\
        \    5\n\
        \define test (-> Int32) { 1 + 1 }"
        $ Type.fun o r (Type.prod o r int) e

    it "typechecks nested scopes" $ do
      testTypecheck
        Positive
        "intrinsic add (Int32, Int32 -> Int32)\n\
        \define test (-> Int32, Int32) {\n\
        \  1000 -> x1;\n\
        \  100 -> y1;\n\
        \  10\n\
        \  {\n\
        \    -> a1;\n\
        \    a1 x1 add\n\
        \    {\n\
        \      -> b1;\n\
        \      b1 y1 add\n\
        \    } call\n\
        \  } call\n\
        \  \n\
        \  1000 -> x2;\n\
        \  100 -> y2;\n\
        \  10\n\
        \  {\n\
        \    -> a2;\n\
        \    a2 y2 add\n\
        \    {\n\
        \      -> b2;\n\
        \      b2 x2 add\n\
        \    } call\n\
        \  } call\n\
        \}"
        $ Type.fun o r (Type.prod o (Type.prod o r int) int) e

    it "typechecks closures with multiple types" $ do
      testTypecheck
        Positive
        "define test (-> (-> Int32, Float64)) {\n\
        \  0 0.0 -> x, y;\n\
        \  { x y }\n\
        \}"
        $ Type.fun
          o
          r
          ( Type.prod
              o
              r
              (Type.fun o r (Type.prod o (Type.prod o r int) float) e)
          )
          e

  describe "with instance checking" $ do
    it "rejects invalid signature" $ do
      testTypecheck
        Negative
        "type Pair[A, B] { case pair (A, B) }\n\
        \define flip[A, B] (Pair[A, B] -> Pair[A, B]) {\n\
        \  match case pair -> x, y { y x pair }\n\
        \}\n\
        \define test (-> Pair[Char, Int32]) { 1 '1' pair flip }"
        $ Type.fun o r (Type.prod o r (ctor "Pair" :@ char :@ int)) e

    it "accepts valid permissions" $ do
      testTypecheck
        Positive
        "define test (-> +Fail) { abort }"
        $ Type.fun o r r (Type.join o fail_ e)

      testTypecheck
        Positive
        "intrinsic launch_missiles (-> +IO)\n\
        \define test (-> +Fail +IO) { launch_missiles abort }"
        $ Type.fun o r r (Type.join o fail_ (Type.join o io e))

      testTypecheck
        Positive
        "intrinsic launch_missiles (-> +IO)\n\
        \define test (-> +IO +Fail) { launch_missiles abort }"
        $ Type.fun o r r (Type.join o fail_ (Type.join o io e))

    it "accepts redundant permissions" $ do
      testTypecheck
        Positive
        "define test (-> +Fail) {}"
        $ Type.fun o r r (Type.join o fail_ e)

      testTypecheck
        Positive
        "define test (-> +Fail +IO) {}"
        $ Type.fun o r r (Type.join o fail_ (Type.join o io e))

      testTypecheck
        Positive
        "define test (-> +IO +Fail) {}"
        $ Type.fun o r r (Type.join o fail_ (Type.join o io e))

    it "rejects missing permissions" $ do
      testTypecheck
        Negative
        "define test (->) { abort }"
        $ Type.fun o r r e

      testTypecheck
        Negative
        "intrinsic launch_missiles (-> +IO)\n\
        \define test (->) { launch_missiles abort }"
        $ Type.fun o r r e

  describe "with higher-order functions" $ do
    it "typechecks curried functions" $ do
      testTypecheck
        Positive
        "define curried_add (Int32 -> Int32 -> Int32) {\n\
        \  -> x; { -> y; x y _::mlatu::add_int }\n\
        \}\n\
        \define test (-> Int32) { 1 2 curried_add call }"
        $ Type.fun o r (Type.prod o r int) e

    it "typechecks permissions of higher-order functions" $ do
      testTypecheck
        Positive
        "intrinsic launch_missiles (-> +IO)\n\
        \intrinsic map[A, B, +P] (List[A], (A -> B +P) -> List[B] +P)\n\
        \define test (-> List[Int32] +IO) { [1, 2, 3] \\launch_missiles map }"
        $ Type.fun o r (Type.prod o r (ctor "List" :@ int)) (Type.join o io e)

  describe "with coercions" $ do
    it "typechecks identity coercions" $ do
      testTypecheck
        Positive
        "define test (-> Int32) { 1i32 as (Int32) }"
        $ Type.fun o r (Type.prod o r int) e

      testTypecheck
        Negative
        "define test (-> Int32) { 1i64 as (Int32) }"
        $ Type.fun o r (Type.prod o r int) e
  where
    o = Origin.point "" 0 0
    r = TypeVar o $ Var "R" (TypeId 0) Stack
    s = TypeVar o $ Var "S" (TypeId 1) Stack
    e = TypeVar o $ Var "P" (TypeId 2) Permission
    ctor =
      TypeConstructor o . Type.Constructor
        . Qualified Vocabulary.global
    char = ctor "Char"
    int = ctor "Int32"
    io = ctor "IO"
    fail_ = ctor "Fail"
    float = ctor "Float64"

testTypecheck :: Sign -> Text -> Type -> IO ()
testTypecheck sign input expected = do
  result <- runMlatu $ do
    let io = [QualifiedName $ Qualified Vocabulary.global "IO"]
    fragment <- fragmentFromSource io Nothing 1 "<test>" input
    -- FIXME: Avoid redundantly reparsing common vocabulary.
    common <- fragmentFromSource io Nothing 1 "<common>" commonSource
    commonDictionary <- Enter.fragment common Dictionary.empty
    Enter.fragment fragment commonDictionary
  case Dictionary.toList <$> result of
    Right definitions -> case find matching definitions of
      Just (_, Entry.Word _ _ _ _ _ (Just term)) -> do
        let actual = Term.typ term
        check <- runMlatu $ do
          instanceCheck "inferred" actual "declared" expected
          checkpoint
        case sign of
          Positive ->
            assertBool
              (Pretty.render $ Pretty.hsep [pPrint actual, "<:", pPrint expected])
              $ isRight check
          Negative ->
            assertBool
              (Pretty.render $ Pretty.hsep [pPrint actual, "</:", pPrint expected])
              $ isLeft check
      _ ->
        assertFailure $
          Pretty.render $
            Pretty.hsep
              ["missing main word definition:", pPrint definitions]
      where
        matching (Instantiated (Qualified v "test") _, _)
          | v == Vocabulary.global =
            True
        matching _ = False
    Left reports -> case sign of
      Positive ->
        assertFailure $
          toString $
            unlines $
              map (toText . Pretty.render . Report.human) reports
      -- FIXME: This might accept a negative test for the wrong
      -- reason.
      Negative -> pass

-- FIXME: Avoid redundantly re-parsing common vocabulary.
commonSource :: Text
commonSource =
  "\
  \vocab mlatu {\
  \  intrinsic call[R..., S...] (R..., (R... -> S...) -> S...)\n\
  \  intrinsic magic[R..., S...] (R... -> S...)\n\
  \  intrinsic add_int (_::Int32, _::Int32 -> _::Int32)\n\
  \}\n\
  \define call[R..., S...] (R..., (R... -> S...) -> S...) {\n\
  \  _::mlatu::call\n\
  \}\n\
  \intrinsic abort[R..., S...] (R... -> S... +Fail)\n\
  \type Char {}\n\
  \type Float64 {}\n\
  \type Int32 {}\n\
  \type List[T] {}\n\
  \permission IO[R..., S..., +E] (R..., (R... -> S... +IO +E) -> S... +E) {\n\
  \  with (+IO)\n\
  \}\n\
  \permission Fail[R..., S..., +E] (R..., (R... -> S... +Fail +E) -> S... +E) {\n\
  \  with (+Fail)\n\
  \}\n\
  \\&"