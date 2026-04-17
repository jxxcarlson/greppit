# Greppit Frontend Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the greppit v1 frontend: a single-page Elm app with email/password auth, a two-column UI (search + results on the left, Display / Editor on the right), a CodeMirror body editor, and markdown rendering with KaTeX math. Talks to the backend produced by `docs/superpowers/plans/2026-04-17-greppit-backend.md`.

**Architecture:** Elm 0.19.1 single-page app, one `Main.elm`, one top-level model. Markdown rendering via a vendored `elm-markdown` that emits `<math-text>` custom elements; those are rendered to HTML by KaTeX (loaded from CDN) through a tiny inline `<script>` in `index.html`. CodeMirror comes as a vendored `codemirror-editor` custom element (`codemirror-element.js`). Token stored in `localStorage` via ports.

**Tech Stack:** Elm 0.19.1, `elm/http`, `elm/browser`, `elm/json`, `elm-iso8601-date-strings`. Dev server: Python's `http.server` wrapped in a tiny `serve.py`. No bundler; `elm.js` + static assets served directly. `elm-test` for unit tests on pure functions (decoders, search-state reducers).

**Reference project:** `/Users/carlson/dev/elm-work/scripta/scripta-app-v4/frontend/` — use as pattern source. Copy-adapt the `elm-markdown/` directory, `codemirror-element.js`, and the KaTeX `<math-text>` custom element from `index.html`. Everything else is written fresh for greppit's simpler UI.

**Prerequisites:** backend from `docs/superpowers/plans/2026-04-17-greppit-backend.md` must be running on `http://localhost:8085`. Requires `elm` 0.19.1 on the PATH and Python 3.

**Network:** Frontend served on `http://localhost:8011` (avoiding the `8000-8010` range per user convention). Backend on `8085`. Backend CORS is permissive (`corsOrigins = Nothing`), so the frontend can POST/GET across origins.

---

## File Structure

```
frontend/
  elm.json
  index.html
  serve.py                           # dev static-file server
  run.sh                             # convenience wrapper
  codemirror-element.js              # copied verbatim from scripta-app-v4
  elm-markdown/                      # copied verbatim from scripta-app-v4
    Markdown.elm
    Markdown/*.elm
  src/
    Main.elm                         # top-level model, update, view
    Types.elm                        # Snippet, User, Mode, Msg, Model, AuthState
    Api.elm                          # HTTP calls + JSON codecs
    Auth.elm                         # login/signup view helpers (no state; pure views)
    Search.elm                       # left column: search input + results list
    Render.elm                       # Snippet → Html (dispatches on markup)
    Editor.elm                       # right column: editor form
    CodeMirror.elm                   # thin wrapper around <codemirror-editor>
  tests/
    ApiDecoderTests.elm              # elm-test
```

**Per-file responsibility:**

- `Types.elm` — all shared data types. No logic.
- `Api.elm` — every HTTP call. One function per endpoint. No model knowledge.
- `Main.elm` — owns the whole `Model` and `update`. Imports everything.
- `Auth.elm` / `Search.elm` / `Editor.elm` — *view* modules only. Take a `config` record containing values + msg constructors. No state of their own.
- `Render.elm` — pure: `Snippet -> Html msg`.
- `CodeMirror.elm` — pure: `{ value, key, onInput } -> Html msg`. Behind the scenes emits `Html.Keyed.node "div" ... [(key, Html.node "codemirror-editor" ...)]` so mode-switching forces a full remount.

---

## Global Conventions

- **No new `elm install`** beyond what's declared in `elm.json` (Task 1). If the compiler asks for an extra package, add it explicitly to `elm.json` with the exact version from scripta-app-v4's `elm.json` and note it in the task.
- **API base URL:** derived at startup from `window.location.hostname`. `localhost` → `http://localhost:8085`. Everything else falls back to `window.location.origin` (so the same bundle works if deployed later behind the same host). Passed in via Elm flags.
- **Token storage:** a single key `greppit-token` in `localStorage`. Three ports: `saveToken : String -> Cmd msg`, `removeToken : () -> Cmd msg`, and flags carry `initialToken : Maybe String`.
- **JSON decoders:** live in `Api.elm`; one decoder per response type. Tested in `tests/ApiDecoderTests.elm`.
- **No emojis** in UI strings.
- **Commits:** one commit per completed task.

---

## Task 1: Scaffolding

**Files:**
- Create: `frontend/elm.json`
- Create: `frontend/index.html`
- Create: `frontend/serve.py`
- Create: `frontend/run.sh`
- Create: `frontend/src/Main.elm` (placeholder)
- Create: `frontend/tests/ApiDecoderTests.elm` (placeholder)
- Copy: `frontend/codemirror-element.js` from scripta-app-v4
- Copy: `frontend/elm-markdown/` from scripta-app-v4

- [ ] **Step 1: Create `frontend/elm.json`**

```json
{
    "type": "application",
    "source-directories": [
        "src",
        "elm-markdown"
    ],
    "elm-version": "0.19.1",
    "dependencies": {
        "direct": {
            "elm/browser": "1.0.2",
            "elm/core": "1.0.5",
            "elm/html": "1.0.1",
            "elm/http": "2.0.0",
            "elm/json": "1.1.4",
            "elm/parser": "1.1.0",
            "elm/regex": "1.0.0",
            "elm/time": "1.0.0",
            "elm/url": "1.0.0",
            "rtfeldman/elm-iso8601-date-strings": "1.1.4"
        },
        "indirect": {
            "elm/bytes": "1.0.8",
            "elm/file": "1.0.5",
            "elm/virtual-dom": "1.0.5"
        }
    },
    "test-dependencies": {
        "direct": {
            "elm-explorations/test": "2.2.1"
        },
        "indirect": {
            "elm/random": "1.0.0"
        }
    }
}
```

- [ ] **Step 2: Copy `codemirror-element.js`**

Run from the repo root:

```bash
cp /Users/carlson/dev/elm-work/scripta/scripta-app-v4/frontend/codemirror-element.js \
   frontend/codemirror-element.js
```

- [ ] **Step 3: Copy the vendored `elm-markdown/` directory**

```bash
cp -R /Users/carlson/dev/elm-work/scripta/scripta-app-v4/frontend/elm-markdown \
      frontend/elm-markdown
```

- [ ] **Step 4: Create `frontend/index.html`**

