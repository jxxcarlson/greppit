# Reader-Mode Table of Contents Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show a clickable table of contents on the right in reader mode (Scripta + Markdown) where clicking an entry scrolls the main display to that section.

**Architecture:** Add `Render.renderWithToc` returning `{ body, toc }` — Scripta via the compiler's `output.toc` (with `withTOC True`), Markdown via a custom block renderer that injects heading `id`s plus a TOC built from a pure `markdownHeadings` helper. Clicking a TOC entry sends `ScrollToHeading id`, which a `scrollToElement` port turns into `scrollIntoView`. Reader mode becomes a three-column layout (files | display | TOC).

**Tech Stack:** Elm 0.19.1, vendored `scripta-compiler-v3` and `elm-markdown`, ports + `scrollIntoView`, elm-test.

---

## Reference paths & operational notes

- greppit frontend root: `/Users/carlson/dev/greppit/frontend` (run all commands here unless noted).
- Branch: create and work on `reader-toc` (off `main`).
- **Sandbox:** plain `elm make` works in the sandbox; `git` works. `elm-test` opens a unix socket and fails with `EPERM`/"operation not permitted" under the sandbox — re-run that SAME command with the Bash tool parameter `dangerouslyDisableSandbox: true`. `./scripts/restart.sh` also needs `dangerouslyDisableSandbox: true`.

## Confirmed library facts (do not re-derive)

- `Markdown.Block.parse : Maybe Options -> String -> List (Block b i)`.
- `Markdown.Block.toHtml : Block b i -> List (Html msg)` (a LIST).
- `Markdown.Block` exposes `Block(..)`; the heading constructor is `Heading String Int (List (Inline i))`.
- `Markdown.Inline.toHtml : Inline i -> Html msg` and `Markdown.Inline.extractText : List (Inline i) -> String` (both exposed).
- `Markdown.TableOfContents.headingId : String -> String` lowercases and replaces runs of spaces with `-` (e.g. `"Section A" -> "section-a"`). `getHeading` slugs `Inline.extractText inlines`, so the body heading `id` MUST also be `headingId (Inline.extractText inlines)` to match.
- `Scripta` exposes `Event(..)` (`ClickedId String | ClickedFootnote .. | ClickedCitation .. | ClickedImage .. | ClickedLink .. | HighlightedId ..`), `withTOC : Bool -> Options -> Options`, and `compile`/`mapEvent`. `output.toc` is populated only when `withTOC True`.

## File Structure

- **Modify** `frontend/src/Render.elm` — add `markdownHeadings` (pure, tested) and `renderWithToc`; remove the now-unused `render`.
- **Create** `frontend/tests/MarkdownTocTests.elm` — unit tests for `markdownHeadings`.
- **Modify** `frontend/src/Types.elm` — add `ScrollToHeading String` to `Msg`.
- **Modify** `frontend/src/Main.elm` — add the `scrollToElement` port + handler; change `viewRight` to return `List (Html Msg)` and render the TOC column.
- **Modify** `frontend/index.html` — add the `scrollToElement` port subscription and TOC CSS.

---

## Task 1: Pure `markdownHeadings` helper (testable seam)

**Files:**
- Modify: `frontend/src/Render.elm`
- Create: `frontend/tests/MarkdownTocTests.elm`

- [ ] **Step 1: Write the failing test**

Create `frontend/tests/MarkdownTocTests.elm`:

```elm
module MarkdownTocTests exposing (suite)

import Expect
import Render
import Test exposing (Test, describe, test)


suite : Test
suite =
    describe "Render.markdownHeadings"
        [ test "extracts id, level, and title for each heading in order" <|
            \_ ->
                Render.markdownHeadings "# Hello World\n\nsome text\n\n## Section A"
                    |> Expect.equal
                        [ { id = "hello-world", level = 1, title = "Hello World" }
                        , { id = "section-a", level = 2, title = "Section A" }
                        ]
        , test "returns empty list when there are no headings" <|
            \_ ->
                Render.markdownHeadings "just a paragraph"
                    |> Expect.equal []
        ]
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `elm-test tests/MarkdownTocTests.elm`
Expected: FAIL at compile time — `Render.markdownHeadings` does not exist yet.

- [ ] **Step 3: Replace the contents of `frontend/src/Render.elm`**

```elm
module Render exposing (render, renderBody, markdownHeadings)

