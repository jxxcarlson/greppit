module CodeMirror exposing (view)

import Html exposing (Html)
import Html.Attributes as Attr
import Html.Events
import Html.Keyed
import Json.Decode as D


{-| Render a CodeMirror editor.

  - `key` is used as the stable key for Html.Keyed, so changing the key
    forces a full remount (used when switching between New / Edit targets).
  - `value` is the initial body; it is written to the `load` attribute and
    picked up by the custom element. Later edits come through `onInput`.
  - `onInput` is called with the new body on each keystroke.

The custom element is defined in `codemirror-element.js` and emits
`text-change` events with `{ detail: { position: Int, source: String } }`.

-}
view :
    { key : String
    , value : String
    , onInput : String -> msg
    }
    -> Html msg
view opts =
    Html.Keyed.node "div"
        [ Attr.style "width" "100%", Attr.style "height" "100%" ]
        [ ( opts.key
          , Html.node "codemirror-editor"
                [ Attr.attribute "load" opts.value
                , Attr.attribute "selection" "false"
                , Html.Events.on "text-change" (textChangeDecoder opts.onInput)
                ]
                []
          )
        ]


textChangeDecoder : (String -> msg) -> D.Decoder msg
textChangeDecoder toMsg =
    D.field "detail" (D.field "source" D.string)
        |> D.map toMsg
