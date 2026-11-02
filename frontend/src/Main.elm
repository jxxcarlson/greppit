port module Main exposing (main)

import Api
import Auth
import Browser
import Editor
import Export
import File.Download
import Html exposing (Html, button, div, text)
import Html.Attributes exposing (attribute, class, title)
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


port scrollToElement : String -> Cmd msg


port saveLanguage : String -> Cmd msg


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
    , editorSeq = 0
    }


emptyEditor : Markup -> Int -> EditorState
emptyEditor markup seq =
    { editing = Nothing
    , title = ""
    , tags = ""
    , markup = markup
    , body = ""
    , saving = False
    , errorMessage = Nothing
    , showDeleteConfirm = False
    , previewSource = ""
    , previewTick = 0
    , editorKey = "new:" ++ String.fromInt seq
    , initialBody = ""
    , dirty = False
    , autoSaving = False
    , autoSaveTick = 0
    , autoSaveError = Nothing
    , pendingNav = Nothing
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
    , previewSource = s.body
    , previewTick = 0
    , editorKey = "edit:" ++ s.id
    , initialBody = s.body
    , dirty = False
    , autoSaving = False
    , autoSaveTick = 0
    , autoSaveError = Nothing
    , pendingNav = Nothing
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


selectResult : String -> SignedInData -> Model -> ( Model, Cmd Msg )
selectResult sid s model =
    let
        mSnippet =
            List.filter (\x -> x.id == sid) s.results |> List.head
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


{-| If the editor has changes that aren't saved yet (or a save is in
flight), remember where the user wants to go and save first;
AutoSaveResponded performs the navigation once the save succeeds.
Nothing means it's safe to leave right away.
-}
saveBeforeLeaving : SignedInData -> Model -> PendingNav -> Maybe ( Model, Cmd Msg )
saveBeforeLeaving s model nav =
    case s.rightMode of
        EditorMode e ->
            if e.autoSaving then
                -- The in-flight save's response will pick up the navigation.
                Just ( setEditor s model { e | pendingNav = Just nav }, Cmd.none )

            else if e.dirty && not (isBlankNew e) then
                Just (startAutoSave s model { e | pendingNav = Just nav })

            else
                Nothing

        _ ->
            Nothing


performNav : PendingNav -> SignedInData -> Model -> ( Model, Cmd Msg )
performNav nav s model =
    case nav of
        GoToSnippet sid ->
            updateSignedIn (SelectResult sid) s model

        GoToNewSnippet ->
            updateSignedIn NewSnippetPressed s model


setEditor : SignedInData -> Model -> EditorState -> Model
setEditor s model e =
    { model | auth = SignedIn { s | rightMode = EditorMode e } }


{-| Send the editor's current contents to the server (create or update).
-}
startAutoSave : SignedInData -> Model -> EditorState -> ( Model, Cmd Msg )
startAutoSave s model e =
    let
        input =
            { title = e.title, tags = e.tags, markup = e.markup, body = e.body }
    in
    ( setEditor s model { e | autoSaving = True, dirty = False }
    , case e.editing of
        Nothing ->
            Api.createSnippet model.apiBase s.token input AutoSaveResponded

        Just snippet ->
            Api.updateSnippet model.apiBase s.token snippet.id input AutoSaveResponded
    )


closeEditor : SignedInData -> Model -> ( Model, Cmd Msg )
closeEditor s model =
    let
        mSel =
            s.selectedId
                |> Maybe.andThen (\sid -> List.filter (\x -> x.id == sid) s.results |> List.head)
    in
    ( { model | auth = SignedIn { s | rightMode = DisplayMode mSel } }
    , Cmd.none
    )


{-| A new snippet with no title or body yet: nothing worth saving.
-}
isBlankNew : EditorState -> Bool
isBlankNew e =
    e.editing == Nothing && String.isEmpty (String.trim e.title) && String.isEmpty (String.trim e.body)


autoSaveDelay : Float
autoSaveDelay =
    2000


{-| Mark the editor as changed and (re)start the auto-save countdown.
-}
editorChanged : SignedInData -> Model -> (EditorState -> EditorState) -> ( Model, Cmd Msg )
editorChanged s model f =
    case s.rightMode of
        EditorMode e ->
            let
                nextTick =
                    e.autoSaveTick + 1

                newE =
                    f { e | dirty = True, autoSaveTick = nextTick }
            in
            ( { model | auth = SignedIn { s | rightMode = EditorMode newE } }
            , scheduleAutoSave nextTick
            )

        _ ->
            ( model, Cmd.none )


scheduleAutoSave : Int -> Cmd Msg
scheduleAutoSave tick =
    Task.perform (\_ -> AutoSaveTick tick) (Process.sleep autoSaveDelay)