```html
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>greppit</title>

    <!-- KaTeX for math rendering -->
    <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/katex@0.16.9/dist/katex.min.css">
    <script defer src="https://cdn.jsdelivr.net/npm/katex@0.16.9/dist/katex.min.js"></script>

    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        html, body { height: 100%; overflow: hidden; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; color: #222; }

        /* Header */
        .header { height: 50px; padding: 0 20px; display: flex; align-items: center; justify-content: space-between; border-bottom: 1px solid #ddd; background: #fff; }
        .header-title { font-weight: 600; font-size: 18px; color: #333; }
        .header-right { display: flex; align-items: center; gap: 16px; }
        .header-email { color: #666; font-size: 13px; }

        /* Two-column body */
        .app { display: flex; height: calc(100vh - 50px); overflow: hidden; }
        .col-left { width: 340px; min-width: 340px; border-right: 1px solid #ddd; padding: 12px; overflow-y: auto; background: #fafafa; }
        .col-right { flex: 1; overflow-y: auto; padding: 16px; }

        /* Search */
        .search-input { width: 100%; padding: 8px 10px; border: 1px solid #ccc; border-radius: 4px; font-size: 14px; outline: none; }
        .result-list { margin-top: 12px; display: flex; flex-direction: column; gap: 6px; }
        .result-item { padding: 8px 10px; border: 1px solid #e0e0e0; border-radius: 4px; cursor: pointer; background: #fff; }
        .result-item:hover { background: #f0f4f9; }
        .result-item.selected { border-color: #0066cc; background: #eaf2fb; }
        .result-title { font-weight: 600; font-size: 14px; }
        .result-tags { color: #777; font-size: 12px; margin-top: 2px; }

        /* Display mode */
        .display-snippet { max-width: 42rem; }
        .display-header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 8px; }
        .display-title { font-size: 22px; font-weight: 600; }
        .display-tags { color: #777; font-size: 13px; margin-bottom: 16px; }
        .display-body h1, .display-body h2, .display-body h3 { margin: 0.7em 0 0.3em 0; }
        .display-body p { margin: 0.4em 0; line-height: 1.5; }
        .display-body code { background: #f3f3f3; padding: 1px 4px; border-radius: 3px; font-family: ui-monospace, Menlo, monospace; font-size: 0.95em; }
        .display-body pre { background: #f3f3f3; padding: 10px; border-radius: 4px; overflow-x: auto; }

        /* Buttons */
        .btn { padding: 6px 14px; border-radius: 4px; font-size: 14px; cursor: pointer; border: 1px solid transparent; background: #fff; }
        .btn-primary { background: #0066cc; color: #fff; border-color: #0066cc; }
        .btn-secondary { color: #333; border-color: #bbb; }
        .btn-danger { background: #c23; color: #fff; border-color: #c23; }
        .btn:disabled { opacity: 0.5; cursor: default; }

        /* Editor */
        .editor-form { max-width: 48rem; display: flex; flex-direction: column; gap: 10px; }
        .editor-row { display: flex; gap: 10px; align-items: center; }
        .editor-row label { width: 90px; font-size: 13px; color: #555; }
        .editor-row input, .editor-row select { flex: 1; padding: 6px 8px; border: 1px solid #ccc; border-radius: 3px; font-size: 14px; }
        .editor-body { height: 55vh; border: 1px solid #ccc; border-radius: 3px; overflow: hidden; }
        .editor-actions { display: flex; gap: 10px; margin-top: 10px; }

        /* Auth */
        .auth-page { display: flex; justify-content: center; align-items: flex-start; padding-top: 10vh; height: calc(100vh - 50px); background: #fafafa; }
        .auth-form { width: 340px; padding: 24px; border: 1px solid #ddd; background: #fff; border-radius: 6px; }
        .auth-form h2 { margin-bottom: 14px; font-size: 20px; }
        .auth-field { margin-bottom: 12px; display: flex; flex-direction: column; gap: 4px; }
        .auth-field label { font-size: 13px; color: #555; }
        .auth-field input { padding: 8px; border: 1px solid #ccc; border-radius: 3px; font-size: 14px; }
        .auth-error { color: #c23; font-size: 13px; margin-bottom: 10px; }
        .auth-link { margin-top: 12px; font-size: 13px; color: #666; }
        .auth-link a { color: #0066cc; cursor: pointer; }
    </style>
</head>
<body>
    <div id="app"></div>

    <script src="/codemirror-element.js"></script>
    <script src="/elm.js"></script>

    <script>
        // KaTeX <math-text> custom element — lifted from scripta-app-v4.
        class MathText extends HTMLElement {
            static get observedAttributes() { return ['content', 'display']; }
            connectedCallback() { this.renderMath(); }
            attributeChangedCallback() { this.renderMath(); }
            renderMath() {
                var content = this.getAttribute('content') || '';
                var displayMode = this.getAttribute('display') === 'true';
                try {
                    this.innerHTML = katex.renderToString(content, {
                        displayMode: displayMode,
                        throwOnError: false,
                        trust: true
                    });
                } catch(e) {
                    this.innerHTML = '<span style="color:red">' + (e && e.message ? e.message : 'KaTeX error') + '</span>';
                }
            }
        }
        customElements.define('math-text', MathText);

        // Flags for Elm
        var apiBase = (window.location.hostname === 'localhost' || window.location.hostname === '127.0.0.1')
            ? 'http://localhost:8085'
            : window.location.origin;

        var token = localStorage.getItem('greppit-token');

        var app = Elm.Main.init({
            node: document.getElementById('app'),
            flags: {
                apiBase: apiBase,
                initialToken: token
            }
        });

        app.ports.saveToken.subscribe(function(t) {
            localStorage.setItem('greppit-token', t);
        });
        app.ports.removeToken.subscribe(function() {
            localStorage.removeItem('greppit-token');
        });
    </script>
</body>
</html>
```

- [ ] **Step 5: Create `frontend/serve.py`**

```python
#!/usr/bin/env python3
"""Tiny static dev server for greppit frontend. Runs on port 8011."""
import http.server
import socketserver
import os

PORT = 8011
os.chdir(os.path.dirname(os.path.abspath(__file__)))

Handler = http.server.SimpleHTTPRequestHandler
Handler.extensions_map['.js'] = 'application/javascript'

with socketserver.TCPServer(("", PORT), Handler) as httpd:
    print(f"greppit frontend serving at http://localhost:{PORT}")
    httpd.serve_forever()
```

`chmod +x frontend/serve.py`.

