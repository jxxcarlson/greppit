# Live Preview Editor (Sub-Project 1)

**Date:** 2026-06-11
**Status:** Approved (design)
**Scope:** Live rendered preview in a three-column editor, plus adopting the Demo's CodeMirror element. Editor↔render synchronization is explicitly a separate sub-project.

## Goal

When editing a snippet, show a live-rendered preview beside the source that
updates as the user types. Adopt the Scripta Demo's CodeMirror custom element
(the sync-capable one) so a later sub-project can add bidirectional
editor↔render sync with minimal additional change.

## Background

greppit's editor today is a single source pane. `Editor.view` renders a
stacked form (title, tags, markup dropdown, a `CodeMirror.view` body, and action
buttons). Rendering only happens in display mode, after save, via
`Render.render`. greppit's current `frontend/codemirror-element.js` is a ~27k-line
self-contained CodeMirror 6 bundle that emits `text-change` events.

The Demo (`/Users/carlson/dev/elm-work/scripta/scripta-compiler-v3/Demo`) uses a
566-line `codemirror-element.js` that is an ES module importing CodeMirror from
the esm.sh CDN via an import map. It emits the same `text-change {position,
source}` event greppit already decodes, accepts a `load` attribute, and adds
sync capabilities (`sync-to-rendered`, `editor-ready`, a `selection` attribute,
a `setSyncHighlight` effect) that this sub-project leaves unused.

## Non-Goals (deferred to Sub-Project 2)

- Click an element in the preview → highlight/scroll its source.
- Move the cursor/selection in source → scroll the preview to match.
- Scroll synchronization between panes.
- Incremental `Scripta.reparse` (this sub-project re-compiles from source).
- Theme switching, multiple documents, import/export wiring from the Demo.

## Architecture

### 1. Three-column layout

In `EditorMode`, the right column (`.col-right`) contains:

- A **metadata toolbar**: title input, tags input, markup `select`, and the
  action buttons (Save / Cancel / Export / Delete), plus the error message and
  delete-confirm UI that exist today.
- A **horizontal split** below the toolbar: the CodeMirror **source** pane on
  the left and the rendered **preview** pane on the right, each taking half the
  width and scrolling independently.

Display mode (viewing a saved snippet) is unchanged — still a single rendered
column.

New CSS in `frontend/index.html`:

- `.editor-split` — `display:flex; flex:1; min-height:0;` (the source|preview row)
- `.editor-source` — `flex:1; min-width:0;` wrapper around the CodeMirror host
- `.editor-preview` — `flex:1; min-width:0; overflow-y:auto; padding:…;` the
  rendered output, reusing the existing `.display-body` styles for content

`.editor-form` / `.editor-body` rules are adjusted so the form lays out as
toolbar-over-split rather than a single vertical stack.

### 2. CodeMirror element swap

- Replace `frontend/codemirror-element.js` with the Demo's ES-module version
  (copied verbatim from the Demo).
- Add the CodeMirror import map to `frontend/index.html` (the esm.sh URLs from
  the Demo's `index.html`), and load the element with
  `<script type="module" src="/codemirror-element.js"></script>`. This mirrors
  the existing KaTeX-from-CDN approach.
- `frontend/src/CodeMirror.elm` keeps its current interface (`key`,
  `initialValue` via the `load` attribute, `onInput` from `text-change`'s
  `detail.source`). The empty-initial-value workaround (omit `load` when the
  initial value is empty) is retained; verify it is still needed against the
  Demo element and keep or drop accordingly.

### 3. Live render — reuse existing rendering

Refactor `frontend/src/Render.elm`:

```elm
render : Snippet -> Html Msg
render s =
    renderBody s.markup s.body


renderBody : Markup -> String -> Html Msg
renderBody markup body =
    case markup of
        Markdown ->
            div [ class "display-body" ] (Markdown.toHtml Nothing body)

        PlainText ->
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

`render` keeps its existing call site behavior; the preview pane calls
`Render.renderBody st.markup st.previewSource`. `renderBody` is added to the
module's exposing list. All three markup types render with no Scripta-only
special-casing.

### 4. Debounced preview

Add two fields to `EditorState` in `frontend/src/Types.elm`:

- `previewSource : String` — the snapshot the preview renders from.
- `previewTick : Int` — debounce generation counter.

Add a message `PreviewDebounceTick Int` to `Msg`.

In `Main.elm` `updateSignedIn`, change the `EditorBodyChanged` handler so it,
in addition to updating `body`, bumps `previewTick` and schedules a tick:

```elm
EditorBodyChanged v ->
    case s.rightMode of
        EditorMode e ->
            let
                nextTick = e.previewTick + 1
                newE = { e | body = v, previewTick = nextTick }
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

This mirrors the existing search debounce (`SearchDebounceTick`, `Process.sleep
200`). The preview lags typing by ~200ms and avoids recompiling Scripta on every
keystroke.

Wherever an `EditorState` is constructed (opening New, opening Edit, and after a
successful create/update that keeps the editor open), initialize
`previewSource` to the starting body and `previewTick` to `0`. The exact
mapEditor / initialization helper used in `Main.elm` is followed so the live
buffer and the preview start in sync.

## Data Flow

```
keystroke
  -> codemirror-editor "text-change" {detail:{source}}
  -> CodeMirror.elm decodes -> EditorBodyChanged v
  -> body := v, previewTick := n+1, schedule Process.sleep 200 -> PreviewDebounceTick (n+1)
  -> (200ms, if still latest tick) previewSource := body
  -> Editor preview view: Render.renderBody markup previewSource
  -> math-text nodes rendered by KaTeX
```

## Error Handling

No new error paths. The Scripta compiler renders malformed input inline; KaTeX
errors are surfaced inline by the `math-text` element. If the esm.sh CDN is
unreachable, the CodeMirror editor will not load — same failure class as the
existing KaTeX CDN dependency.

## Testing & Verification

- `elm make src/Main.elm` compiles cleanly.
- `elm-test` — existing 37 tests stay green; add tests asserting
  `Render.renderBody` returns non-empty output for `Markdown`, `PlainText`, and
  `Scripta` inputs (extending `tests/ScriptaRenderTests.elm` or a sibling file).
- Manual: open the editor on a Scripta snippet; confirm the preview renders
  beside the source and updates ~200ms after typing, including KaTeX math; change
  the Markup dropdown and confirm the preview switches renderer; type quickly in
  a long document and confirm the editor stays responsive.
- Run with `./scripts/restart.sh` and eyeball the three-column layout.

## Risks

- The editor now requires network access for CodeMirror (esm.sh), consistent
  with the existing KaTeX CDN dependency. Offline vendoring of CodeMirror is out
  of scope.
- The Demo's element may differ from greppit's around the `load`/programmatic-update
  handling; the `CodeMirror.elm` empty-initial-value workaround must be
  re-verified after the swap.
- The 200ms debounce interval may need tuning after manual testing.