import Html exposing (Html, div, text)
import Html.Attributes exposing (class)
import Markdown
import Markdown.Block as Block exposing (Block(..))
import Markdown.Inline as Inline
import Markdown.TableOfContents as TOC
import Scripta
import Types exposing (Markup(..), Msg(..), Snippet)


{-| Render a saved snippet's body for the display pane. -}
render : Snippet -> Html Msg
render s =
    renderBody s.markup s.body


{-| Render an arbitrary body string for a given markup type. Used by the editor
live preview (body only, no TOC). The return type is `Html Msg` because Scripta's
rendered output carries interaction events; here every event maps to `NoOp`.
-}
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


{-| The flat list of Markdown headings in document order, each with the slug id
used both for the rendered heading's `id` attribute and for its TOC link, its
level, and its plain-text title. Slugging goes through `TOC.headingId` applied to
`Inline.extractText`, matching how the TOC link target is computed.
-}
markdownHeadings : String -> List { id : String, level : Int, title : String }
markdownHeadings body =
    headingsFromBlocks (Block.parse Nothing body)


headingsFromBlocks : List (Block b i) -> List { id : String, level : Int, title : String }
headingsFromBlocks blocks =
    List.concatMap headingOf blocks


headingOf : Block b i -> List { id : String, level : Int, title : String }
headingOf block =
    case block of
        Block.Heading _ level inlines ->
            let
                t =
                    Inline.extractText inlines
            in
            [ { id = TOC.headingId t, level = level, title = t } ]

        _ ->
            []
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `elm-test`
Expected: PASS — existing 37 tests plus the 2 new `markdownHeadings` tests (39 total).

Also confirm the app still compiles: `elm make src/Main.elm --output=/dev/null` → `Success!`.

- [ ] **Step 5: Commit**

```bash
git add frontend/src/Render.elm frontend/tests/MarkdownTocTests.elm
git commit -m "feat(reader): add pure markdownHeadings helper

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: Scroll port, message, and handler

Add the `ScrollToHeading` message, the `scrollToElement` outgoing port, its update handler, and the JS subscription. After this task the plumbing exists; nothing emits `ScrollToHeading` yet (Tasks 3–4 do). Verified by compile + tests.

**Files:**
- Modify: `frontend/src/Types.elm`
- Modify: `frontend/src/Main.elm`
- Modify: `frontend/index.html`

- [ ] **Step 1: Add the message to `Msg`**

In `frontend/src/Types.elm`, the `Msg` type currently ends with:

```elm
    | SearchDebounceTick Int String
    | PreviewDebounceTick Int
    | NoOp
```

Replace those three lines with:

```elm
    | SearchDebounceTick Int String
    | PreviewDebounceTick Int
    | ScrollToHeading String
    | NoOp
```

- [ ] **Step 2: Declare the outgoing port in `Main.elm`**

In `frontend/src/Main.elm`, the existing ports near the top are:

```elm
port saveToken : String -> Cmd msg


port removeToken : () -> Cmd msg
```

Add a third port immediately after `removeToken`:

```elm
port saveToken : String -> Cmd msg


port removeToken : () -> Cmd msg


port scrollToElement : String -> Cmd msg
```

- [ ] **Step 3: Handle `ScrollToHeading` in `updateSignedIn`**

In `frontend/src/Main.elm` `updateSignedIn`, find the `PreviewDebounceTick` handler (it ends with its `_ -> ( model, Cmd.none )` branch). Immediately after that whole `PreviewDebounceTick n -> ...` case, add:

```elm
        ScrollToHeading elementId ->
            ( model, scrollToElement elementId )
```

(`ScrollToHeading` is signed-in–only; `updateSignedOut` already has a `_ -> ( model, Cmd.none )` catch-all, so no change is needed there.)

- [ ] **Step 4: Subscribe to the port in `index.html`**

In `frontend/index.html`, the inline init script contains:

```js
        app.ports.saveToken.subscribe(function(t) {
            localStorage.setItem('greppit-token', t);
        });
        app.ports.removeToken.subscribe(function() {
            localStorage.removeItem('greppit-token');
        });
```

Immediately after the `removeToken` subscription, add:

```js
        app.ports.scrollToElement.subscribe(function (id) {
            requestAnimationFrame(function () {
                var el = document.getElementById(id);
                if (el) el.scrollIntoView({ behavior: 'smooth', block: 'start' });
            });
        });
```

- [ ] **Step 5: Verify compile and tests**

Run: `elm make src/Main.elm --output=/dev/null` → expect `Success!`.
Run: `elm-test` → expect 39 passed, 0 failed.

- [ ] **Step 6: Commit**

```bash
git add frontend/src/Types.elm frontend/src/Main.elm frontend/index.html
git commit -m "feat(reader): add scrollToElement port and ScrollToHeading message

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: `Render.renderWithToc`

Add the function that returns both the rendered body and the TOC entry list, for all three markup types. Verified by compile + tests (rendered `Html` is not assertable in Elm; the id logic is already guarded by Task 1's `markdownHeadings` tests).

**Files:**
- Modify: `frontend/src/Render.elm`

- [ ] **Step 1: Replace the contents of `frontend/src/Render.elm`**

```elm
module Render exposing (render, renderBody, renderWithToc, markdownHeadings)

import Html exposing (Html, div, text)
import Html.Attributes exposing (class, id)
import Html.Events exposing (onClick)
import Markdown
import Markdown.Block as Block exposing (Block(..))
import Markdown.Inline as Inline
import Markdown.TableOfContents as TOC
import Scripta
import Types exposing (Markup(..), Msg(..), Snippet)


{-| Render a saved snippet's body for the display pane. -}
render : Snippet -> Html Msg
render s =
    renderBody s.markup s.body


{-| Render an arbitrary body string for a given markup type. Used by the editor
live preview (body only, no TOC). Every Scripta interaction event maps to `NoOp`.
-}
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


{-| Render a body for the reader pane along with a table-of-contents entry list.
Used by reader mode. For Scripta the TOC comes from the compiler (`withTOC True`)
and its `ClickedId` events become `ScrollToHeading`; for Markdown the body's
headings get `id`s and the TOC is built from `markdownHeadings`; PlainText has no
TOC.
-}
renderWithToc : Markup -> String -> { body : Html Msg, toc : List (Html Msg) }
renderWithToc markup body =
    case markup of
        Markdown ->
            let
                blocks =
                    Block.parse Nothing body
            in
            { body = div [ class "display-body" ] (List.concatMap renderMarkdownBlock blocks)
            , toc = List.map tocEntryView (headingsFromBlocks blocks)
            }

        PlainText ->
            { body = div [ class "display-body display-body-plain" ] [ text body ]
            , toc = []
            }

        Scripta ->
            let
                options =
                    Scripta.defaultOptions
                        |> Scripta.withContentWidth 700
                        |> Scripta.withWindowWidth 700
                        |> Scripta.withTOC True

                output =
                    Scripta.compile options body
                        |> Scripta.mapEvent scriptaEventToMsg
            in
            { body = div [ class "display-body" ] (output.title :: output.body)
            , toc = output.toc
            }


scriptaEventToMsg : Scripta.Event -> Msg
scriptaEventToMsg event =
    case event of
        Scripta.ClickedId elementId ->
            ScrollToHeading elementId

        _ ->
            NoOp


renderMarkdownBlock : Block b i -> List (Html Msg)
renderMarkdownBlock block =
    case block of
        Block.Heading _ level inlines ->
            [ Html.node ("h" ++ String.fromInt level)
                [ id (TOC.headingId (Inline.extractText inlines)) ]
                (List.map Inline.toHtml inlines)
            ]

        _ ->
            Block.toHtml block


tocEntryView : { id : String, level : Int, title : String } -> Html Msg
tocEntryView h =
    div
        [ class ("toc-entry toc-level-" ++ String.fromInt h.level)
        , onClick (ScrollToHeading h.id)
        ]
        [ text h.title ]


{-| The flat list of Markdown headings in document order, each with the slug id
used both for the rendered heading's `id` attribute and for its TOC link, its
level, and its plain-text title.
-}
markdownHeadings : String -> List { id : String, level : Int, title : String }
markdownHeadings body =
    headingsFromBlocks (Block.parse Nothing body)


headingsFromBlocks : List (Block b i) -> List { id : String, level : Int, title : String }
headingsFromBlocks blocks =
    List.concatMap headingOf blocks


headingOf : Block b i -> List { id : String, level : Int, title : String }
headingOf block =
    case block of
        Block.Heading _ level inlines ->
            let
                t =
                    Inline.extractText inlines
            in
            [ { id = TOC.headingId t, level = level, title = t } ]

        _ ->
            []
```

- [ ] **Step 2: Verify compile and tests**

Run: `elm make src/Main.elm --output=/dev/null` → expect `Success!`.
Run: `elm-test` → expect 39 passed, 0 failed.

- [ ] **Step 3: Commit**

```bash
git add frontend/src/Render.elm
git commit -m "feat(reader): add renderWithToc for Scripta and Markdown

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: Three-column reader layout

Make `viewRight` return a list of columns and render the TOC column in `DisplayMode (Just snippet)` when there are headings. Wire it to `renderWithToc`, remove the now-unused `render`, and add the CSS.

**Files:**
- Modify: `frontend/src/Main.elm`
- Modify: `frontend/src/Render.elm` (remove `render`)
- Modify: `frontend/index.html` (CSS)

- [ ] **Step 1: Render the app columns from a list**

In `frontend/src/Main.elm` `view`, the `SignedIn s` branch currently builds the app div as:

```elm
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
```

Replace it with (the left column is prepended to the list `viewRight` now returns):

```elm
                , div [ class "app" ]
                    (div [ class "col-left" ]
                        [ Search.view
                            { searchInput = s.searchInput
                            , results = s.results
                            , selectedId = s.selectedId
                            }
                        ]
                        :: viewRight s
                    )
```

- [ ] **Step 2: Change `viewRight` to return a list and render the TOC column**

In `frontend/src/Main.elm`, replace the entire `viewRight` function. The current version is:

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

        EditorMode e ->
            div [ class "col-right" ]
                [ Editor.view e ]
```

Replace it with:

```elm
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
                            , rendered.body
                            ]
                        ]
            in
            if List.isEmpty rendered.toc then
                [ displayColumn ]

            else
                [ displayColumn
                , div [ class "col-toc" ] rendered.toc
                ]

        EditorMode e ->
            [ div [ class "col-right" ]
                [ Editor.view e ]
            ]
```

- [ ] **Step 3: Remove the now-unused `render` from `Render.elm`**

In `frontend/src/Render.elm`, `render` is no longer called (the display view now uses `renderWithToc`). Change the module line from:

```elm
module Render exposing (render, renderBody, renderWithToc, markdownHeadings)
```

to:

```elm
module Render exposing (renderBody, renderWithToc, markdownHeadings)
```

Delete the `render` function and its doc comment:

```elm
{-| Render a saved snippet's body for the display pane. -}
render : Snippet -> Html Msg
render s =
    renderBody s.markup s.body


```

Then remove the now-unused `Snippet` from the Types import. Change:

```elm
import Types exposing (Markup(..), Msg(..), Snippet)
```

to:

```elm
import Types exposing (Markup(..), Msg(..))
```

- [ ] **Step 4: Add the TOC CSS to `index.html`**

In `frontend/index.html`, in the `<style>` block, after the `.display-tags` rule:

```css
        .display-tags { color: #777; font-size: 13px; margin-bottom: 16px; }
```

add:

```css
        .col-toc { width: 240px; min-width: 240px; border-left: 1px solid #ddd; padding: 12px; overflow-y: auto; background: #fafafa; }
        .toc-entry { cursor: pointer; padding: 2px 0; color: #0066cc; font-size: 13px; }
        .toc-entry:hover { text-decoration: underline; }
        .toc-level-2 { padding-left: 12px; }
        .toc-level-3 { padding-left: 24px; }
        .toc-level-4 { padding-left: 36px; }
        .toc-level-5 { padding-left: 48px; }
        .toc-level-6 { padding-left: 60px; }
```

- [ ] **Step 5: Verify compile and tests**

Run: `elm make src/Main.elm --output=/dev/null` → expect `Success!`.
Run: `elm-test` → expect 39 passed, 0 failed.

- [ ] **Step 6: Commit**

```bash
git add frontend/src/Main.elm frontend/src/Render.elm frontend/index.html
git commit -m "feat(reader): three-column layout with clickable TOC

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: End-to-end manual verification

**Files:** none (verification only; commit only if Step 4 requires a fix).

- [ ] **Step 1: Build and start the app (optimized)**

Run from repo root `/Users/carlson/dev/greppit`:

```bash
./scripts/restart.sh --all --opt
```

Expected: backend on `:8085`, frontend on `:8011`, ending with `Open http://localhost:8011`.

- [ ] **Step 2: Verify the Scripta TOC**

At `http://localhost:8011` (hard-refresh), sign in and select a **Scripta** snippet that has sections (use a doc with `| section` headings, or create one). Confirm:
- A TOC column appears on the far right (files | display | TOC).
- TOC entries are clickable and clicking one smoothly scrolls the main display to that section.

- [ ] **Step 3: Verify the Markdown TOC**

Select (or create) a **Markdown** snippet with several `#`/`##`/`###` headings and enough body text to scroll. Confirm the TOC lists the headings (indented by level), and clicking an entry scrolls the display to that heading.

- [ ] **Step 4: Verify the empty/PlainText cases and tune**

Confirm a **Plain text** snippet, and a Markdown/Scripta doc with no headings, show **no** TOC column (the display stays full width). Confirm editor mode is unaffected (no TOC there). Check the browser console for errors.

If the Scripta `output.toc` looks visually heavy in the panel (it carries the compiler's own bordered styling), or the layout has issues (double scrollbars, column widths), adjust the `.col-toc`/`.toc-entry` CSS in `frontend/index.html`. If smooth scrolling does not land correctly, the `.col-right` scroll container or the `scrollIntoView` block option may need tuning. Commit any fix:

```bash
git add -A
git commit -m "fix(reader): tune TOC styling/scroll after manual testing

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

If nothing needs adjustment, note that verification passed and stop here.

---

## Self-Review notes

- **Spec coverage:** three-column reader layout with conditional TOC column (Task 4) ✓; `renderWithToc` for Scripta (`withTOC True` + `ClickedId → ScrollToHeading`) and Markdown (id-injected body + TOC) and PlainText (no TOC) (Task 3) ✓; pure `markdownHeadings` testable seam (Task 1) ✓; `scrollToElement` port + `ScrollToHeading` + JS `scrollIntoView` (Task 2) ✓; manual verification incl. Scripta-toc-styling and empty cases (Task 5) ✓.
- **Id-match correctness:** the spec's flagged risk is resolved — both the Markdown body heading `id` (`renderMarkdownBlock`) and the TOC entry id (`headingOf`) are `TOC.headingId (Inline.extractText inlines)`, the same string `getHeading` uses. `markdownHeadings` (tested in Task 1) shares `headingsFromBlocks`/`headingOf` with the renderer, so the tested ids are the rendered ids.
- **Type consistency:** `renderWithToc : Markup -> String -> { body : Html Msg, toc : List (Html Msg) }`; `markdownHeadings : String -> List { id : String, level : Int, title : String }` (same record shape consumed by `tocEntryView`); `viewRight : SignedInData -> List (Html Msg)` with the single call site updated in `view`; `Msg` gains `ScrollToHeading String`; `port scrollToElement : String -> Cmd msg`. `renderBody` is unchanged and still used by the editor preview.
- **Testing honesty:** only `markdownHeadings` is unit-tested (it returns inspectable records). `renderWithToc`/layout/port produce `Html`/`Cmd` that Elm can't assert, so they are guarded by the compiler, the shared tested helper, and Task 5 manual verification.
```
