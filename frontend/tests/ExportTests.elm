module ExportTests exposing (suite)

import Expect
import Export
import Test exposing (Test, describe, test)
import Time
import Types exposing (Markup(..), Snippet)


fixture : { zkuId : String, title : String } -> Snippet
fixture x =
    { id = "00000000-0000-0000-0000-000000000000"
    , userId = "u1"
    , zkuId = x.zkuId
    , title = x.title
    , tags = ""
    , markup = Markdown
    , body = ""
    , createdAt = Time.millisToPosix 0
    , updatedAt = Time.millisToPosix 0
    }


suite : Test
suite =
    describe "Export"
        [ describe "baseIdOf"
            [ test "strips username prefix" <|
                \_ ->
                    Export.baseIdOf "jxxcarlson-20260118003017"
                        |> Expect.equal "20260118003017"
            , test "preserves collision suffix" <|
                \_ ->
                    Export.baseIdOf "jxxcarlson-20260118003017-2"
                        |> Expect.equal "20260118003017-2"
            , test "splits on the first dash only" <|
                \_ ->
                    Export.baseIdOf "ab-cd-ef"
                        |> Expect.equal "cd-ef"
            , test "returns the input when no dash is present" <|
                \_ ->
                    Export.baseIdOf "nodash"
                        |> Expect.equal "nodash"
            ]
        , describe "sanitizeTitle"
            [ test "preserves plain ASCII" <|
                \_ ->
                    Export.sanitizeTitle "Painting Random Walk"
                        |> Expect.equal "Painting Random Walk"
            , test "replaces illegal filename chars with space and collapses" <|
                \_ ->
                    Export.sanitizeTitle "Notes: 2026/04"
                        |> Expect.equal "Notes 2026 04"
            , test "replaces all of / \\ : * ? \" < > |" <|
                \_ ->
                    Export.sanitizeTitle "a/b\\c:d*e?f\"g<h>i|j"
                        |> Expect.equal "a b c d e f g h i j"
            , test "replaces control characters with space" <|
                \_ ->
                    Export.sanitizeTitle "foo\tbar\nbaz"
                        |> Expect.equal "foo bar baz"
            , test "drops non-ASCII characters" <|
                \_ ->
                    Export.sanitizeTitle "Café notes"
                        |> Expect.equal "Caf notes"
            , test "all-non-ASCII yields empty" <|
                \_ ->
                    Export.sanitizeTitle "思考"
                        |> Expect.equal ""
            , test "empty input yields empty" <|
                \_ ->
                    Export.sanitizeTitle ""
                        |> Expect.equal ""
            , test "whitespace-only yields empty" <|
                \_ ->
                    Export.sanitizeTitle "   \t  "
                        |> Expect.equal ""
            , test "truncates at 120 chars" <|
                \_ ->
                    Export.sanitizeTitle (String.repeat 200 "a")
                        |> String.length
                        |> Expect.equal 120
            ]
        , describe "filename"
            [ test "base id + sanitized title" <|
                \_ ->
                    fixture { zkuId = "jxxcarlson-20260118003017", title = "Painting Random Walk" }
                        |> Export.filename
                        |> Expect.equal "20260118003017 Painting Random Walk.txt"
            , test "empty title uses base id alone" <|
                \_ ->
                    fixture { zkuId = "jxxcarlson-20260118003017", title = "" }
                        |> Export.filename
                        |> Expect.equal "20260118003017.txt"
            , test "whitespace-only title uses base id alone" <|
                \_ ->
                    fixture { zkuId = "jxxcarlson-20260118003017", title = "   " }
                        |> Export.filename
                        |> Expect.equal "20260118003017.txt"
            , test "all-non-ASCII title uses base id alone" <|
                \_ ->
                    fixture { zkuId = "jxxcarlson-20260118003017", title = "思考" }
                        |> Export.filename
                        |> Expect.equal "20260118003017.txt"
            , test "collision suffix is preserved" <|
                \_ ->
                    fixture { zkuId = "jxxcarlson-20260118003017-2", title = "Some Title" }
                        |> Export.filename
                        |> Expect.equal "20260118003017-2 Some Title.txt"
            , test "illegal chars sanitized" <|
                \_ ->
                    fixture { zkuId = "jxxcarlson-20260118003017", title = "a/b:c" }
                        |> Export.filename
                        |> Expect.equal "20260118003017 a b c.txt"
            ]
        ]
