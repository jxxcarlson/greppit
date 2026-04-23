module ExportTests exposing (suite)

import Expect
import Export
import Test exposing (Test, describe, test)


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
        ]
