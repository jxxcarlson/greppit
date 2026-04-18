module Render exposing (render)

import Html exposing (Html, div, text)
import Html.Attributes exposing (class)
import Markdown
import Types exposing (Markup(..), Snippet)


render : Snippet -> Html msg
render s =
    case s.markup of
        Markdown ->
            div [ class "display-body" ] (Markdown.toHtml Nothing s.body)

        PlainText ->
            -- Preserve line breaks and whitespace; no markdown parsing.
            -- `.display-body-plain` sets `white-space: pre-wrap`.
            div [ class "display-body display-body-plain" ] [ text s.body ]

        Scripta ->
            div [ class "display-body" ]
                [ text "Scripta rendering not yet enabled." ]
