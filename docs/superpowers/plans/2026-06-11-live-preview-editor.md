# Live Preview Editor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a live rendered preview beside the source in a three-column editor (files | source | preview), and adopt the Scripta Demo's CDN-loaded CodeMirror element.

**Architecture:** Extract a `Render.renderBody` used by both the display pane and a new editor preview pane. Debounce the preview off the existing search-debounce pattern. Restructure `Editor.view` into a metadata toolbar over a source|preview split. Swap greppit's inlined CodeMirror bundle for the Demo's ES-module element loaded via an esm.sh import map.

**Tech Stack:** Elm 0.19.1, vendored `scripta-compiler-v3`, CodeMirror 6 (esm.sh CDN), KaTeX, elm-test.

---

## Reference paths

- greppit frontend root: `/Users/carlson/dev/greppit/frontend` (all commands run from here unless noted)
- Demo (source of the CodeMirror element + import map): `/Users/carlson/dev/elm-work/scripta/scripta-compiler-v3/Demo`
- Branch: create and work on `live-preview-editor` (off `main`).

## Operational note (sandbox)

Plain `elm make` works inside the sandbox. `git` works. `elm-test` opens a unix socket and fails under the sandbox with `EPERM`/"operation not permitted" — when you see that, re-run the SAME `elm-test` command with the Bash tool parameter `dangerouslyDisableSandbox: true`. If the running app needs a rebuild, `./scripts/restart.sh --all` (from repo root) also needs `dangerouslyDisableSandbox: true` (it touches Postgres/network).

## File Structure

- **Modify** `frontend/src/Render.elm` — extract `renderBody : Markup -> String -> Html Msg`; `render` delegates to it; expose `renderBody`.
- **Modify** `frontend/src/Types.elm` — add `previewSource`/`previewTick` to `EditorState`; add `PreviewDebounceTick Int` to `Msg`.
- **Modify** `frontend/src/Main.elm` — init the two new fields in `emptyEditor`/`editorFromSnippet`; rewrite `EditorBodyChanged` to debounce; add the `PreviewDebounceTick` handler.
- **Modify** `frontend/src/Editor.elm` — restructure `view` into a toolbar over a source|preview split; render the preview via `Render.renderBody`.
- **Modify** `frontend/index.html` — add editor-split CSS; add the CodeMirror import map; load the element as an ES module.
- **Replace** `frontend/codemirror-element.js` — with the Demo's ES-module version.

---

## Task 1: Extract `Render.renderBody`

A pure refactor: pull the markup `case` out of `render` into a reusable `renderBody markup body`, so the editor preview can render an arbitrary live buffer. Guarded by the existing `tests/ScriptaRenderTests.elm` (which exercises the Scripta path) and the compiler.

**Files:**
- Modify: `frontend/src/Render.elm`

- [ ] **Step 1: Replace the contents of `frontend/src/Render.elm`**

```elm
module Render exposing (render, renderBody)

import Html exposing (Html, div, text)
import Html.Attributes exposing (class)
import Markdown
import Scripta
import Types exposing (Markup(..), Msg(..), Snippet)


{-| Render a saved snippet's body for the display pane. -}
render : Snippet -> Html Msg
render s =
    renderBody s.markup s.body


{-| Render an arbitrary body string for a given markup type. Used by both the
display pane and the editor's live preview. The return type is `Html Msg`
because Scripta's rendered output carries interaction events; for these
read-only views every event is mapped to `NoOp`.
-}
renderBody : Markup -> String -> Html Msg
renderBody markup body =
    case markup of
        Markdown ->
            div [ class "display-body" ] (Markdown.toHtml Nothing body)

        PlainText ->
            -- Preserve line breaks and whitespace; no markdown parsing.
            -- `.display-body-plain` sets `white-space: pre-wrap`.
            div [ class "display-body display-body-plain" ] [ text body ]

        Scripta ->
            let
                options =
                    Scripta.defaultOptions
                        |> Scripta.withContentWidth 700
                        |> Scripta.withWindowWidth 700

                output =
                    Scripta.compile options body
                        |> Scripta.mapEvent (\_ -> NoOp)
            in
            div [ class "display-body" ] (output.title :: output.body)
```

- [ ] **Step 2: Verify compile and tests**

Run: `elm make src/Main.elm --output=/dev/null`
Expected: `Success!`

