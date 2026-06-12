module Render exposing (render, renderBody, markdownHeadings)

import Html exposing (Html, div, text)
import Html.Attributes exposing (class)
import Markdown
import Markdown.Block as Block exposing (Block(..))
import Markdown.Inline as Inline
import Markdown.TableOfContents as TOC
import Scripta
import Types exposing (Markup(..), Msg(..), Snippet)


{-| Render a saved snippet's body for the display pane. -}
render : Snippet -> Html Msg
render s =
    renderBody s.markup s.body


{-| Render an arbitrary body string for a given markup type. Used by both the
display pane and the editor's live preview. The return type is `Html Msg`
because Scripta's rendered output carries interaction events; for these
read-only views every event is mapped to `NoOp`.
-}
renderBody : Markup -> String -> Html Msg
renderBody markup body =
    case markup of
        Markdown ->
            div [ class "display-body" ] (Markdown.toHtml Nothing body)

        PlainText ->
            -- Preserve line breaks and whitespace; no markdown parsing.
            -- `.display-body-plain` sets `white-space: pre-wrap`.
            div [ class "display-body display-body-plain" ] [ text body ]

        Scripta ->
            let
                options =
                    Scripta.defaultOptions
                        |> Scripta.withContentWidth 700
                        |> Scripta.withWindowWidth 700

                output =
                    Scripta.compile options body
                        |> Scripta.mapEvent (\_ -> NoOp)
            in
            div [ class "display-body" ] (output.title :: output.body)


{-| The flat list of Markdown headings in document order, each with the slug id
used both for the rendered heading's `id` attribute and for its TOC link, its
level, and its plain-text title. Slugging goes through `TOC.headingId` applied to
`Inline.extractText`, matching how the TOC link target is computed.
-}
markdownHeadings : String -> List { id : String, level : Int, title : String }
markdownHeadings body =
    headingsFromBlocks (Block.parse Nothing body)


headingsFromBlocks : List (Block b i) -> List { id : String, level : Int, title : String }
headingsFromBlocks blocks =
    List.concatMap headingOf blocks


headingOf : Block b i -> List { id : String, level : Int, title : String }
headingOf block =
    case block of
        Heading _ level inlines ->
            let
                t =
                    Inline.extractText inlines
            in
            [ { id = TOC.headingId t, level = level, title = t } ]

        _ ->
            []
