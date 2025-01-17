{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}

module ParserTest where

import           Data.Char (chr)
import           Data.Foldable (for_)
import qualified Data.Text as Text
import           Data.Text (Text)
import           Data.Void

import           Hedgehog hiding (Var)
import           Test.Hspec.Megaparsec
import           Text.Megaparsec (parse, ParseErrorBundle)
import           Text.RawString.QQ
import           Test.Tasty.Hspec

import           Data.Aeson.Jq.Expr
import           Data.Aeson.Jq.Parser

shouldParseAs :: Text -> Expr -> Spec
shouldParseAs s e =
  it (Text.unpack s) $ parseExpr s `shouldParse` e

spec_DotAndBracketIndexing :: Spec
spec_DotAndBracketIndexing = do
  describe "expr parses dot-indexing" $ do
    ".foo[.bar + 1]" `shouldParseAs`
      IndexAfter (DotField "foo")
                 (Just (Plus (DotField "bar") (NumLit 1)))

    ".foo.bar" `shouldParseAs`
      DotFieldAfter (DotField "foo") "bar"

    "{foo: 1}.foo" `shouldParseAs`
      DotFieldAfter (Obj [ (FieldExpr (StrLit "foo"), Just (NumLit 1)) ]) "foo"

    [r|{foo: 1}."foo"|] `shouldParseAs`
      DotStrAfter (Obj [ (FieldExpr (StrLit "foo"), Just (NumLit 1)) ]) "foo"

  describe "expr parses bracket-indexing" $ do
    [r|{foo: 1}["foo"]|] `shouldParseAs`
      IndexAfter (Obj [ (FieldExpr (StrLit "foo"), Just (NumLit 1)) ])
                 (Just (StrLit "foo"))

spec_Pipe :: Spec
spec_Pipe =
  describe "expr parses pipes" $ do
    "1 | 2" `shouldParseAs` Pipe one two
    ".foo | .bar" `shouldParseAs`
      Pipe (DotField "foo") (DotField "bar")
    "1 | 2 | 3" `shouldParseAs`
      Pipe one (Pipe two three)
    "1 | (2 | 3)" `shouldParseAs`
      Pipe one (Paren (Pipe two three))
    "(1 | 2) | 3" `shouldParseAs`
      Pipe (Paren (Pipe one two)) three
  where
    one = NumLit 1
    two = NumLit 2
    three = NumLit 3

spec_Parentheses :: Spec
spec_Parentheses =
  describe "expr parses parentheses" $ do
    "(null)" `shouldParseAs` Paren NullLit
    "((null))" `shouldParseAs` Paren (Paren NullLit)
    "([1, ([1, ((1))]), 1])"
      `shouldParseAs`
        Paren (List [one, Paren (List [one, Paren (Paren (one))]), one])
  where
    one = NumLit 1

spec_Obj :: Spec
spec_Obj =
  describe "expr parses simple objects" $ do
    "{}" `shouldParseAs` Obj []

    [r|{"foo": 42}|] `shouldParseAs`
      Obj [(FieldExpr (StrLit "foo"), Just (NumLit 42))]

    "{foo: 42}" `shouldParseAs`
      Obj [(FieldKey "foo", Just (NumLit 42))]

    [r|{"foo": 1, "bar": 2}|]
      `shouldParseAs`
        Obj [ (FieldExpr (StrLit "foo"), Just (NumLit 1))
            , (FieldExpr (StrLit "bar"), Just (NumLit 2))
            ]

    "{foo: 1, bar: 2}"
      `shouldParseAs`
        Obj [ (FieldKey "foo", Just (NumLit 1))
            , (FieldKey "bar", Just (NumLit 2))
            ]

spec_List :: Spec
spec_List =
  describe "expr parses lists" $ do
    "[]"                `shouldParseAs` List []
    "[1,2,3]"           `shouldParseAs` List [NumLit 1, NumLit 2, NumLit 3]
    "[true,false,null]" `shouldParseAs` List [BoolLit True, BoolLit False, NullLit]
    "[[], true, [false, [], [null]]]"
      `shouldParseAs`
        List [ List []
             , BoolLit True
             , List [ BoolLit False
                    , List []
                    , List [NullLit]] ]

spec_Var :: Spec
spec_Var =
  describe "$vars" $
    "$foo" `shouldParseAs` Var "foo"

spec_StrLit :: Spec
spec_StrLit = do
  describe "expr parses" $ do
    [r|""|]              `shouldParseAs` StrLit ""
    [r|"Hello, World!"|] `shouldParseAs` StrLit "Hello, World!"

  -- FIXME: The parser doesn't support escape sequences.

{-

  describe "escape sequences" $ do
    [r|"\""|] `shouldParseAs` StrLit "\"" -- double quote
    [r|"\\"|] `shouldParseAs` StrLit "\\" -- backslash
    [r|"\/"|] `shouldParseAs` StrLit "/"  -- forward slash
    [r|"\b"|] `shouldParseAs` StrLit "\b" -- backspace
    [r|"\f"|] `shouldParseAs` StrLit "\f" -- new page
    [r|"\n"|] `shouldParseAs` StrLit "\n" -- newline
    [r|"\r"|] `shouldParseAs` StrLit "\r" -- carriage return
    [r|"\t"|] `shouldParseAs` StrLit "\t" -- tab


  -- FIXME: The parser is too liberal wrt. characters
  describe "string literals with character literals U+0000 through U+001F" $
    it "should fail when they're not escaped" $
      for_ [0..0x1f] $ \c ->
        parse expr "" `shouldFailOn` Text.pack [ '"', chr c, '"' ]

-}

-- prop_NumLit :: Property
-- prop_NumLit = undefined

spec_NumLit :: Spec
spec_NumLit = do
  describe "expr parses" $ do
    "0"     `shouldParseAs` NumLit 0
    "-1"    `shouldParseAs` NumLit (-1)
    "2.5"   `shouldParseAs` NumLit 2.5
    "-2.5"  `shouldParseAs` NumLit (-2.5)
    "1e100" `shouldParseAs` NumLit 1e100

  describe "expr does not parse" $
    it "\"+42\"" $ parseExpr `shouldFailOn` "+42"

spec_BoolLit_NullLit :: Spec
spec_BoolLit_NullLit =
  describe "expr parses" $ do
    "true"  `shouldParseAs` BoolLit True
    "false" `shouldParseAs` BoolLit False
    "null"  `shouldParseAs` NullLit
