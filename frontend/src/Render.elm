module Render exposing (render, renderBody)

import Html exposing (Html, div, text)
import Html.Attributes exposing (class)
import Markdown
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
