module Editor exposing (view)

import CodeMirror
import Html exposing (Html, button, div, input, label, option, select, text)
import Html.Attributes exposing (class, disabled, placeholder, selected, type_, value)
import Html.Events exposing (onClick, onInput)
import Types exposing (EditorState, Markup(..), Msg(..), stringToMarkup)


view : EditorState -> Html Msg
view st =
    let
        isEdit = st.editing /= Nothing

        keyForEditor =
            case st.editing of
                Just s  -> "edit:" ++ s.id
                Nothing -> "new"
    in
    div [ class "editor-form" ]
        ([ div [ class "display-title" ]
            [ text (if isEdit then "Edit snippet" else "New snippet") ]
        , case st.errorMessage of
            Just m  -> div [ class "auth-error" ] [ text m ]
            Nothing -> text ""
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
                [ option [ value "markdown",  selected (st.markup == Markdown)  ] [ text "Markdown" ]
                , option [ value "plaintext", selected (st.markup == PlainText) ] [ text "Plain text" ]
                , option [ value "scripta",   selected (st.markup == Scripta)   ] [ text "Scripta" ]
                ]
            ]
        , div [ class "editor-body" ]
            [ CodeMirror.view
                { key = keyForEditor
                , initialValue =
                    case st.editing of
                        Just s  -> s.body
                        Nothing -> ""
                , onInput = EditorBodyChanged
                }
            ]
        , div [ class "editor-actions" ]
            ([ button
                [ class "btn btn-primary"
                , onClick SaveSnippet
                , disabled st.saving
                ]
                [ text (if st.saving then "Saving..." else "Save") ]
            , button
                [ class "btn btn-secondary"
                , onClick CancelEditor
                , disabled st.saving
                ]
                [ text "Cancel" ]
            ]
            ++ (if isEdit then
                    [ button
                        [ class "btn btn-danger"
                        , onClick DeletePressed
                        , disabled st.saving
                        ]
                        [ text "Delete" ]
                    ]
                else
                    []
               )
            )
        ]
        ++ (if st.showDeleteConfirm then
                [ div [ class "auth-error" ] [ text "Delete this snippet? This cannot be undone." ]
                , div [ class "editor-actions" ]
                    [ button [ class "btn btn-danger", onClick ConfirmDelete ] [ text "Yes, delete" ]
                    , button [ class "btn btn-secondary", onClick CancelDelete ] [ text "Cancel" ]
                    ]
                ]
            else
                []
           )
        )
