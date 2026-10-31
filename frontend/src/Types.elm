module Types exposing
    ( Flags
    , User
    , Snippet
    , Markup(..)
    , markupToString
    , stringToMarkup
    , AuthState(..)
    , AuthMode(..)
    , AuthForm
    , RightMode(..)
    , PendingNav(..)
    , EditorState
    , SignedInData
    , Model
    , Msg(..)
    )

import Http
import Time exposing (Posix)


type alias Flags =
    { apiBase : String
    , initialToken : Maybe String
    , initialLanguage : Maybe String
    }


type alias User =
    { id : String
    , email : String
    }


type Markup
    = Markdown
    | Scripta
    | PlainText


markupToString : Markup -> String
markupToString m =
    case m of
        Markdown  -> "markdown"
        Scripta   -> "scripta"
        PlainText -> "plaintext"


stringToMarkup : String -> Maybe Markup
stringToMarkup s =
    case s of
        "markdown"  -> Just Markdown
        "scripta"   -> Just Scripta
        "plaintext" -> Just PlainText
        _           -> Nothing


type alias Snippet =
    { id : String
    , userId : String
    , zkuId : String
    , title : String
    , tags : String
    , markup : Markup
    , body : String
    , createdAt : Posix
    , updatedAt : Posix
    }


type AuthMode
    = LoginMode
    | SignupMode


type alias AuthForm =
    { mode : AuthMode
    , email : String
    , password : String
    , submitting : Bool
    , errorMessage : Maybe String
    }


type AuthState
    = SignedOut AuthForm
    | SignedIn SignedInData


type alias SignedInData =
    { user : User
    , token : String
    , searchInput : String
    , searchTick : Int
    , results : List Snippet
    , selectedId : Maybe String
    , rightMode : RightMode
    , editorSeq : Int
    }


type RightMode
    = DisplayMode (Maybe Snippet)
    | EditorMode EditorState


{-| Where to go once the editor's pending changes are saved.
-}
type PendingNav
    = GoToSnippet String
    | GoToNewSnippet


type alias EditorState =
    { editing : Maybe Snippet
    , title : String
    , tags : String
    , markup : Markup
    , body : String
    , saving : Bool
    , errorMessage : Maybe String
    , showDeleteConfirm : Bool
    , previewSource : String
    , previewTick : Int
    , editorKey : String
    , initialBody : String
    , dirty : Bool
    , autoSaving : Bool
    , autoSaveTick : Int
    , autoSaveError : Maybe String
    , pendingNav : Maybe PendingNav
    }


type alias Model =
    { apiBase : String
    , auth : AuthState

    -- The markup language for new snippets: the last one the user picked,
    -- remembered in localStorage. Markdown (xmarkdown) the very first time.
    , currentLanguage : Markup
    }


type Msg
    = AuthEmailChanged String
    | AuthPasswordChanged String
    | AuthSwitchMode AuthMode
    | AuthSubmitted
    | AuthResponded (Result Http.Error ( String, User ))
    | TokenValidated String (Result Http.Error User)
    | SignedOutPressed
    | SearchInputChanged String
    | SearchResponded (Result Http.Error (List Snippet))
    | SelectResult String
    | NewSnippetPressed
    | EditPressed Snippet
    | CancelEditor
    | EditorTitleChanged String
    | EditorTagsChanged String
    | EditorMarkupChanged Markup
    | EditorBodyChanged String
    | SaveSnippet
    | CreateResponded (Result Http.Error Snippet)
    | UpdateResponded (Result Http.Error Snippet)
    | DeletePressed
    | ConfirmDelete
    | CancelDelete
    | DeleteResponded String (Result Http.Error ())
    | ExportPressed
    | SearchDebounceTick Int String
    | PreviewDebounceTick Int
    | AutoSaveTick Int
    | AutoSaveResponded (Result Http.Error Snippet)
    | ScrollToHeading String
    | NoOp