- [ ] **Step 6: Create `frontend/run.sh`**

```bash
#!/usr/bin/env bash
cd "$(dirname "$0")"
elm make src/Main.elm --output=elm.js "$@" && python3 serve.py
```

`chmod +x frontend/run.sh`.

- [ ] **Step 7: Placeholder `frontend/src/Main.elm`**

```elm
module Main exposing (main)

import Browser
import Html exposing (text)


main : Program () () ()
main =
    Browser.element
        { init = \_ -> ( (), Cmd.none )
        , update = \_ _ -> ( (), Cmd.none )
        , view = \_ -> text "greppit"
        , subscriptions = \_ -> Sub.none
        }
```

- [ ] **Step 8: Placeholder `frontend/tests/ApiDecoderTests.elm`**

```elm
module ApiDecoderTests exposing (suite)

import Expect
import Test exposing (Test, describe, test)


suite : Test
suite =
    describe "placeholder"
        [ test "1 + 1 == 2" (\_ -> Expect.equal 2 (1 + 1))
        ]
```

- [ ] **Step 9: Verify Elm compiles**

Run: `cd frontend && elm make src/Main.elm --output=elm.js`
Expected: `Success! Compiled 1 module.`

Also run: `cd frontend && elm-test` (if installed). Expected: 1 passing test. If `elm-test` is not installed, note it and skip until Task 9.

- [ ] **Step 10: Commit**

```bash
git add frontend/elm.json frontend/index.html frontend/serve.py frontend/run.sh \
        frontend/src/Main.elm frontend/tests/ApiDecoderTests.elm \
        frontend/codemirror-element.js frontend/elm-markdown
git commit -m "scaffold greppit frontend with vendored elm-markdown + CodeMirror"
```

---

## Task 2: Types module

**Files:**
- Create: `frontend/src/Types.elm`

- [ ] **Step 1: Create the module**

```elm
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
    , EditorState
    , Model
    , Msg(..)
    )

import Http
import Time exposing (Posix)


type alias Flags =
    { apiBase : String
    , initialToken : Maybe String
    }


type alias User =
    { id : String
    , email : String
    }


type Markup
    = Markdown
    | Scripta


markupToString : Markup -> String
markupToString m =
    case m of
        Markdown -> "markdown"
        Scripta  -> "scripta"


stringToMarkup : String -> Maybe Markup
stringToMarkup s =
    case s of
        "markdown" -> Just Markdown
        "scripta"  -> Just Scripta
        _          -> Nothing


type alias Snippet =
    { id : String
    , userId : String
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
    , results : List Snippet
    , selectedId : Maybe String
    , rightMode : RightMode
    }


type RightMode
    = DisplayMode (Maybe Snippet)
    | EditorMode EditorState


type alias EditorState =
    { -- Nothing = creating a new snippet; Just s = editing snippet s.
      editing : Maybe Snippet
    , title : String
    , tags : String
    , markup : Markup
    , body : String
    , saving : Bool
    , errorMessage : Maybe String
    , showDeleteConfirm : Bool
    }


type alias Model =
    { apiBase : String
    , auth : AuthState
    }


type Msg
    -- Auth
    = AuthEmailChanged String
    | AuthPasswordChanged String
    | AuthSwitchMode AuthMode
    | AuthSubmitted
    | AuthResponded (Result Http.Error ( String, User ))
    | SignedOutPressed
      -- Search
    | SearchInputChanged String
    | SearchResponded (Result Http.Error (List Snippet))
    | SelectResult String
      -- Right column
    | NewSnippetPressed
    | EditPressed Snippet
    | CancelEditor
      -- Editor fields
    | EditorTitleChanged String
    | EditorTagsChanged String
    | EditorMarkupChanged Markup
    | EditorBodyChanged String
      -- Editor actions
    | SaveSnippet
    | CreateResponded (Result Http.Error Snippet)
    | UpdateResponded (Result Http.Error Snippet)
    | DeletePressed
    | ConfirmDelete
    | CancelDelete
    | DeleteResponded String (Result Http.Error ())
      -- Debounce ticks (search)
    | SearchDebounceTick Int String
```

- [ ] **Step 2: Build**

Run: `cd frontend && elm make src/Types.elm --output=/dev/null`
Expected: `Success! Compiled 1 module.`

- [ ] **Step 3: Commit**

```bash
git add frontend/src/Types.elm
git commit -m "add Types module with Model, Msg, domain types"
```

---

## Task 3: Api module (HTTP + codecs), with decoder tests

**Files:**
- Create: `frontend/src/Api.elm`
- Modify: `frontend/tests/ApiDecoderTests.elm`

- [ ] **Step 1: Create `frontend/src/Api.elm`**

