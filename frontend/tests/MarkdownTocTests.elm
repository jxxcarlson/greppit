module MarkdownTocTests exposing (suite)

import Expect
import Render
import Test exposing (Test, describe, test)


suite : Test
suite =
    describe "Render.markdownHeadings"
        [ test "extracts id, level, and title for each heading in order" <|
            \_ ->
                Render.markdownHeadings "# Hello World\n\nsome text\n\n## Section A"
                    |> Expect.equal
                        [ { id = "hello-world", level = 1, title = "Hello World" }
                        , { id = "section-a", level = 2, title = "Section A" }
                        ]
        , test "returns empty list when there are no headings" <|
            \_ ->
                Render.markdownHeadings "just a paragraph"
                    |> Expect.equal []
        ]