Run: `elm-test`
Expected: 37 passed, 0 failed. (No new test: `renderBody` returns `Html Msg`, which Elm cannot compare with `==` — its function-containing values crash equality — so there is no assertable unit test beyond the existing Scripta-path guard. The refactor is verified by the compiler and the unchanged 37 tests.)

- [ ] **Step 3: Commit**

```bash
git add frontend/src/Render.elm
git commit -m "refactor(render): extract renderBody for reuse by editor preview

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: Editor state + debounced preview wiring

Add the preview snapshot and debounce counter to `EditorState`, the tick message, and the debounce logic in `update`. After this task the preview snapshot is maintained in the model but not yet displayed (Task 3 shows it). Verified by compile + existing tests.

**Files:**
- Modify: `frontend/src/Types.elm`
- Modify: `frontend/src/Main.elm`

- [ ] **Step 1: Add fields to `EditorState`**

In `frontend/src/Types.elm`, the `EditorState` alias currently ends:

```elm
type alias EditorState =
    { editing : Maybe Snippet
    , title : String
    , tags : String
    , markup : Markup
    , body : String
    , saving : Bool
    , errorMessage : Maybe String
    , showDeleteConfirm : Bool
    }
```

Replace it with (two new fields appended):

```elm
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
    }
```

- [ ] **Step 2: Add the tick message to `Msg`**

In `frontend/src/Types.elm`, the `Msg` type currently ends with:

```elm
    | SearchDebounceTick Int String
    | NoOp
```

Replace those two lines with:

```elm
    | SearchDebounceTick Int String
    | PreviewDebounceTick Int
    | NoOp
```

- [ ] **Step 3: Initialize the new fields in both editor constructors**

In `frontend/src/Main.elm`, `emptyEditor` currently is:

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
```

Replace with:

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
    , previewSource = ""
    , previewTick = 0
    }
```

And `editorFromSnippet` currently is:

```elm
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

Replace with:

```elm
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
    }
```

- [ ] **Step 4: Rewrite `EditorBodyChanged` to debounce, and add `PreviewDebounceTick`**

In `frontend/src/Main.elm` `updateSignedIn`, the current handler is:

```elm
        EditorBodyChanged v ->
            mapEditor s model (\e -> { e | body = v })
```

Replace it with:

```elm
        EditorBodyChanged v ->
            case s.rightMode of
                EditorMode e ->
                    let
                        nextTick =
                            e.previewTick + 1

                        newE =
                            { e | body = v, previewTick = nextTick }
                    in
                    ( { model | auth = SignedIn { s | rightMode = EditorMode newE } }
                    , Task.perform (\_ -> PreviewDebounceTick nextTick) (Process.sleep 200)
                    )

                _ ->
                    ( model, Cmd.none )

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
```

(`Process` and `Task` are already imported in `Main.elm`; this mirrors the existing `SearchDebounceTick` debounce with `Process.sleep 200`.)

- [ ] **Step 5: Verify compile and tests**

Run: `elm make src/Main.elm --output=/dev/null`
Expected: `Success!`

Run: `elm-test`
Expected: 37 passed, 0 failed.

- [ ] **Step 6: Commit**

