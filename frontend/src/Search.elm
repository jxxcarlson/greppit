module Search exposing (view)

import Html exposing (Html, div, input, text)
import Html.Attributes exposing (class, classList, placeholder, value)
import Html.Events exposing (onClick, onInput)
import Types exposing (Msg(..), Snippet)


view :
    { searchInput : String
    , results : List Snippet
    , selectedId : Maybe String
    }
    -> Html Msg
view { searchInput, results, selectedId } =
    div []
        [ input
            [ class "search-input"
            , placeholder "Search..."
            , value searchInput
            , onInput SearchInputChanged
            ]
            []
        , div [ class "result-list" ]
            (List.map (viewItem selectedId) results)
        ]


viewItem : Maybe String -> Snippet -> Html Msg
viewItem selectedId s =
    div
        [ classList
            [ ( "result-item", True )
            , ( "selected", selectedId == Just s.id )
            ]
        , onClick (SelectResult s.id)
        ]
        [ div [ class "result-title" ] [ text (if String.isEmpty s.title then "(untitled)" else s.title) ]
        , if String.isEmpty s.tags then
            text ""
          else
            div [ class "result-tags" ] [ text s.tags ]
        ]