{-| Replace a snippet in the results list, or prepend it if it is new.
-}
upsertResult : Snippet -> List Snippet -> List Snippet
upsertResult snippet results =
    if List.any (\x -> x.id == snippet.id) results then
        List.map (\x -> if x.id == snippet.id then snippet else x) results

    else
        snippet :: results


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
    let
        model =
            { apiBase = flags.apiBase
            , auth = SignedOut (emptyAuthForm LoginMode)
            , currentLanguage =
                flags.initialLanguage
                    |> Maybe.andThen stringToMarkup
                    |> Maybe.withDefault Markdown
            }
    in
    case flags.initialToken of
        Just t ->
            ( model, Api.me flags.apiBase t (TokenValidated t) )

        Nothing ->
            ( model, Cmd.none )



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
            let
                base = { s | results = results }
                newS =
                    case ( s.rightMode, List.head results ) of
                        ( DisplayMode Nothing, Just first ) ->
                            -- Nothing is shown on the right yet; auto-select the
                            -- first result so the user has something to read on
                            -- load, reload, and sign-in.
                            { base
                                | selectedId = Just first.id
                                , rightMode = DisplayMode (Just first)
                            }

                        _ ->
                            base
            in
            ( { model | auth = SignedIn newS }, Cmd.none )

        SearchResponded (Err err) ->
            if isAuthError err then
                forceSignOut model
            else
                ( model, Cmd.none )

        SelectResult sid ->
            case saveBeforeLeaving s model (GoToSnippet sid) of
                Just result ->
                    result

                Nothing ->
                    selectResult sid s model

        NewSnippetPressed ->
            case saveBeforeLeaving s model GoToNewSnippet of
                Just result ->
                    result

                Nothing ->
                    ( { model
                        | auth =
                            SignedIn
                                { s
                                    | rightMode = EditorMode (emptyEditor model.currentLanguage (s.editorSeq + 1))
                                    , editorSeq = s.editorSeq + 1
                                }
                      }
                    , Cmd.none
                    )

        EditPressed snippet ->
            ( { model | auth = SignedIn { s | rightMode = EditorMode (editorFromSnippet snippet) } }
            , Cmd.none
            )

        CancelEditor ->
            case s.rightMode of
                EditorMode e ->
                    if e.dirty && not (isBlankNew e) then
                        -- Flush changes the auto-save hasn't picked up yet.
                        updateSignedIn SaveSnippet s model

                    else
                        closeEditor s model

                _ ->
                    closeEditor s model

        EditorTitleChanged v ->
            editorChanged s model (\e -> { e | title = v })

        EditorTagsChanged v ->
            editorChanged s model (\e -> { e | tags = v })

        EditorMarkupChanged m ->
            let
                ( newModel, cmd ) =
                    editorChanged s model (\e -> { e | markup = m })
            in
            ( { newModel | currentLanguage = m }
            , Cmd.batch [ cmd, saveLanguage (markupToString m) ]
            )

        EditorBodyChanged v ->
            case s.rightMode of
                EditorMode e ->
                    let
                        nextTick =
                            e.previewTick + 1

                        ( newModel, autoSaveCmd ) =
                            editorChanged s model (\e2 -> { e2 | body = v, previewTick = nextTick })
                    in
                    ( newModel
                    , Cmd.batch
                        [ Task.perform (\_ -> PreviewDebounceTick nextTick) (Process.sleep 200)
                        , autoSaveCmd
                        ]
                    )

                _ ->
                    ( model, Cmd.none )

        AutoSaveTick n ->
            case s.rightMode of
                EditorMode e ->
                    if n /= e.autoSaveTick || not e.dirty || e.autoSaving || e.saving || isBlankNew e then
                        -- Stale tick, nothing to save, or a save is already in
                        -- flight (AutoSaveResponded reschedules if still dirty).
                        ( model, Cmd.none )

                    else
                        startAutoSave s model e

                _ ->
                    ( model, Cmd.none )

        AutoSaveResponded (Ok snippet) ->
            let
                newResults =
                    upsertResult snippet s.results
            in
            case s.rightMode of
                EditorMode e ->
                    let
                        nextTick =
                            e.autoSaveTick + 1

                        newE =
                            { e
                                | editing = Just snippet
                                , autoSaving = False
                                , autoSaveError = Nothing
                                , autoSaveTick = nextTick
                            }

                        newS =
                            { s
                                | results = newResults
                                , selectedId = Just snippet.id
                                , rightMode = EditorMode newE
                            }

                        newModel =
                            { model | auth = SignedIn newS }
                    in
                    case ( e.pendingNav, e.dirty ) of
                        ( Just _, True ) ->
                            -- Edited again while saving: save those edits too
                            -- before leaving.
                            startAutoSave newS newModel newE

                        ( Just nav, False ) ->
                            performNav nav newS newModel

                        ( Nothing, True ) ->
                            ( newModel, scheduleAutoSave nextTick )

                        ( Nothing, False ) ->
                            ( newModel, Cmd.none )

                DisplayMode (Just shown) ->
                    -- The editor was closed while the save was in flight.
                    ( { model
                        | auth =
                            SignedIn
                                { s
                                    | results = newResults
                                    , rightMode = DisplayMode (Just (if shown.id == snippet.id then snippet else shown))
                                }
                      }
                    , Cmd.none
                    )

                DisplayMode Nothing ->
                    ( { model | auth = SignedIn { s | results = newResults } }, Cmd.none )

        AutoSaveResponded (Err err) ->
            if isAuthError err then
                forceSignOut model

            else
                mapEditor s
                    model
                    -- Stay in the editor so the error is visible and the
                    -- changes aren't lost.
                    (\e -> { e | autoSaving = False, dirty = True, autoSaveError = Just (httpError err), pendingNav = Nothing })

        PreviewDebounceTick n ->
            case s.rightMode of
                EditorMode e ->
                    if n /= e.previewTick then
                        ( model, Cmd.none )

                    else
                        ( { model | auth = SignedIn { s | rightMode = EditorMode { e | previewSource = e.body } } }
                        , Cmd.none
                        )

                _ ->
                    ( model, Cmd.none )

        ScrollToHeading elementId ->
            ( model, scrollToElement elementId )

        SaveSnippet ->
            case s.rightMode of
                EditorMode e ->
                    let
                        input =
                            { title = e.title, tags = e.tags, markup = e.markup, body = e.body }

                        newE = { e | saving = True, errorMessage = Nothing }
                        newS = { s | rightMode = EditorMode newE }
                    in
                    case e.editing of
                        Nothing ->
                            ( { model | auth = SignedIn newS }
                            , Api.createSnippet model.apiBase s.token input CreateResponded
                            )

                        Just snippet ->
                            ( { model | auth = SignedIn newS }
                            , Api.updateSnippet model.apiBase s.token snippet.id input UpdateResponded
                            )

                _ ->
                    ( model, Cmd.none )

        CreateResponded (Ok snippet) ->
            ( { model
                | auth =
                    SignedIn
                        { s
                            | results = snippet :: s.results
                            , selectedId = Just snippet.id
                            , rightMode = DisplayMode (Just snippet)
                        }
              }
            , Cmd.none
            )

        CreateResponded (Err err) ->
            if isAuthError err then
                forceSignOut model
            else
                ( updateEditorError s model err, Cmd.none )

        UpdateResponded (Ok snippet) ->
            let
                newResults =
                    s.results
                        |> List.map (\x -> if x.id == snippet.id then snippet else x)
            in
            ( { model
                | auth =
                    SignedIn
                        { s
                            | results = newResults
                            , selectedId = Just snippet.id
                            , rightMode = DisplayMode (Just snippet)
                        }
              }
            , Cmd.none
            )

        UpdateResponded (Err err) ->
            if isAuthError err then
                forceSignOut model
            else
                ( updateEditorError s model err, Cmd.none )

        DeletePressed ->
            mapEditor s model (\e -> { e | showDeleteConfirm = True })

        CancelDelete ->
            mapEditor s model (\e -> { e | showDeleteConfirm = False })

        ExportPressed ->
            case s.rightMode of
                EditorMode e ->
                    case e.editing of
                        Just snippet ->
                            ( model
                            , File.Download.string
                                (Export.filename snippet)
                                "text/plain"
                                (Export.body snippet)
                            )

                        Nothing ->
                            ( model, Cmd.none )

                _ ->
                    ( model, Cmd.none )

        ConfirmDelete ->
            case s.rightMode of
                EditorMode e ->
                    case e.editing of
                        Just snippet ->
                            ( { model | auth = SignedIn { s | rightMode = EditorMode { e | saving = True } } }
                            , Api.deleteSnippet model.apiBase s.token snippet.id (DeleteResponded snippet.id)
                            )

                        Nothing ->
                            ( model, Cmd.none )

                _ ->
                    ( model, Cmd.none )

        DeleteResponded sid (Ok ()) ->
            let
                newResults = List.filter (\x -> x.id /= sid) s.results

                ( nextSelected, nextMode ) =
                    case List.head newResults of
                        Just first ->
                            ( Just first.id, DisplayMode (Just first) )
                        Nothing ->
                            ( Nothing, DisplayMode Nothing )
            in
            ( { model
                | auth =
                    SignedIn
                        { s
                            | results = newResults
                            , selectedId = nextSelected
                            , rightMode = nextMode
                        }
              }
            , Cmd.none
            )

        DeleteResponded _ (Err err) ->
            if isAuthError err then
                forceSignOut model
            else
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
        Http.BadStatus 404  -> "Not found"
        Http.BadStatus 409  -> "That email is already registered"
        Http.BadStatus s    -> "Server error (" ++ String.fromInt s ++ ")"
        Http.BadBody _      -> "Unexpected server response"


