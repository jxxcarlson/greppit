module Editor exposing (view)

import CodeMirror
import Html exposing (Html, button, div, input, label, option, select, text)
import Html.Attributes exposing (class, disabled, placeholder, selected, type_, value)
import Html.Events exposing (onClick, onInput)
import Render
import Types exposing (EditorState, Markup(..), Msg(..), stringToMarkup)


view : EditorState -> Html Msg
view st =
    let
        isEdit =
            st.editing /= Nothing

        -- Key and initial body are fixed when the editor opens, so an
        -- auto-save that creates or updates the snippet doesn't remount or
        -- reload CodeMirror.
        keyForEditor =
            st.editorKey

        busy =
            st.saving || st.autoSaving
    in
    div [ class "editor-form" ]
        [ div [ class "display-title" ]
            [ text (if isEdit then "Edit snippet" else "New snippet") ]
        , case st.errorMessage of
            Just m ->
                div [ class "auth-error" ] [ text m ]

            Nothing ->
                text ""
        , div [ class "editor-row" ]
            [ label [] [ text "Title" ]
            , input
                [ type_ "text"
                , placeholder "Title"
                , value st.title
                , onInput EditorTitleChanged
                ]
                []
            ]
        , div [ class "editor-row" ]
            [ label [] [ text "Tags" ]
            , input
                [ type_ "text"
                , placeholder "space separated"
                , value st.tags
                , onInput EditorTagsChanged
                ]
                []
            ]
        , div [ class "editor-row" ]
            [ label [] [ text "Markup" ]
            , select
                [ onInput (\v -> EditorMarkupChanged (Maybe.withDefault Markdown (stringToMarkup v))) ]
                [ option [ value "markdown", selected (st.markup == Markdown) ] [ text "Markdown" ]
                , option [ value "plaintext", selected (st.markup == PlainText) ] [ text "Plain text" ]
                , option [ value "scripta", selected (st.markup == Scripta) ] [ text "Scripta" ]
                ]
            ]
        , div [ class "editor-actions" ]
            ([ button
                [ class "btn btn-primary"
                , onClick SaveSnippet
                , disabled busy
                ]
                [ text (if st.saving then "Saving..." else "Save") ]
             , button
                [ class "btn btn-secondary"
                , onClick CancelEditor
                , disabled busy
                ]
                [ text "Close" ]
             , div [ class "autosave-status" ] [ text (autoSaveStatus st) ]
             ]
                ++ (if isEdit then
                        [ button
                            [ class "btn btn-secondary"
                            , onClick ExportPressed
                            , disabled busy
                            ]
                            [ text "Export" ]
                        , button
                            [ class "btn btn-danger"
                            , onClick DeletePressed
                            , disabled busy
                            ]
                            [ text "Delete" ]
                        ]

                    else
                        []
                   )
            )
        , div [ class "editor-split" ]
            [ div [ class "editor-source" ]
                [ CodeMirror.view
                    { key = keyForEditor
                    , initialValue = st.initialBody
                    , onInput = EditorBodyChanged
                    }
                ]
            , div [ class "editor-preview" ]
                [ Render.renderBody st.markup st.previewSource ]
            ]
        , if st.showDeleteConfirm then
            div []
                [ div [ class "auth-error" ] [ text "Delete this snippet? This cannot be undone." ]
                , div [ class "editor-actions" ]
                    [ button [ class "btn btn-danger", onClick ConfirmDelete ] [ text "Yes, delete" ]
                    , button [ class "btn btn-secondary", onClick CancelDelete ] [ text "Cancel" ]
                    ]
                ]

          else
            text ""
        ]


autoSaveStatus : EditorState -> String
autoSaveStatus st =
    if st.autoSaving then
        "Saving…"

    else
        case st.autoSaveError of
            Just m ->
                "Auto-save failed: " ++ m

            Nothing ->
                if st.dirty then
                    "Unsaved changes"

                else if st.editing /= Nothing then
                    "Saved"

                else
                    ""
