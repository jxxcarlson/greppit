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

**Empty-initial-value caveat.** The vendored custom element sets a
`isProgrammaticUpdate` flag before dispatching `load`, and clears it
only when the resulting doc-change handler fires. When `initialValue`
is `""`, the programmatic dispatch is a no-op (doc was already `""`),
so the handler never fires and the flag sticks as `true` — which causes
the *next* real user input (paste, keystroke) to be silently suppressed
as "programmatic". Work-around: omit the `load` attribute entirely when
initialValue is empty, letting CM6 keep its default `doc: ""` without
the flag ever being set.

-}
view :
    { key : String
    , initialValue : String
    , onInput : String -> msg
    }
    -> Html msg
view opts =
    let
        baseAttrs =
            [ Attr.attribute "selection" "false"
            , Html.Events.on "text-change" (textChangeDecoder opts.onInput)
            ]

        attrs =
            if String.isEmpty opts.initialValue then
                baseAttrs

            else
                Attr.attribute "load" opts.initialValue :: baseAttrs
    in
    Html.Keyed.node "div"
        [ Attr.style "width" "100%", Attr.style "height" "100%" ]
        [ ( opts.key, Html.node "codemirror-editor" attrs [] )
        ]


textChangeDecoder : (String -> msg) -> D.Decoder msg
textChangeDecoder toMsg =
    D.field "detail" (D.field "source" D.string)
        |> D.map toMsg
