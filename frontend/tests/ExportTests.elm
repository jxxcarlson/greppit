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
        , describe "formatTags"
            [ test "empty string returns Nothing" <|
                \_ ->
                    Export.formatTags ""
                        |> Expect.equal Nothing
            , test "whitespace-only returns Nothing" <|
                \_ ->
                    Export.formatTags "   "
                        |> Expect.equal Nothing
            , test "single tag" <|
                \_ ->
                    Export.formatTags "alpha"
                        |> Expect.equal (Just "Tags: #alpha")
            , test "multiple tags joined with comma" <|
                \_ ->
                    Export.formatTags "alpha beta"
                        |> Expect.equal (Just "Tags: #alpha, #beta")
            , test "ignores extra whitespace between tags" <|
                \_ ->
                    Export.formatTags "  alpha   beta  "
                        |> Expect.equal (Just "Tags: #alpha, #beta")
            ]
        , describe "body"
            [ test "with tags and markdown markup" <|
                \_ ->
                    let
                        s =
                            fixture { zkuId = "jxxcarlson-20260118003017", title = "t" }
                    in
                    { s | body = "Some body text.", tags = "alpha beta", markup = Markdown }
                        |> Export.body
                        |> Expect.equal "Some body text.\n\nTags: #alpha, #beta\nmarkup: markdown\n"
            , test "omits Tags line when no tags" <|
                \_ ->
                    let
                        s =
                            fixture { zkuId = "x-20260118003017", title = "t" }
                    in
                    { s | body = "Body.", tags = "", markup = Markdown }
                        |> Export.body
                        |> Expect.equal "Body.\n\nmarkup: markdown\n"
            , test "scripta markup variant" <|
                \_ ->
                    let
                        s =
                            fixture { zkuId = "x-20260118003017", title = "t" }
                    in
                    { s | body = "B", tags = "", markup = Scripta }
                        |> Export.body
                        |> Expect.equal "B\n\nmarkup: scripta\n"
            , test "plaintext markup variant" <|
                \_ ->
                    let
                        s =
                            fixture { zkuId = "x-20260118003017", title = "t" }
                    in
                    { s | body = "B", tags = "", markup = PlainText }
                        |> Export.body
                        |> Expect.equal "B\n\nmarkup: plaintext\n"
            , test "trims trailing newlines from body to one blank separator" <|
                \_ ->
                    let
                        s =
                            fixture { zkuId = "x-20260118003017", title = "t" }
                    in
                    { s | body = "B\n\n\n", tags = "", markup = Markdown }
                        |> Export.body
                        |> Expect.equal "B\n\nmarkup: markdown\n"
            , test "empty body starts with blank line then trailer" <|
                \_ ->
                    let
                        s =
                            fixture { zkuId = "x-20260118003017", title = "t" }
                    in
                    { s | body = "", tags = "", markup = Markdown }
                        |> Export.body
                        |> Expect.equal "\n\nmarkup: markdown\n"
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