-- | Is this HTTP error a "your session is over" signal?
isAuthError : Http.Error -> Bool
isAuthError err =
    case err of
        Http.BadStatus 401 -> True
        _ -> False


-- | Transition to signed-out after a 401 mid-session; clear the token too.
forceSignOut : Model -> ( Model, Cmd Msg )
forceSignOut model =
    ( { model | auth = SignedOut (emptyAuthForm LoginMode) }
    , removeToken ()
    )



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
                [ header (Just { email = s.user.email, count = List.length s.results, editable = displayedSnippet s })
                , div [ class "app" ]
                    (div [ class "col-left" ]
                        [ Search.view
                            { searchInput = s.searchInput
                            , results = s.results
                            , selectedId = s.selectedId
                            }
                        ]
                        :: resizer "left"
                        :: viewRight s
                    )
                ]


-- | A drag handle between two columns. app.js does the dragging: it sets
-- a CSS variable that the column's width reads, so re-renders keep it.
resizer : String -> Html Msg
resizer name =
    div [ class "resizer", attribute "data-resize" name, title "Drag to resize; double-click to reset" ] []


viewRight : SignedInData -> List (Html Msg)
viewRight s =
    case s.rightMode of
        DisplayMode Nothing ->
            [ div [ class "col-right" ]
                [ div [ class "display-snippet" ]
                    [ text "Select a snippet on the left, or click \"New snippet\" to create one." ]
                ]
            ]

        DisplayMode (Just snippet) ->
            let
                rendered =
                    Render.renderWithToc snippet.markup snippet.body

                displayColumn =
                    div [ class "col-right" ]
                        [ div [ class "display-snippet" ]
                            [ if Render.hasSourceTitle snippet.markup snippet.body then
                                -- The body's title block shows the title.
                                text ""

                              else
                                div [ class "display-header" ]
                                    [ div [ class "display-title" ]
                                        [ text
                                            (if String.isEmpty snippet.title then
                                                "(untitled)"

                                             else
                                                snippet.title
                                            )
                                        ]
                                    ]
                            , if String.isEmpty snippet.tags then
                                text ""
                              else
                                div [ class "display-tags" ] [ text snippet.tags ]
                            , rendered.body
                            ]
                        ]
            in
            if List.isEmpty rendered.toc then
                [ displayColumn ]

            else
                [ displayColumn
                , resizer "toc"
                , div [ class "col-toc" ] rendered.toc
                ]

        EditorMode e ->
            [ div [ class "col-right" ]
                [ Editor.view e ]
            ]


