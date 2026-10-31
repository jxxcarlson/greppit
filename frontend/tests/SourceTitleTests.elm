module SourceTitleTests exposing (suite)

import Expect
import Render
import Test exposing (Test, describe, test)
import Types exposing (Markup(..))


suite : Test
suite =
    describe "source titles"
        [ markdown
        , sourceTitle
        ]


sourceTitle : Test
sourceTitle =
    describe "Render.hasSourceTitle"
        [ test "Scripta with a title block" <|
            \_ ->
                Render.hasSourceTitle Scripta "| title\nGood Podcasts!\n\nSome text."
                    |> Expect.equal True
        , test "Scripta without a title block" <|
            \_ ->
                Render.hasSourceTitle Scripta "# Podcasts\n\nSome text."
                    |> Expect.equal False
        , test "Scripta with an empty title block" <|
            \_ ->
                Render.hasSourceTitle Scripta "| title\n\nSome text."
                    |> Expect.equal False
        , test "Markdown uses the %title rule" <|
            \_ ->
                Render.hasSourceTitle Markdown "%title T\n\nText"
                    |> Expect.equal True
        , test "plain text never has a source title" <|
            \_ ->
                Render.hasSourceTitle PlainText "%title T\n| title\nX"
                    |> Expect.equal False
        ]


markdown : Test
markdown =
    describe "Render.hasMarkdownTitle"
        [ test "a leading title block with %title" <|
            \_ ->
                Render.hasMarkdownTitle "%title Three Poems\n%author N. Darwish\n\n## I Write the Land"
                    |> Expect.equal True
        , test "blank lines before the title block are fine" <|
            \_ ->
                Render.hasMarkdownTitle "\n\n%title T\n\nText"
                    |> Expect.equal True
        , test "other % lines may come first" <|
            \_ ->
                Render.hasMarkdownTitle "%source poems.md\n%title T"
                    |> Expect.equal True
        , test "no title block" <|
            \_ ->
                Render.hasMarkdownTitle "# Intro\n\nText"
                    |> Expect.equal False
        , test "a title block that is not at the start does not count" <|
            \_ ->
                Render.hasMarkdownTitle "Text first.\n\n%title Late"
                    |> Expect.equal False
        , test "a title block without %title does not count" <|
            \_ ->
                Render.hasMarkdownTitle "%author A\n%date D\n\nText"
                    |> Expect.equal False
        , test "an empty %title does not count" <|
            \_ ->
                Render.hasMarkdownTitle "%title   \n%author A"
                    |> Expect.equal False
        , test "% title (space after %) is a comment, not a title" <|
            \_ ->
                Render.hasMarkdownTitle "% title Not A Title"
                    |> Expect.equal False
        , test "%title must be in the first block" <|
            \_ ->
                Render.hasMarkdownTitle "%author A\n\n%title T"
                    |> Expect.equal False
        ]