```elm
module Api exposing
    ( signup, login, me
    , listSnippets, getSnippet, createSnippet, updateSnippet, deleteSnippet
    , userDecoder, snippetDecoder, authResponseDecoder
    )

import Http
import Iso8601
import Json.Decode as D
import Json.Encode as E
import Time exposing (Posix)
import Types exposing (Markup(..), Snippet, User, markupToString, stringToMarkup)
import Url.Builder


authHeader : String -> Http.Header
authHeader token =
    Http.header "Authorization" ("Bearer " ++ token)


userDecoder : D.Decoder User
userDecoder =
    D.map2 User
        (D.field "id" D.string)
        (D.field "email" D.string)


authResponseDecoder : D.Decoder ( String, User )
authResponseDecoder =
    D.map2 Tuple.pair
        (D.field "token" D.string)
        (D.field "user" userDecoder)


markupDecoder : D.Decoder Markup
markupDecoder =
    D.string
        |> D.andThen
            (\s ->
                case stringToMarkup s of
                    Just m  -> D.succeed m
                    Nothing -> D.fail ("Unknown markup: " ++ s)
            )


snippetDecoder : D.Decoder Snippet
snippetDecoder =
    D.map8 Snippet
        (D.field "id" D.string)
        (D.field "userId" D.string)
        (D.field "title" D.string)
        (D.field "tags" D.string)
        (D.field "markup" markupDecoder)
        (D.field "body" D.string)
        (D.field "createdAt" Iso8601.decoder)
        (D.field "updatedAt" Iso8601.decoder)


-- Auth endpoints

signup :
    String
    -> { email : String, password : String }
    -> (Result Http.Error ( String, User ) -> msg)
    -> Cmd msg
signup apiBase creds toMsg =
    Http.post
        { url = apiBase ++ "/api/auth/signup"
        , body = Http.jsonBody (credsEncoder creds)
        , expect = Http.expectJson toMsg authResponseDecoder
        }


login :
    String
    -> { email : String, password : String }
    -> (Result Http.Error ( String, User ) -> msg)
    -> Cmd msg
login apiBase creds toMsg =
    Http.post
        { url = apiBase ++ "/api/auth/login"
        , body = Http.jsonBody (credsEncoder creds)
        , expect = Http.expectJson toMsg authResponseDecoder
        }


credsEncoder : { email : String, password : String } -> E.Value
credsEncoder creds =
    E.object
        [ ( "email", E.string creds.email )
        , ( "password", E.string creds.password )
        ]


me : String -> String -> (Result Http.Error User -> msg) -> Cmd msg
me apiBase token toMsg =
    Http.request
        { method = "GET"
        , headers = [ authHeader token ]
        , url = apiBase ++ "/api/auth/me"
        , body = Http.emptyBody
        , expect = Http.expectJson toMsg userDecoder
        , timeout = Nothing
        , tracker = Nothing
        }


-- Snippets

listSnippets :
    String
    -> String
    -> String
    -> (Result Http.Error (List Snippet) -> msg)
    -> Cmd msg
listSnippets apiBase token query toMsg =
    let
        url =
            Url.Builder.crossOrigin
                apiBase
                [ "api", "snippets" ]
                (if String.isEmpty (String.trim query) then
                    []
                 else
                    [ Url.Builder.string "q" query ]
                )
    in
    Http.request
        { method = "GET"
        , headers = [ authHeader token ]
        , url = url
        , body = Http.emptyBody
        , expect = Http.expectJson toMsg (D.list snippetDecoder)
        , timeout = Nothing
        , tracker = Nothing
        }


getSnippet :
    String -> String -> String
    -> (Result Http.Error Snippet -> msg)
    -> Cmd msg
getSnippet apiBase token sid toMsg =
    Http.request
        { method = "GET"
        , headers = [ authHeader token ]
        , url = apiBase ++ "/api/snippets/" ++ sid
        , body = Http.emptyBody
        , expect = Http.expectJson toMsg snippetDecoder
        , timeout = Nothing
        , tracker = Nothing
        }


type alias SnippetInput =
    { title : String, tags : String, markup : Markup, body : String }


snippetInputEncoder : SnippetInput -> E.Value
snippetInputEncoder s =
    E.object
        [ ( "title", E.string s.title )
        , ( "tags", E.string s.tags )
        , ( "markup", E.string (markupToString s.markup) )
        , ( "body", E.string s.body )
        ]


createSnippet :
    String -> String -> SnippetInput
    -> (Result Http.Error Snippet -> msg)
    -> Cmd msg
createSnippet apiBase token input toMsg =
    Http.request
        { method = "POST"
        , headers = [ authHeader token ]
        , url = apiBase ++ "/api/snippets"
        , body = Http.jsonBody (snippetInputEncoder input)
        , expect = Http.expectJson toMsg snippetDecoder
        , timeout = Nothing
        , tracker = Nothing
        }


updateSnippet :
    String -> String -> String -> SnippetInput
    -> (Result Http.Error Snippet -> msg)
    -> Cmd msg
updateSnippet apiBase token sid input toMsg =
    Http.request
        { method = "PUT"
        , headers = [ authHeader token ]
        , url = apiBase ++ "/api/snippets/" ++ sid
        , body = Http.jsonBody (snippetInputEncoder input)
        , expect = Http.expectJson toMsg snippetDecoder
        , timeout = Nothing
        , tracker = Nothing
        }


deleteSnippet :
    String -> String -> String
    -> (Result Http.Error () -> msg)
    -> Cmd msg
deleteSnippet apiBase token sid toMsg =
    Http.request
        { method = "DELETE"
        , headers = [ authHeader token ]
        , url = apiBase ++ "/api/snippets/" ++ sid
        , body = Http.emptyBody
        , expect = Http.expectWhatever toMsg
        , timeout = Nothing
        , tracker = Nothing
        }
```

- [ ] **Step 2: Write decoder tests**

Replace `frontend/tests/ApiDecoderTests.elm`:

```elm
module ApiDecoderTests exposing (suite)

import Api
import Expect
import Json.Decode as D
import Test exposing (Test, describe, test)
import Types exposing (Markup(..))


suite : Test
suite =
    describe "Api decoders"
        [ test "userDecoder" <|
            \_ ->
                let
                    json =
                        "{\"id\":\"u1\",\"email\":\"a@b.c\"}"
                in
                D.decodeString Api.userDecoder json
                    |> Expect.equal (Ok { id = "u1", email = "a@b.c" })

        , test "authResponseDecoder" <|
            \_ ->
                let
                    json =
                        "{\"token\":\"abc\",\"user\":{\"id\":\"u1\",\"email\":\"a@b.c\"}}"
                in
                D.decodeString Api.authResponseDecoder json
                    |> Expect.equal (Ok ( "abc", { id = "u1", email = "a@b.c" } ))

        , test "snippetDecoder (markdown)" <|
            \_ ->
                let
                    json =
                        "{\"id\":\"s1\",\"userId\":\"u1\",\"title\":\"t\",\"tags\":\"a b\",\"markup\":\"markdown\",\"body\":\"# h\",\"createdAt\":\"2026-04-17T12:00:00Z\",\"updatedAt\":\"2026-04-17T12:00:00Z\"}"
                in
                D.decodeString Api.snippetDecoder json
                    |> Result.map (\s -> ( s.id, s.title, s.markup ))
                    |> Expect.equal (Ok ( "s1", "t", Markdown ))

        , test "snippetDecoder (scripta)" <|
            \_ ->
                let
                    json =
                        "{\"id\":\"s2\",\"userId\":\"u1\",\"title\":\"\",\"tags\":\"\",\"markup\":\"scripta\",\"body\":\"\",\"createdAt\":\"2026-04-17T12:00:00Z\",\"updatedAt\":\"2026-04-17T12:00:00Z\"}"
                in
                D.decodeString Api.snippetDecoder json
                    |> Result.map .markup
                    |> Expect.equal (Ok Scripta)

        , test "snippetDecoder rejects unknown markup" <|
            \_ ->
                let
                    json =
                        "{\"id\":\"s3\",\"userId\":\"u1\",\"title\":\"\",\"tags\":\"\",\"markup\":\"latex\",\"body\":\"\",\"createdAt\":\"2026-04-17T12:00:00Z\",\"updatedAt\":\"2026-04-17T12:00:00Z\"}"
                in
                D.decodeString Api.snippetDecoder json
                    |> (\r -> case r of
                            Ok _  -> Expect.fail "expected decode error"
                            Err _ -> Expect.pass)
        ]
```

