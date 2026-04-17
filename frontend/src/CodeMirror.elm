module CodeMirror exposing (view)

import Html exposing (Html)
import Html.Attributes as Attr
import Html.Events
import Html.Keyed
import Json.Decode as D


{-| Render a CodeMirror editor.

  - `key` identifies the mount target. Changing the key forces a full remount
    (used when switching between New / Edit / different-Edit targets).
  - `initialValue` is written to the `load` attribute ONCE at mount time.
    Subsequent edits come back through `onInput` events. Do NOT pass the live
    buffer here; pass the value you want the editor to start with.
  - `onInput` is called with the new body on each keystroke.

The custom element is defined in `codemirror-element.js` and emits
`text-change` events with `{ detail: { position: Int, source: String } }`.

-}
view :
    { key : String
    , initialValue : String
    , onInput : String -> msg
    }
    -> Html msg
view opts =
    Html.Keyed.node "div"
        [ Attr.style "width" "100%", Attr.style "height" "100%" ]
        [ ( opts.key
          , Html.node "codemirror-editor"
                [ Attr.attribute "load" opts.initialValue
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
