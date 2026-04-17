port module Main exposing (main)

import Api
import Auth
import Browser
import Editor
import Html exposing (Html, button, div, text)
import Html.Attributes exposing (class)
import Html.Events exposing (onClick)
import Http
import Process
import Render
import Search
import Task
import Types exposing (..)


-- PORTS


port saveToken : String -> Cmd msg


port removeToken : () -> Cmd msg


-- MAIN


main : Program Flags Model Msg
main =
    Browser.element
        { init = init
        , update = update
        , view = view
        , subscriptions = \_ -> Sub.none
        }


emptyAuthForm : AuthMode -> AuthForm
emptyAuthForm m =
    { mode = m
    , email = ""
    , password = ""
    , submitting = False
    , errorMessage = Nothing
    }


initSignedIn : String -> User -> SignedInData
initSignedIn token user =
    { user = user
    , token = token
    , searchInput = ""
    , searchTick = 0
    , results = []
    , selectedId = Nothing
    , rightMode = DisplayMode Nothing
    }


emptyEditor : EditorState
emptyEditor =
    { editing = Nothing
    , title = ""
    , tags = ""
    , markup = Markdown
    , body = ""
    , saving = False
    , errorMessage = Nothing
    , showDeleteConfirm = False
    }


editorFromSnippet : Snippet -> EditorState
editorFromSnippet s =
    { editing = Just s
    , title = s.title
    , tags = s.tags
    , markup = s.markup
    , body = s.body
    , saving = False
    , errorMessage = Nothing
    , showDeleteConfirm = False
    }


mapEditor : SignedInData -> Model -> (EditorState -> EditorState) -> ( Model, Cmd Msg )
mapEditor s model f =
    case s.rightMode of
        EditorMode e ->
            ( { model | auth = SignedIn { s | rightMode = EditorMode (f e) } }
            , Cmd.none
            )

        _ ->
            ( model, Cmd.none )


updateEditorError : SignedInData -> Model -> Http.Error -> Model
updateEditorError s model err =
    case s.rightMode of
        EditorMode e ->
            { model
                | auth =
                    SignedIn
                        { s
                            | rightMode =
                                EditorMode
                                    { e
                                        | saving = False
                                        , errorMessage = Just (httpError err)
                                    }
                        }
            }

        _ ->
            model


init : Flags -> ( Model, Cmd Msg )
init flags =
    case flags.initialToken of
        Just t ->
            ( { apiBase = flags.apiBase
              , auth = SignedOut (emptyAuthForm LoginMode)
              }
            , Api.me flags.apiBase t (TokenValidated t)
            )

        Nothing ->
            ( { apiBase = flags.apiBase
              , auth = SignedOut (emptyAuthForm LoginMode)
              }
            , Cmd.none
            )



-- UPDATE


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case model.auth of
        SignedOut f ->
            updateSignedOut msg f model

        SignedIn s ->
            updateSignedIn msg s model


updateSignedOut : Msg -> AuthForm -> Model -> ( Model, Cmd Msg )
updateSignedOut msg f model =
    case msg of
        AuthEmailChanged v ->
            ( { model | auth = SignedOut { f | email = v } }, Cmd.none )

        AuthPasswordChanged v ->
            ( { model | auth = SignedOut { f | password = v } }, Cmd.none )

        AuthSwitchMode m ->
            ( { model | auth = SignedOut { f | mode = m, errorMessage = Nothing } }, Cmd.none )

        AuthSubmitted ->
            if f.submitting || String.isEmpty f.email || String.isEmpty f.password then
                ( model, Cmd.none )
            else
                let
                    creds =
                        { email = f.email, password = f.password }

                    cmd =
                        case f.mode of
                            LoginMode  -> Api.login  model.apiBase creds AuthResponded
                            SignupMode -> Api.signup model.apiBase creds AuthResponded
                in
                ( { model | auth = SignedOut { f | submitting = True, errorMessage = Nothing } }
                , cmd
                )

        AuthResponded (Ok ( tok, user )) ->
            ( { model | auth = SignedIn (initSignedIn tok user) }
            , Cmd.batch
                [ saveToken tok
                , Api.listSnippets model.apiBase tok "" SearchResponded
                ]
            )

        AuthResponded (Err err) ->
            ( { model | auth = SignedOut { f | submitting = False, errorMessage = Just (httpError err) } }
            , Cmd.none
            )

        TokenValidated tok (Ok user) ->
            ( { model | auth = SignedIn (initSignedIn tok user) }
            , Api.listSnippets model.apiBase tok "" SearchResponded
            )

        TokenValidated _ (Err _) ->
            -- Stored token is no longer valid.
            ( model, removeToken () )

        _ ->
            ( model, Cmd.none )