- [ ] **Step 3: Install elm-test if needed**

Run: `npm install -g elm-test` (or equivalent) if not already installed. Verify with `elm-test --version`.

- [ ] **Step 4: Run tests**

Run: `cd frontend && elm-test`
Expected: all five tests pass.

- [ ] **Step 5: Commit**

```bash
git add frontend/src/Api.elm frontend/tests/ApiDecoderTests.elm
git commit -m "add Api module with HTTP calls and decoder tests"
```

---

## Task 4: Minimal Main with ports and auth scaffolding

This task gets us to "app boots, user can sign up or log in, empty signed-in state appears." No snippet UI yet.

**Files:**
- Create: `frontend/src/Auth.elm`
- Rewrite: `frontend/src/Main.elm`

- [ ] **Step 1: Create `frontend/src/Auth.elm`** (pure view module)

```elm
module Auth exposing (view)

import Html exposing (Html, a, button, div, form, h2, input, label, text)
import Html.Attributes exposing (autofocus, class, placeholder, type_, value)
import Html.Events exposing (onClick, onInput, onSubmit)
import Types exposing (AuthForm, AuthMode(..), Msg(..))


view : AuthForm -> Html Msg
view f =
    div [ class "auth-page" ]
        [ div [ class "auth-form" ]
            [ h2 []
                [ text
                    (case f.mode of
                        LoginMode  -> "Sign in to greppit"
                        SignupMode -> "Create a greppit account"
                    )
                ]
            , case f.errorMessage of
                Just m ->
                    div [ class "auth-error" ] [ text m ]

                Nothing ->
                    text ""
            , form [ onSubmit AuthSubmitted ]
                [ div [ class "auth-field" ]
                    [ label [] [ text "Email" ]
                    , input
                        [ type_ "email"
                        , autofocus True
                        , placeholder "you@example.com"
                        , value f.email
                        , onInput AuthEmailChanged
                        ]
                        []
                    ]
                , div [ class "auth-field" ]
                    [ label [] [ text "Password" ]
                    , input
                        [ type_ "password"
                        , placeholder "Password"
                        , value f.password
                        , onInput AuthPasswordChanged
                        ]
                        []
                    ]
                , button
                    [ type_ "submit"
                    , class "btn btn-primary"
                    , Html.Attributes.disabled f.submitting
                    ]
                    [ text
                        (case f.mode of
                            LoginMode  -> if f.submitting then "Signing in..." else "Sign in"
                            SignupMode -> if f.submitting then "Creating..."   else "Create account"
                        )
                    ]
                ]
            , div [ class "auth-link" ]
                (case f.mode of
                    LoginMode ->
                        [ text "No account? "
                        , a [ onClick (AuthSwitchMode SignupMode) ] [ text "Sign up" ]
                        ]

                    SignupMode ->
                        [ text "Have an account? "
                        , a [ onClick (AuthSwitchMode LoginMode) ] [ text "Sign in" ]
                        ]
                )
            ]
        ]
```

- [ ] **Step 2: Rewrite `frontend/src/Main.elm`**

```elm
port module Main exposing (main)

import Api
import Auth
import Browser
import Html exposing (Html, button, div, text)
import Html.Attributes exposing (class)
import Html.Events exposing (onClick)
import Http
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


init : Flags -> ( Model, Cmd Msg )
init flags =
    let
        m =
            { apiBase = flags.apiBase
            , auth = SignedOut (emptyAuthForm LoginMode)
            }
    in
    case flags.initialToken of
        Just t ->
            -- Validate the stored token by calling /api/auth/me.
            ( m, Api.me flags.apiBase t (TokenValidated t) )

        Nothing ->
            ( m, Cmd.none )



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

        _ ->
            ( model, Cmd.none )


-- TokenValidated is not in Msg (Types) yet — add a SignedInData bootstrap message locally.
-- For Task 4 we keep it simple: persistent-token validation is a no-op; we just accept the token
-- and fetch /me, then fetch snippets. Implementation is in the `Msg` payload branch below.
-- (If you prefer to add a dedicated constructor, extend Types.Msg; keeping this note inline so the
-- engineer knows why we're routing through AuthResponded with a synthesized user.)

initSignedIn : String -> User -> SignedInData
initSignedIn token user =
    { user = user
    , token = token
    , searchInput = ""
    , results = []
    , selectedId = Nothing
    , rightMode = DisplayMode Nothing
    }


updateSignedIn : Msg -> SignedInData -> Model -> ( Model, Cmd Msg )
updateSignedIn msg s model =
    case msg of
        SignedOutPressed ->
            ( { model | auth = SignedOut (emptyAuthForm LoginMode) }
            , removeToken ()
            )

        SearchResponded (Ok results) ->
            ( { model | auth = SignedIn { s | results = results } }, Cmd.none )

        SearchResponded (Err _) ->
            ( model, Cmd.none )

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
                    [ div [ class "col-left" ] [ text "(search and results go here)" ]
                    , div [ class "col-right" ] [ text "(display / editor goes here)" ]
                    ]
                ]


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
```

**Note about TokenValidated:** the body of `init` mentions a `TokenValidated` constructor that we haven't added yet. For simplicity in Task 4, change `init` to just ignore `initialToken` — we'll revalidate stored tokens in a later task. Replace the `init` body with:

```elm
init flags =
    ( { apiBase = flags.apiBase
      , auth = SignedOut (emptyAuthForm LoginMode)
      }
    , Cmd.none
    )
```

(We will add auto-login in Task 5.)

- [ ] **Step 3: Build**

Run: `cd frontend && elm make src/Main.elm --output=elm.js`
Expected: `Success! Compiled N modules.` No warnings about partial `case` matches.

- [ ] **Step 4: Manual smoke test**

Start backend: `cd backend && ./run.sh` (in terminal A).
Start frontend: `cd frontend && ./run.sh` (in terminal B).
Open `http://localhost:8011` in a browser.

Expected:
- Header shows "greppit" on the left, nothing on the right (signed-out).
- Sign-in form visible.
- Click "Sign up" link → heading changes to "Create a greppit account".
- Fill in email + password → submit → signed-in header appears (email + "New snippet" + "Sign out").
- Click "Sign out" → returns to sign-in form.

