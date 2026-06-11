module Render exposing (render)

import Html exposing (Html, div, text)
import Html.Attributes exposing (class)
import Markdown
import Scripta
import Types exposing (Markup(..), Msg(..), Snippet)


{-| Render a snippet's body for the display pane. The return type is `Html Msg`
because Scripta's rendered output carries interaction events; for this
read-only view every event is mapped to `NoOp`.
-}
render : Snippet -> Html Msg
render s =
    case s.markup of
        Markdown ->
            div [ class "display-body" ] (Markdown.toHtml Nothing s.body)

        PlainText ->
            -- Preserve line breaks and whitespace; no markdown parsing.
            -- `.display-body-plain` sets `white-space: pre-wrap`.
            div [ class "display-body display-body-plain" ] [ text s.body ]

        Scripta ->
            let
                options =
                    Scripta.defaultOptions
                        |> Scripta.withContentWidth 700
                        |> Scripta.withWindowWidth 700

                output =
                    Scripta.compile options s.body
                        |> Scripta.mapEvent (\_ -> NoOp)
            in
            div [ class "display-body" ] (output.title :: output.body)
