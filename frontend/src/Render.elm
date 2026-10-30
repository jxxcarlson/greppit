module Render exposing (hasMarkdownTitle, renderBody, renderWithToc)

import Html exposing (Html, div, text)
import Html.Attributes exposing (class)
import Scripta
import Types exposing (Markup(..), Msg(..))
import XMarkdown.API
import XMarkdown.Types


{-| Render an arbitrary body string for a given markup type. Used by the editor
live preview (body only, no TOC). Every compiler interaction event maps to `NoOp`.
-}
renderBody : Markup -> String -> Html Msg
renderBody markup body =
    case markup of
        Markdown ->
            div [ class "display-body" ] (XMarkdown.API.compileOutput markdownParams body).body
                |> Html.map (\_ -> NoOp)

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
Used by reader mode. Both compilers build the TOC: Scripta's `ClickedId` and
XMarkdown's `SelectId` events become `ScrollToHeading`. PlainText has no TOC.
-}
renderWithToc : Markup -> String -> { body : Html Msg, toc : List (Html Msg) }
renderWithToc markup body =
    case markup of
        Markdown ->
            let
                output =
                    XMarkdown.API.compileOutput markdownParams body
            in
            { body = div [ class "display-body" ] output.body |> Html.map xmarkdownMsgToMsg
            , toc = List.map (Html.map xmarkdownMsgToMsg) output.toc
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


markdownParams : XMarkdown.Types.CompilerParameters
markdownParams =
    let
        defaults =
            XMarkdown.API.defaultCompilerParameters
    in
    { defaults | docWidth = 700, windowWidth = 700 }


xmarkdownMsgToMsg : XMarkdown.Types.MarkupMsg -> Msg
xmarkdownMsgToMsg msg =
    case msg of
        XMarkdown.Types.SelectId elementId ->
            ScrollToHeading elementId

        _ ->
            NoOp


{-| Whether a Markdown body starts with an XMarkdown title block that sets a
`%title`. The compiler then draws the title itself, so the reader can leave
out the snippet-title header.

This mirrors the compiler's rule (`AST.TitleBlock`, not exposed by the
package): the document's first block, after any blank lines, starts with `%`;
`%key value` lines set fields, and `% ...` (space after `%`) is a comment.

-}
hasMarkdownTitle : String -> Bool
hasMarkdownTitle body =
    let
        firstBlock =
            body
                |> String.lines
                |> dropWhile (String.trim >> String.isEmpty)
                |> takeWhile (String.trim >> String.isEmpty >> not)
                |> List.map String.trim
    in
    case firstBlock of
        first :: _ ->
            String.startsWith "%" first
                && List.any (\line -> titleValue line /= Nothing) firstBlock

        [] ->
            False


titleValue : String -> Maybe String
titleValue line =
    let
        rest =
            String.dropLeft 1 line
    in
    if String.startsWith "%" line && not (String.startsWith " " rest) then
        case String.words rest of
            "title" :: _ ->
                case String.trim (String.dropLeft (String.length "title") rest) of
                    "" ->
                        Nothing

                    value ->
                        Just value

            _ ->
                Nothing

    else
        Nothing


dropWhile : (a -> Bool) -> List a -> List a
dropWhile pred list =
    case list of
        x :: xs ->
            if pred x then
                dropWhile pred xs

            else
                list

        [] ->
            []


takeWhile : (a -> Bool) -> List a -> List a
takeWhile pred list =
    case list of
        x :: xs ->
            if pred x then
                x :: takeWhile pred xs

            else
                []

        [] ->
            []