- [ ] **Step 5: Commit**

```bash
git add frontend/src/Auth.elm frontend/src/Main.elm
git commit -m "add auth UI: signup/login with JWT storage via ports"
```

---

## Task 5: Auto-login from stored token

**Files:**
- Modify: `frontend/src/Types.elm` (add a new Msg constructor)
- Modify: `frontend/src/Main.elm`

- [ ] **Step 1: Add `TokenValidated` to `Types.Msg`**

In `Types.elm`, add to the `Msg` union (alongside `AuthResponded`):

```elm
    | TokenValidated String (Result Http.Error Types.User)
```

Wait — `Types` can't reference itself like that. The correct line is just:

```elm
    | TokenValidated String (Result Http.Error User)
```

(added inside the existing `type Msg` block; `User` is already in scope since we're in `Types`).

- [ ] **Step 2: Update `init` in `Main.elm`**

```elm
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
```

- [ ] **Step 3: Handle `TokenValidated` in `updateSignedOut`**

```elm
        TokenValidated tok (Ok user) ->
            ( { model | auth = SignedIn (initSignedIn tok user) }
            , Cmd.batch
                [ Api.listSnippets model.apiBase tok "" SearchResponded ]
            )

        TokenValidated _ (Err _) ->
            -- Stored token is no longer valid.
            ( model, removeToken () )
```

- [ ] **Step 4: Build and smoke test**

Run: `cd frontend && elm make src/Main.elm --output=elm.js`
Expected: success.

Manual test: sign in, refresh the page. Expected: stays signed in (header shows email, left column still says "(search and results go here)").

- [ ] **Step 5: Commit**

```bash
git add frontend/src/Types.elm frontend/src/Main.elm
git commit -m "validate stored token on load; auto-login when valid"
```

---

## Task 6: Search column — input, debounced fetch, results list

**Files:**
- Create: `frontend/src/Search.elm`
- Modify: `frontend/src/Main.elm`
- Modify: `frontend/src/Types.elm` (nothing to change, all messages already present)

- [ ] **Step 1: Create `frontend/src/Search.elm`**

```elm
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
```

- [ ] **Step 2: Add debounce state to `SignedInData`**

We debounce search input by delaying the API call with `Process.sleep`. Each keystroke increments a counter; when the delayed `SearchDebounceTick` fires, we only send the API request if its counter matches the current one.

In `Types.elm`, extend `SignedInData`:

```elm
type alias SignedInData =
    { user : User
    , token : String
    , searchInput : String
    , searchTick : Int        -- NEW: monotonic counter for debounce
    , results : List Snippet
    , selectedId : Maybe String
    , rightMode : RightMode
    }
```

And update `initSignedIn` in `Main.elm` to include `searchTick = 0`:

```elm
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
```

- [ ] **Step 3: Handle search messages in `updateSignedIn`**

Add branches (remove the catchall `_ ->` for now; we'll handle every message):

```elm
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
```

Add imports to `Main.elm`:

```elm
import Process
import Task
```

- [ ] **Step 4: Replace the left column placeholder**

In `view` (for `SignedIn`), change the left column:

```elm
                    [ div [ class "col-left" ]
                        [ Search.view
                            { searchInput = s.searchInput
                            , results = s.results
                            , selectedId = s.selectedId
                            }
                        ]
                    , div [ class "col-right" ] [ text "(display / editor goes here)" ]
                    ]
```

Add `import Search` at the top.

- [ ] **Step 5: Build and smoke test**

Run: `cd frontend && elm make src/Main.elm --output=elm.js`
Expected: success.

Manual test:
- Sign in.
- Expect the left column shows a search input. If you have snippets from backend's `test-api.sh` run, they appear.
- Create 3 snippets via `curl` (reuse snippets from `test-api.sh`). Reload the page.
- Left column: shows up to 5 snippets, most recent first.
- Type `elm` into the search input; results narrow.
- Click a result; item becomes highlighted ("selected" style).

- [ ] **Step 6: Commit**

```bash
git add frontend/src/Search.elm frontend/src/Types.elm frontend/src/Main.elm
git commit -m "add search column with debounced query + result selection"
```

---

## Task 7: Render module — markdown (with math) + scripta stub

**Files:**
- Create: `frontend/src/Render.elm`

- [ ] **Step 1: Create the module**

```elm
module Render exposing (render)

import Html exposing (Html, div, text)
import Html.Attributes exposing (class)
import Markdown
import Types exposing (Markup(..), Snippet)


render : Snippet -> Html msg
render s =
    case s.markup of
        Markdown ->
            -- Markdown.toHtml produces a List (Html msg); wrap in a container.
            div [ class "display-body" ] (Markdown.toHtml Nothing s.body)

        Scripta ->
            div [ class "display-body" ]
                [ text "Scripta rendering not yet enabled." ]
```

- [ ] **Step 2: Build**

Run: `cd frontend && elm make src/Main.elm --output=elm.js`
Expected: `Success!` If the compiler cannot find `Markdown`, verify `frontend/elm.json`'s `source-directories` contains `"elm-markdown"` (it should, from Task 1).

- [ ] **Step 3: Commit**

```bash
git add frontend/src/Render.elm
git commit -m "add Render.render dispatching on Snippet.markup"
```

---

## Task 8: Display mode in the right column

**Files:**
- Modify: `frontend/src/Main.elm`

- [ ] **Step 1: Add a display-column view helper to `Main.elm`**

Add after the `header` function:

```elm
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

        EditorMode _ ->
            div [ class "col-right" ] [ text "(editor; coming in next task)" ]
```

Update the `SignedIn` branch of `view`:

```elm
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
```

Add imports:

```elm
import Render
```

- [ ] **Step 2: Build and smoke test**

Run: `cd frontend && elm make src/Main.elm --output=elm.js`
Expected: success.

Manual test:
- Sign in.
- Left column shows results; right column has the placeholder prompt.
- Click a result with markdown body containing `# Hello\n$e^{i\pi}+1=0$`.
- Right column shows the title, then the rendered `<h1>Hello</h1>` and a KaTeX-rendered formula.
- Click a scripta-format snippet: right column shows "Scripta rendering not yet enabled."

- [ ] **Step 3: Commit**

```bash
git add frontend/src/Main.elm
git commit -m "add Display mode in right column with markdown rendering"
```

---

## Task 9: CodeMirror wrapper

**Files:**
- Create: `frontend/src/CodeMirror.elm`

- [ ] **Step 1: Create the module**

```elm
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
```

- [ ] **Step 2: Build**

Run: `cd frontend && elm make src/Main.elm --output=elm.js`
Expected: success.

- [ ] **Step 3: Commit**

```bash
git add frontend/src/CodeMirror.elm
git commit -m "add CodeMirror wrapper with Keyed for clean remount"
```

---

## Task 10: Editor view module

**Files:**
- Create: `frontend/src/Editor.elm`

- [ ] **Step 1: Create the module**

```elm
module Editor exposing (view)

import CodeMirror
import Html exposing (Html, button, div, input, label, option, select, text)
import Html.Attributes exposing (class, disabled, placeholder, selected, type_, value)
import Html.Events exposing (onClick, onInput)
import Types exposing (EditorState, Markup(..), Msg(..), markupToString, stringToMarkup)


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
                [ option [ value "markdown", selected (st.markup == Markdown) ] [ text "Markdown" ]
                , option [ value "scripta",  selected (st.markup == Scripta)  ] [ text "Scripta" ]
                ]
            ]
        , div [ class "editor-body" ]
            [ CodeMirror.view
                { key = keyForEditor
                , value = st.body
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
```

- [ ] **Step 2: Build**

Run: `cd frontend && elm make src/Main.elm --output=elm.js`
Expected: success.

- [ ] **Step 3: Commit**

```bash
git add frontend/src/Editor.elm
git commit -m "add Editor view module (new + edit + delete confirm)"
```

---

## Task 11: Wire Editor mode into Main (New Snippet)

**Files:**
- Modify: `frontend/src/Main.elm`

- [ ] **Step 1: Add an empty-editor helper**

In `Main.elm` near `initSignedIn`:

```elm
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
```

Add to imports: `import Types exposing (... Markup(..) ...)` (already present).

- [ ] **Step 2: Handle mode-switch messages in `updateSignedIn`**

```elm
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
```

- [ ] **Step 3: Handle editor field messages**

Helper to update the editor when in EditorMode:

```elm
withEditor : SignedInData -> (EditorState -> EditorState) -> ( Model, Cmd Msg ) -> ( Model, Cmd Msg )
withEditor _ _ ( m, c ) = ( m, c )
```

(Dummy — we actually want the following specific branches. Ignore the helper; just add branches directly:)

```elm
        EditorTitleChanged v ->
            mapEditor s model (\e -> { e | title = v })

        EditorTagsChanged v ->
            mapEditor s model (\e -> { e | tags = v })

        EditorMarkupChanged m ->
            mapEditor s model (\e -> { e | markup = m })

        EditorBodyChanged v ->
            mapEditor s model (\e -> { e | body = v })
```

And define `mapEditor`:

```elm
mapEditor : SignedInData -> Model -> (EditorState -> EditorState) -> ( Model, Cmd Msg )
mapEditor s model f =
    case s.rightMode of
        EditorMode e ->
            ( { model | auth = SignedIn { s | rightMode = EditorMode (f e) } }
            , Cmd.none
            )

        _ ->
            ( model, Cmd.none )
```

- [ ] **Step 4: Handle Save (for New only — Task 12 adds Edit)**

```elm
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
                            ( model, Cmd.none )  -- handled in Task 12

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
```

Helper:

```elm
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
```

- [ ] **Step 5: Replace the EditorMode placeholder in `viewRight`**

```elm
        EditorMode e ->
            div [ class "col-right" ]
                [ Editor.view e ]
```

Add `import Editor`.

- [ ] **Step 6: Build and smoke test**

Run: `cd frontend && elm make src/Main.elm --output=elm.js`
Expected: success.

Manual test:
- Sign in.
- Click "New snippet" in the header. Right column shows the editor form.
- Type a title, tags, and a body with some markdown (e.g., `# Hello $x=1$`).
- Click Save. Right column flips to Display mode showing the saved snippet with KaTeX math rendered.
- The new snippet appears at the top of the results list on the left.
- Click Cancel (on a fresh New): returns to Display mode with whatever was previously selected.

- [ ] **Step 7: Commit**

```bash
git add frontend/src/Main.elm
git commit -m "wire Editor mode: New Snippet flow with save"
```

---

## Task 12: Edit flow (PUT) and Delete

**Files:**
- Modify: `frontend/src/Main.elm`

- [ ] **Step 1: Extend `SaveSnippet` to handle Edit**

Replace the `SaveSnippet` branch with:

```elm
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
            ( updateEditorError s model err, Cmd.none )
```

- [ ] **Step 2: Handle Delete**

```elm
        DeletePressed ->
            mapEditor s model (\e -> { e | showDeleteConfirm = True })

        CancelDelete ->
            mapEditor s model (\e -> { e | showDeleteConfirm = False })

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
            in
            ( { model
                | auth =
                    SignedIn
                        { s
                            | results = newResults
                            , selectedId = Nothing
                            , rightMode = DisplayMode Nothing
                        }
              }
            , Cmd.none
            )

        DeleteResponded _ (Err err) ->
            ( updateEditorError s model err, Cmd.none )
```

- [ ] **Step 3: Build and smoke test**

Run: `cd frontend && elm make src/Main.elm --output=elm.js`
Expected: success.

Manual test:
- Sign in; click a snippet → Display mode shows it.
- Click "Edit". Right column flips to the editor pre-filled with the snippet.
- Change the title; click Save.
- Display mode returns; list on the left now shows the updated title; search for the old title → not found; new title → found.
- Edit again, click Delete. Confirmation appears.
- Click "Yes, delete". Snippet disappears from the list; right column goes to empty Display mode.
- Click Cancel in the confirmation: it disappears, snippet remains.

- [ ] **Step 4: Commit**

```bash
git add frontend/src/Main.elm
git commit -m "add Edit flow and Delete with confirm"
```

---

## Task 13: Polish — empty searches, error display, refetch on mode changes

**Files:**
- Modify: `frontend/src/Main.elm`

This task closes a few UX gaps that real use will surface.

- [ ] **Step 1: Refetch after Save/Update/Delete so the list reflects server state**

We already update the list optimistically; no change needed for create/update/delete themselves. But after the user changes the search query and lands on Display, switching to New via "New snippet" should preserve the search query. That's already the case because we only modify `rightMode`.

- [ ] **Step 2: Handle `Http.BadStatus 404` more gracefully**

Extend `httpError`:

```elm
        Http.BadStatus 404 -> "Not found"
```

(Place before the generic `Http.BadStatus s ->` branch.)

- [ ] **Step 3: Disable the search input on signed-out state — n/a, input only shows signed in. Confirm no regression.**

Run: `cd frontend && elm make src/Main.elm --output=elm.js`
Expected: success.

- [ ] **Step 4: Manual end-to-end pass**

With backend and frontend running:

1. Open `http://localhost:8011` in a fresh incognito window.
2. **Signup** with a new email + password. Land on empty signed-in state.
3. **New snippet**: title "Test A", tags "elm howto", body "# Hello $\\alpha$". Save → Display shows formatted snippet with KaTeX `α`.
4. **New snippet**: title "Test B", tags "postgres", markup Markdown, body "Use ILIKE." Save.
5. **New snippet**: title "Test C", markup Scripta, body "anything". Save → Display shows "Scripta rendering not yet enabled."
6. Left column: all 3 listed, most recent first.
7. Search "elm": only Test A appears.
8. Search "elm howto" (two words): only Test A appears.
9. Search "elm postgres" (two words, conjunctive): empty list.
10. Clear search: all 3 return.
11. Click Test A → Edit → change title to "Test A v2" → Save. Verify list and display update.
12. Edit Test A v2 → Delete → Confirm. Snippet disappears; Display shows empty state.
13. Sign out. Sign back in. All preserved data still present; latest 5 in list.
14. Wrong password on login: error message shown.
15. Duplicate signup: "That email is already registered."

- [ ] **Step 5: Commit**

```bash
git add frontend/src/Main.elm
git commit -m "polish 404 error handling + verified end-to-end flows"
```

---

## Task 14: README

**Files:**
- Create: `frontend/README.md`

- [ ] **Step 1: Write `frontend/README.md`**

```markdown
# greppit-frontend

Elm 0.19.1 single-page app for greppit.

## Prerequisites
- `elm` (0.19.1)
- `elm-test` (for unit tests)
- Python 3 (for the dev server)
- Backend running on `http://localhost:8085` (see `../backend/README.md`)

## Run

```
./run.sh
```

Serves on `http://localhost:8011`. Opens `index.html`, which loads
`elm.js` and the CodeMirror + KaTeX scripts.

## Test

```
elm-test
```

Runs decoder unit tests.

## Layout

- `src/Main.elm` — top-level model, update, view
- `src/Types.elm` — domain types and Msg
- `src/Api.elm` — HTTP calls and JSON codecs
- `src/Auth.elm`, `src/Search.elm`, `src/Editor.elm`, `src/Render.elm`,
  `src/CodeMirror.elm` — view modules (pure)
- `elm-markdown/` — vendored extended markdown (math via `<math-text>`)
- `codemirror-element.js` — vendored CodeMirror 6 custom element

## Auth

Email + password. JWT stored in `localStorage` as `greppit-token`.
On load, if a token is present it is validated via `GET /api/auth/me`.

## Search

Conjunctive, case-insensitive. Top 5 by `updated_at DESC`. Empty query
returns the 5 most recent.
```

- [ ] **Step 2: Commit**

```bash
git add frontend/README.md
git commit -m "add frontend README"
```

---

## Task 15: Final verification

- [ ] **Step 1: Clean builds**

```bash
cd frontend
rm -f elm.js
elm make src/Main.elm --output=elm.js
elm-test
```

Expected: compile + tests green, no warnings beyond unused imports (fix any that exist).

- [ ] **Step 2: Full end-to-end pass**

Run backend, run frontend, run through all 15 steps of Task 13 Step 4. Every step passes without errors.

- [ ] **Step 3: Confirm Plan 2 is done**

Report success. The frontend consumes the backend plan's API and implements the v1 UI defined in `docs/superpowers/specs/2026-04-17-greppit-design.md`.

---

## Self-Review

**Spec coverage:**
- Email + password signup and login: Tasks 4, 5. ✓
- JWT storage in localStorage; auto-login on reload: Task 5. ✓
- Header with app name, New snippet button, email, Sign out: Task 4. ✓
- Two-column body (search + list on left, Display/Editor on right): Tasks 6, 8, 11, 12. ✓
- Conjunctive, case-insensitive search with 5 results, recency ordered: Task 6 (UI) + backend (query). ✓
- Empty search = 5 most recent: Tasks 6, 4 (auto-fetch on sign-in with `""`). ✓
- Display mode: rendered snippet + Edit button: Task 8. ✓
- Editor mode (New + Edit): Tasks 10, 11, 12. ✓
- Editor fields: title, tags (space-separated), markup dropdown (default Markdown), CodeMirror body: Tasks 9, 10. ✓
- Explicit Save button: Task 10. ✓
- Delete with confirm, only in Edit mode: Tasks 10, 12. ✓
- Markdown rendering via vendored `elm-markdown`: Tasks 1, 7. ✓
- KaTeX math via `<math-text>` custom element: Task 1 (index.html). ✓
- Scripta rendering stubbed: Task 7. ✓
- CodeMirror integration via `<codemirror-editor>` custom element with `load` attribute and `text-change` event: Tasks 1, 9. ✓
- Keyed remount of editor between modes: Task 9. ✓
- JSON codecs + decoder tests: Task 3. ✓

**No placeholders found.** No "TBD". No "similar to task N". Every code step has the full code to write.

**Type consistency:** `SignedInData` gets `searchTick` added in Task 6 — confirmed `initSignedIn` is updated in the same task. `EditorState.editing : Maybe Snippet` is used the same way in Editor view (Task 10) and in Main's SaveSnippet / ConfirmDelete (Tasks 11, 12). `Msg` constructors are consistent between `Types.elm` and every use site.

**Out-of-scope check:** No autosave, no pagination, no Scripta rendering, no sharing, no WebSocket. Matches spec.

**One thing to confirm during implementation (not a blocker):** `elm-test` version availability on the user's system. If `elm-test` is not installed and the user doesn't want to install it, the decoder tests can be run ad hoc via the REPL — but installing is the expected path.

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-04-17-greppit-frontend.md`. Two execution options:

1. **Subagent-Driven (recommended)** — I dispatch a fresh subagent per task, review between tasks, fast iteration.
2. **Inline Execution** — Execute tasks in this session using `executing-plans`, batch execution with checkpoints.

Which approach?