updateSignedIn : Msg -> SignedInData -> Model -> ( Model, Cmd Msg )
updateSignedIn msg s model =
    case msg of
        SignedOutPressed ->
            ( { model | auth = SignedOut (emptyAuthForm LoginMode) }
            , removeToken ()
            )

        SearchInputChanged q ->
            let
                nextTick = s.searchTick + 1
                newS = { s | searchInput = q, searchTick = nextTick }
            in
            ( { model | auth = SignedIn newS }
            , Task.perform (\_ -> SearchDebounceTick nextTick q) (Process.sleep 200)
            )

        SearchDebounceTick tick q ->
            if tick /= s.searchTick then
                ( model, Cmd.none )
            else
                ( model
                , Api.listSnippets model.apiBase s.token q SearchResponded
                )

        SearchResponded (Ok results) ->
            ( { model | auth = SignedIn { s | results = results } }, Cmd.none )

        SearchResponded (Err _) ->
            ( model, Cmd.none )

        SelectResult sid ->
            let
                mSnippet = List.filter (\x -> x.id == sid) s.results |> List.head
            in
            ( { model
                | auth =
                    SignedIn
                        { s
                            | selectedId = Just sid
                            , rightMode = DisplayMode mSnippet
                        }
              }
            , Cmd.none
            )

        NewSnippetPressed ->
            ( { model | auth = SignedIn { s | rightMode = EditorMode emptyEditor } }
            , Cmd.none
            )

        EditPressed snippet ->
            ( { model | auth = SignedIn { s | rightMode = EditorMode (editorFromSnippet snippet) } }
            , Cmd.none
            )

        CancelEditor ->
            let
                mSel =
                    s.selectedId
                        |> Maybe.andThen (\sid -> List.filter (\x -> x.id == sid) s.results |> List.head)
            in
            ( { model | auth = SignedIn { s | rightMode = DisplayMode mSel } }
            , Cmd.none
            )

        EditorTitleChanged v ->
            mapEditor s model (\e -> { e | title = v })

        EditorTagsChanged v ->
            mapEditor s model (\e -> { e | tags = v })

        EditorMarkupChanged m ->
            mapEditor s model (\e -> { e | markup = m })

        EditorBodyChanged v ->
            mapEditor s model (\e -> { e | body = v })

        SaveSnippet ->
            case s.rightMode of
                EditorMode e ->
                    case e.editing of
                        Nothing ->
                            ( { model | auth = SignedIn { s | rightMode = EditorMode { e | saving = True, errorMessage = Nothing } } }
                            , Api.createSnippet model.apiBase s.token
                                { title = e.title, tags = e.tags, markup = e.markup, body = e.body }
                                CreateResponded
                            )

                        Just _ ->
                            -- Edit-mode save is handled in Task 12; no-op for now.
                            ( model, Cmd.none )

                _ ->
                    ( model, Cmd.none )

        CreateResponded (Ok snippet) ->
            ( { model
                | auth =
                    SignedIn
                        { s
                            | results = snippet :: List.take 4 s.results
                            , selectedId = Just snippet.id
                            , rightMode = DisplayMode (Just snippet)
                        }
              }
            , Cmd.none
            )

        CreateResponded (Err err) ->
            ( updateEditorError s model err, Cmd.none )

        _ ->
            ( model, Cmd.none )


httpError : Http.Error -> String
httpError err =
    case err of
        Http.BadUrl _       -> "Bad URL"
        Http.Timeout        -> "Network timeout"
        Http.NetworkError   -> "Network error"
        Http.BadStatus 401  -> "Invalid email or password"
        Http.BadStatus 409  -> "That email is already registered"
        Http.BadStatus s    -> "Server error (" ++ String.fromInt s ++ ")"
        Http.BadBody _      -> "Unexpected server response"



-- VIEW


view : Model -> Html Msg
view model =
    case model.auth of
        SignedOut f ->
            div []
                [ header Nothing
                , Auth.view f
                ]

        SignedIn s ->
            div []
                [ header (Just s.user.email)
                , div [ class "app" ]
                    [ div [ class "col-left" ]
                        [ Search.view
                            { searchInput = s.searchInput
                            , results = s.results
                            , selectedId = s.selectedId
                            }
                        ]
                    , viewRight s
                    ]
                ]


viewRight : SignedInData -> Html Msg
viewRight s =
    case s.rightMode of
        DisplayMode Nothing ->
            div [ class "col-right" ]
                [ div [ class "display-snippet" ]
                    [ text "Select a snippet on the left, or click \"New snippet\" to create one." ]
                ]

        DisplayMode (Just snippet) ->
            div [ class "col-right" ]
                [ div [ class "display-snippet" ]
                    [ div [ class "display-header" ]
                        [ div [ class "display-title" ]
                            [ text
                                (if String.isEmpty snippet.title then
                                    "(untitled)"
                                 else
                                    snippet.title
                                )
                            ]
                        , button
                            [ class "btn btn-secondary"
                            , onClick (EditPressed snippet)
                            ]
                            [ text "Edit" ]
                        ]
                    , if String.isEmpty snippet.tags then
                        text ""
                      else
                        div [ class "display-tags" ] [ text snippet.tags ]
                    , Render.render snippet
                    ]
                ]

        EditorMode e ->
            div [ class "col-right" ]
                [ Editor.view e ]


header : Maybe String -> Html Msg
header mEmail =
    div [ class "header" ]
        [ div [ class "header-title" ] [ text "greppit" ]
        , div [ class "header-right" ]
            (case mEmail of
                Just email ->
                    [ button [ class "btn btn-primary", onClick NewSnippetPressed ]
                        [ text "New snippet" ]
                    , div [ class "header-email" ] [ text email ]
                    , button [ class "btn btn-secondary", onClick SignedOutPressed ]
                        [ text "Sign out" ]
                    ]

                Nothing ->
                    []
            )
        ]
