module Render exposing (renderBody, renderWithToc, markdownHeadings)

import Html exposing (Html, div, text)
import Html.Attributes exposing (class, id)
import Html.Events exposing (onClick)
import Markdown
import Markdown.Block as Block exposing (Block(..))
import Markdown.Inline as Inline
import Markdown.TableOfContents as TOC
import Scripta
import Types exposing (Markup(..), Msg(..))


{-| Render an arbitrary body string for a given markup type. Used by the editor
live preview (body only, no TOC). Every Scripta interaction event maps to `NoOp`.
-}
renderBody : Markup -> String -> Html Msg
renderBody markup body =
    case markup of
        Markdown ->
            div [ class "display-body" ] (Markdown.toHtml Nothing body)

        PlainText ->
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


{-| Render a body for the reader pane along with a table-of-contents entry list.
Used by reader mode. For Scripta the TOC comes from the compiler (`withTOC True`)
and its `ClickedId` events become `ScrollToHeading`; for Markdown the body's
headings get `id`s and the TOC is built from `markdownHeadings`; PlainText has no
TOC.
-}
renderWithToc : Markup -> String -> { body : Html Msg, toc : List (Html Msg) }
renderWithToc markup body =
    case markup of
        Markdown ->
            let
                blocks =
                    Block.parse Nothing body
            in
            { body = div [ class "display-body" ] (List.concatMap renderMarkdownBlock blocks)
            , toc = List.map tocEntryView (headingsFromBlocks blocks)
            }

        PlainText ->
            { body = div [ class "display-body display-body-plain" ] [ text body ]
            , toc = []
            }

        Scripta ->
            let
                options =
                    Scripta.defaultOptions
                        |> Scripta.withContentWidth 700
                        |> Scripta.withWindowWidth 700
                        |> Scripta.withTOC True

                output =
                    Scripta.compile options body
                        |> Scripta.mapEvent scriptaEventToMsg
            in
            { body = div [ class "display-body" ] (output.title :: output.body)
            , toc = output.toc
            }


scriptaEventToMsg : Scripta.Event -> Msg
scriptaEventToMsg event =
    case event of
        Scripta.ClickedId elementId ->
            ScrollToHeading elementId

        _ ->
            NoOp


renderMarkdownBlock : Block b i -> List (Html Msg)
renderMarkdownBlock block =
    case block of
        Block.Heading _ level inlines ->
            [ Html.node ("h" ++ String.fromInt level)
                [ id (TOC.headingId (Inline.extractText inlines)) ]
                (List.map Inline.toHtml inlines)
            ]

        _ ->
            Block.toHtml block


tocEntryView : { id : String, level : Int, title : String } -> Html Msg
tocEntryView h =
    div
        [ class ("toc-entry toc-level-" ++ String.fromInt h.level)
        , onClick (ScrollToHeading h.id)
        ]
        [ text h.title ]


{-| The flat list of Markdown headings in document order, each with the slug id
used both for the rendered heading's `id` attribute and for its TOC link, its
level, and its plain-text title.
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
        Block.Heading _ level inlines ->
            let
                t =
                    Inline.extractText inlines
            in
            [ { id = TOC.headingId t, level = level, title = t } ]

        _ ->
            []
