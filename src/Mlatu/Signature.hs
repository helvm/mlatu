-- |
-- Module      : Mlatu.Signature
-- Description : Type signatures
-- Copyright   : (c) Caden Haustin, 2021
-- License     : MIT
-- Maintainer  : mlatu@brightlysalty.33mail.com
-- Stability   : experimental
-- Portability : GHC
module Mlatu.Signature
  ( Signature (..),
    origin,
  )
where

import Mlatu.Entry.Parameter (Parameter (Parameter))
import Mlatu.Kind (Kind (..))
import Mlatu.Name (GeneralName)
import Mlatu.Origin (Origin)
import Mlatu.Pretty qualified as Pretty
import Mlatu.Type (Type)
import Mlatu.Type qualified as Type
import Relude hiding (Type)
import Text.PrettyPrint qualified as Pretty
import Text.PrettyPrint.HughesPJClass (Pretty (..))

-- | A parsed type signature.
data Signature
  = -- | @List\<T\>@
    Application !Signature !Signature !Origin
  | -- | An empty stack.
    Bottom !Origin
  | -- | @A, B -> C, D +P +Q@
    Function ![Signature] ![Signature] ![GeneralName] !Origin
  | -- | @\<R..., T, +P\> (...)@
    Quantified ![Parameter] !Signature !Origin
  | -- | @T@
    Variable !GeneralName !Origin
  | -- | @R..., A, B -> S..., C, D +P +Q@
    StackFunction
      !Signature
      ![Signature]
      !Signature
      ![Signature]
      ![GeneralName]
      !Origin
  | -- | Produced when generating signatures for lifted quotations after
    -- typechecking.
    Type !Type
  deriving (Show)

-- | Signatures are compared regardless of origin.
instance Eq Signature where
  Application a b _ == Application c d _ = (a, b) == (c, d)
  Function a b c _ == Function d e f _ = (a, b, c) == (d, e, f)
  Quantified a b _ == Quantified c d _ = (a, b) == (c, d)
  Variable a _ == Variable b _ = a == b
  StackFunction a b c d e _ == StackFunction f g h i j _ =
    (a, b, c, d, e) == (f, g, h, i, j)
  _ == _ = False

origin :: Signature -> Origin
origin signature = case signature of
  Application _ _ o -> o
  Bottom o -> o
  Function _ _ _ o -> o
  Quantified _ _ o -> o
  Variable _ o -> o
  StackFunction _ _ _ _ _ o -> o
  Type t -> Type.origin t

instance Pretty Signature where
  pPrint (Application a b _) =
    Pretty.hcat
      [pPrint a, Pretty.angles $ pPrint b]
  pPrint (Bottom _) = "<bottom>"
  pPrint (Function as bs es _) =
    Pretty.parens $
      Pretty.hsep $
        [ Pretty.list $ map pPrint as,
          "->",
          Pretty.list $ map pPrint bs
        ]
          ++ map ((Pretty.char '+' Pretty.<>) . pPrint) es
  pPrint (Quantified names typ _) =
    Pretty.hsep
      [ Pretty.angles $ Pretty.list $ map prettyVar names,
        pPrint typ
      ]
    where
      prettyVar :: Parameter -> Pretty.Doc
      prettyVar (Parameter _ name kind) = case kind of
        Value -> pPrint name
        Stack -> pPrint name Pretty.<> "..."
        Permission -> Pretty.char '+' Pretty.<> pPrint name
        _invalidForQuantified -> error "quantified signature contains variable of invalid kind"
  pPrint (Variable name _) = pPrint name
  pPrint (StackFunction r as s bs es _) =
    Pretty.parens $
      Pretty.hsep $
        (pPrint r Pretty.<> "...") :
        map pPrint as ++ ["->"]
          ++ ((pPrint s Pretty.<> "...") : map pPrint bs)
          ++ map ((Pretty.char '+' Pretty.<>) . pPrint) es
  pPrint (Type t) = pPrint t