```bash
git add frontend/src/Types.elm frontend/src/Main.elm
git commit -m "feat(editor): track debounced preview snapshot in editor state

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: Three-column editor layout with live preview

Restructure `Editor.view` into a metadata toolbar over a source|preview split, render the preview via `Render.renderBody`, and add the split CSS. After this task the live preview is visible (still using greppit's existing CodeMirror element; the swap is Task 4).

**Files:**
- Modify: `frontend/src/Editor.elm`
- Modify: `frontend/index.html` (CSS only)

- [ ] **Step 1: Replace the contents of `frontend/src/Editor.elm`**

```elm
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

        keyForEditor =
            case st.editing of
                Just s ->
                    "edit:" ++ s.id

                Nothing ->
                    "new"
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
                            [ class "btn btn-secondary"
                            , onClick ExportPressed
                            , disabled st.saving
                            ]
                            [ text "Export" ]
                        , button
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
        , div [ class "editor-split" ]
            [ div [ class "editor-source" ]
                [ CodeMirror.view
                    { key = keyForEditor
                    , initialValue =
                        case st.editing of
                            Just s ->
                                s.body

                            Nothing ->
                                ""
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
```

- [ ] **Step 2: Update editor CSS in `frontend/index.html`**

In the `<style>` block, replace this rule:

```css
        .editor-form { max-width: 48rem; display: flex; flex-direction: column; gap: 10px; }
```

with:

```css
        .editor-form { height: 100%; display: flex; flex-direction: column; gap: 10px; }
        .editor-split { flex: 1; display: flex; gap: 12px; min-height: 0; }
        .editor-source { flex: 1; min-width: 0; border: 1px solid #ccc; border-radius: 3px; overflow: hidden; display: flex; flex-direction: column; }
        .editor-source > div { flex: 1; min-height: 0; display: flex; flex-direction: column; }
        .editor-source codemirror-editor { flex: 1; min-height: 0; display: block; overflow: hidden; }
        .editor-preview { flex: 1; min-width: 0; overflow-y: auto; padding: 12px; border: 1px solid #e5e7eb; border-radius: 3px; }
```

Then delete the now-unused old `.editor-body` rules (the source pane uses `.editor-source` now):

```css
        .editor-body {
            height: 55vh;
            border: 1px solid #ccc;
            border-radius: 3px;
            overflow: hidden;
            display: flex;
            flex-direction: column;
        }
        /* CodeMirror.elm wraps <codemirror-editor> in a keyed <div>.
           Both wrapper and host become flex items so CM6's internal
           flex layout has a concrete vertical height to fill. */
        .editor-body > div {
            flex: 1;
            min-height: 0;
            display: flex;
            flex-direction: column;
        }
        .editor-body codemirror-editor {
            flex: 1;
            min-height: 0;
            display: block;
            overflow: hidden;
        }
```

- [ ] **Step 3: Verify compile and tests**

Run: `elm make src/Main.elm --output=/dev/null`
Expected: `Success!`

Run: `elm-test`
Expected: 37 passed, 0 failed.

- [ ] **Step 4: Commit**

```bash
git add frontend/src/Editor.elm frontend/index.html
git commit -m "feat(editor): three-column layout with live preview pane

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: Swap to the Demo's CodeMirror element

Replace greppit's inlined CodeMirror bundle with the Demo's ES-module element and load CodeMirror from the esm.sh CDN via an import map. Verified by compile; runtime behavior is checked in Task 5.

**Files:**
- Replace: `frontend/codemirror-element.js`
- Modify: `frontend/index.html`

- [ ] **Step 1: Vendor the Demo's element**

Run (from `frontend/`):

```bash
cp /Users/carlson/dev/elm-work/scripta/scripta-compiler-v3/Demo/codemirror-element.js codemirror-element.js
```

Verify it is the small ES-module version:

```bash
head -20 codemirror-element.js
wc -l codemirror-element.js
```

Expected: a leading block comment "CodeMirror 6 custom element for Scripta Demo", `import { ... } from '@codemirror/view';` near the top, ~566 lines.

- [ ] **Step 2: Add the CodeMirror import map to `<head>`**

In `frontend/index.html`, find the KaTeX CSS line in `<head>`:

```html
    <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/katex@0.16.9/dist/katex.min.css">
```

Immediately after it, add:

```html

    <!-- Import map so all CodeMirror packages share one @codemirror/state instance -->
    <script type="importmap">
    {
        "imports": {
            "@codemirror/state": "https://esm.sh/@codemirror/state@6.4.1",
            "@codemirror/view": "https://esm.sh/@codemirror/view@6.26.0?external=@codemirror/state",
            "@codemirror/commands": "https://esm.sh/@codemirror/commands@6.3.3?external=@codemirror/state,@codemirror/view,@codemirror/language",
            "@codemirror/autocomplete": "https://esm.sh/@codemirror/autocomplete@6.15.0?external=@codemirror/state,@codemirror/view,@codemirror/language,@lezer/common",
            "@codemirror/language": "https://esm.sh/@codemirror/language@6.10.1?external=@codemirror/state,@codemirror/view,@lezer/common,@lezer/highlight,@lezer/lr",
            "@codemirror/search": "https://esm.sh/@codemirror/search@6.5.6?external=@codemirror/state,@codemirror/view",
            "@codemirror/lint": "https://esm.sh/@codemirror/lint@6.5.0?external=@codemirror/state,@codemirror/view",
            "@lezer/common": "https://esm.sh/@lezer/common@1.2.1",
            "@lezer/highlight": "https://esm.sh/@lezer/highlight@1.2.0?external=@lezer/common",
            "@lezer/lr": "https://esm.sh/@lezer/lr@1.4.0?external=@lezer/common",
            "codemirror": "https://esm.sh/codemirror@6.0.1?external=@codemirror/state,@codemirror/view,@codemirror/commands,@codemirror/autocomplete,@codemirror/language,@codemirror/search,@codemirror/lint"
        }
    }
    </script>
```

- [ ] **Step 3: Load the element as a module**

In `frontend/index.html` `<body>`, the current tag is:

```html
    <script src="/codemirror-element.js"></script>
```

Replace it with:

```html
    <script type="module" src="/codemirror-element.js"></script>
```

(The import map in `<head>` precedes this module script, as required. The element upgrades the `<codemirror-editor>` nodes Elm renders once the module loads.)

- [ ] **Step 4: Verify the app compiles**

Run: `elm make src/Main.elm --output=/dev/null`
Expected: `Success!` (this task changes only static JS/HTML; runtime is verified in Task 5).

- [ ] **Step 5: Commit**

```bash
git add frontend/codemirror-element.js frontend/index.html
git commit -m "feat(editor): adopt the Demo's CDN-loaded CodeMirror element

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: End-to-end manual verification

**Files:** none (verification only; commit only if Step 4 requires a fix).

- [ ] **Step 1: Build and start the app**

Run from repo root `/Users/carlson/dev/greppit`:

```bash
./scripts/restart.sh --all
```

Expected: backend on `:8085`, frontend on `:8011`, ending with `Open http://localhost:8011`.

- [ ] **Step 2: Verify the editor and live preview**

At `http://localhost:8011`, sign in and edit (or create) a snippet with Markup = **Scripta**. Confirm:
- The right side shows the source editor (CodeMirror) and a preview pane side by side, with the title/tags/markup/buttons toolbar above.
- Typing in the source updates the preview ~200ms after you pause (not on every keystroke).
- Inline and display math render in the preview via KaTeX.
- Switching the Markup dropdown (Scripta / Markdown / Plain text) changes how the preview renders.
- Typing quickly in a long document stays responsive.
- The CodeMirror editor still loads and edits normally after the element swap (check the browser console for errors loading from esm.sh or about the `codemirror-editor` element). In particular, verify the empty-initial-value case: open **New snippet**, type into the empty editor, and confirm the first keystrokes are not swallowed.

- [ ] **Step 3: Confirm display mode still works**

Save the snippet and select it in the list; confirm the display pane still renders correctly (the `render`/`renderBody` refactor did not regress it).

- [ ] **Step 4: Tune if needed**

If the layout is off (double scrollbars, panes not filling height), adjust the `.editor-*` CSS in `frontend/index.html`. If the preview feels laggy or too eager, adjust the `Process.sleep 200` interval in `Main.elm`'s `EditorBodyChanged`. If the empty-initial-value case swallows input, re-check `frontend/src/CodeMirror.elm`'s conditional `load` workaround against the new element. Commit any fix:

```bash
git add -A
git commit -m "fix(editor): tune live-preview layout/debounce after manual testing

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

If nothing needs adjustment, note that verification passed and stop here.

---

## Self-Review notes

- **Spec coverage:** three-column layout (Task 3) ✓; CodeMirror element swap + import map (Task 4) ✓; reuse rendering via `renderBody` (Task 1) ✓; debounced preview with `previewSource`/`previewTick`/`PreviewDebounceTick` (Task 2) ✓; manual verification incl. CSS/debounce tuning and empty-initial-value re-check (Task 5) ✓. All-three-markup-types preview is covered by `renderBody`'s existing `case`.
- **Type consistency:** `render : Snippet -> Html Msg` and `renderBody : Markup -> String -> Html Msg`; `EditorState` gains `previewSource : String` and `previewTick : Int`; `Msg` gains `PreviewDebounceTick Int`; `EditorBodyChanged` and `PreviewDebounceTick` both pattern-match `s.rightMode`/`EditorMode e` and write back `EditorMode { e | ... }`. `Editor.view` reads `st.previewSource`/`st.markup` and calls `Render.renderBody`. Consistent across tasks.
- **Testing honesty:** `renderBody` returns `Html Msg`, which cannot be asserted with `Expect.equal` (Elm `==` crashes on function-bearing values), so Tasks 1–4 are guarded by the compiler + the existing 37 tests, and Task 5 is manual. No fabricated/un-assertable tests.