-- | The snippet shown on the right, if any: the header's Edit button edits it.
displayedSnippet : SignedInData -> Maybe Snippet
displayedSnippet s =
    case s.rightMode of
        DisplayMode snippet ->
            snippet

        EditorMode _ ->
            Nothing


header : Maybe { email : String, count : Int, editable : Maybe Snippet } -> Html Msg
header mInfo =
    div [ class "header" ]
        [ div [ class "header-left" ]
            ([ div [ class "header-title" ] [ text "greppit" ]
             , div [ class "header-version" ] [ text "v1" ]
             ]
                ++ (case mInfo of
                        Just info ->
                            [ div [ class "header-count" ] [ text (snippetCountText info.count) ] ]

                        Nothing ->
                            []
                   )
            )
        , div [ class "header-right" ]
            (case mInfo of
                Just info ->
                    (case info.editable of
                        Just snippet ->
                            [ button [ class "btn btn-secondary", onClick (EditPressed snippet) ]
                                [ text "Edit" ]
                            ]

                        Nothing ->
                            []
                    )
                        ++ [ button [ class "btn btn-primary", onClick NewSnippetPressed ]
                                [ text "New snippet" ]
                           , div [ class "header-email" ] [ text info.email ]
                           , button [ class "btn btn-secondary", onClick SignedOutPressed ]
                                [ text "Sign out" ]
                           ]

                Nothing ->
                    []
            )
        ]


snippetCountText : Int -> String
snippetCountText n =
    String.fromInt n ++ (if n == 1 then " snippet" else " snippets")
