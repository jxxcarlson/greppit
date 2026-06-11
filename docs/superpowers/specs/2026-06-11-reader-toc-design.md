# Reader-Mode Table of Contents (Click-to-Scroll)

**Date:** 2026-06-11
**Status:** Approved (design)
**Scope:** A clickable, scroll-on-click table of contents shown on the right in reader mode, for Scripta and Markdown snippets. Scroll-spy (active-section highlighting) is a separate follow-up spec.

## Goal

When greppit is in reader mode (a snippet is displayed, no editor open), show a
table of contents on the right-hand side listing the document's section
headings. Clicking an entry scrolls the main display to that section.

## Background

- Reader mode is `viewRight`'s `DisplayMode (Just snippet)` branch in
  `frontend/src/Main.elm`: a single `.col-right` column containing the title,
  tags, and `Render.render snippet`. The app is `div.app [ col-left, viewRight s ]`.
- `Render.renderBody : Markup -> String -> Html Msg` renders a body for the three
  markup types; the editor live-preview added in the previous sub-project uses it.
- The vendored Scripta compiler's `Scripta.compile`/`render` returns
  `Output = { title, body, toc, banner }`. The `toc` field is populated only when
  `Scripta.withTOC True` is set (`scripta/V3/Compiler.elm:64`). TOC entries emit
  `ClickedId String` events; rendered body sections already carry `HA.id`.
- The vendored `Markdown.TableOfContents` exposes `fromBlocks : List (Block b i)
  -> List ToCItem`, `headingId : String -> String`, plus `level`/`heading`
  accessors. `Markdown.Block` exposes `Block(..)` (incl. `Heading String Int
  (List (Inline i))`) and `parse`/`toHtml`; `Markdown.Inline` exposes
  `toHtml : Inline i -> Html msg`. Default Markdown rendering does NOT add heading
  `id`s, so they must be injected.

## Non-Goals (deferred to the scroll-spy spec)

- Highlighting the section currently in view as the user scrolls (scroll-spy).
- A `Scripta.Document.sections` query and a uniform greppit-rendered TOC across
  both markup types (the scroll-spy spec needs these to highlight Scripta TOC
  entries, which this spec renders via the compiler's opaque `output.toc`).
- TOC for PlainText (it has no headings).
- Internal document links, footnotes, citations (Scripta `ClickedLink` etc.).

## Architecture

### 1. Three-column reader layout

Change `viewRight : SignedInData -> List (Html Msg)` (returns the right-hand
columns), and in `view` render the app as:

```elm
div [ class "app" ] (div [ class "col-left" ] [ Search.view {...} ] :: viewRight s)
```

`viewRight` branches:

- `DisplayMode Nothing` → `[ div [ class "col-right" ] [ placeholder ] ]`
- `DisplayMode (Just snippet)` → compute
  `rendered = Render.renderWithToc snippet.markup snippet.body`, then return the
  display column (title, tags, `rendered.body`) plus, **only when
  `rendered.toc` is non-empty**, a TOC column:
  `div [ class "col-toc" ] rendered.toc`. When `rendered.toc` is empty, return
  just `[ displayColumn ]` so the display keeps full width (today's behavior).
- `EditorMode e` → `[ div [ class "col-right" ] [ Editor.view e ] ]` (unchanged).

New CSS in `frontend/index.html`:

```css
.col-toc { width: 240px; min-width: 240px; border-left: 1px solid #ddd; padding: 12px; overflow-y: auto; background: #fafafa; }
.toc-entry { cursor: pointer; padding: 2px 0; color: #0066cc; font-size: 13px; }
.toc-entry:hover { text-decoration: underline; }
.toc-level-2 { padding-left: 12px; }
.toc-level-3 { padding-left: 24px; }
.toc-level-4 { padding-left: 36px; }
```

### 2. `Render.renderWithToc`

Add to `frontend/src/Render.elm`:

```elm
renderWithToc : Markup -> String -> { body : Html Msg, toc : List (Html Msg) }
```

- **Scripta:** build options with `... |> Scripta.withTOC True`, then
  `output = Scripta.compile options body |> Scripta.mapEvent scriptaEventToMsg`,
  returning `{ body = div [ class "display-body" ] (output.title :: output.body)
  , toc = output.toc }`. `scriptaEventToMsg : Scripta.Event -> Msg` maps
  `ClickedId id -> ScrollToHeading id` and every other event to `NoOp`.
- **Markdown:** `blocks = Markdown.Block.parse Nothing body`. Render the body as
  `div [ class "display-body" ] (List.map renderMarkdownBlock blocks)` where
  `renderMarkdownBlock` pattern-matches `Block.Heading raw level inlines` and
  renders `Html.node ("h" ++ String.fromInt level)
  [ Html.Attributes.id (Markdown.TableOfContents.headingId raw) ]
  (List.map Markdown.Inline.toHtml inlines)`, delegating all other blocks to
  `Markdown.Block.toHtml`. Build the TOC from the pure `markdownHeadings` helper
  (below): `toc = List.map tocEntryView (markdownHeadings body)`, where
  `tocEntryView { id, level, title } = div [ class ("toc-entry toc-level-" ++
  String.fromInt level), onClick (ScrollToHeading id) ] [ text title ]`.
- **PlainText:** `{ body = div [ class "display-body display-body-plain" ]
  [ text body ], toc = [] }`.

Keep `renderBody : Markup -> String -> Html Msg` unchanged (used by the editor
preview; no TOC, Scripta `withTOC` left off so preview performance is unaffected).
Replace the old `render : Snippet -> Html Msg` usage at the display call site with
`renderWithToc`. Expose `renderWithToc` and `markdownHeadings`.

### 3. Pure heading helper (testable seam)

```elm
markdownHeadings : String -> List { id : String, level : Int, title : String }
```

Implementation: parse the markdown to blocks, extract `Heading raw level _`
blocks (in document order, all levels), and map each to
`{ id = Markdown.TableOfContents.headingId raw, level = level, title = raw }`.
Both the TOC entries and the body's injected heading `id`s derive ids through
`Markdown.TableOfContents.headingId`, so a TOC link's target always exists in the
body. (During implementation, confirm `TableOfContents.fromBlocks`/`getHeading`
slug the same raw string this helper uses; if they diverge, prefer this helper as
the single source of truth for both the body id and the TOC.)

### 4. Scroll wiring

- Add an outgoing port to `frontend/src/Main.elm`:
  `port scrollToElement : String -> Cmd msg`.
- Add `ScrollToHeading String` to `Msg` in `frontend/src/Types.elm`; handle it in
  `updateSignedIn` (and it falls through `updateSignedOut`'s catch-all):
  `ScrollToHeading id -> ( model, scrollToElement id )`.
- In `frontend/index.html`, in the inline init script after `Elm.Main.init`, add:

```js
app.ports.scrollToElement.subscribe(function (id) {
    requestAnimationFrame(function () {
        var el = document.getElementById(id);
        if (el) el.scrollIntoView({ behavior: 'smooth', block: 'start' });
    });
});
```

The display column (`.col-right`, `overflow-y: auto`) is the scroll container, so
`scrollIntoView` scrolls it to the targeted section.

## Data Flow

```
click TOC entry
  -> ScrollToHeading id
  -> ( model, scrollToElement id )      -- port command
  -> JS: requestAnimationFrame -> getElementById(id).scrollIntoView(smooth)
  -> the .col-right display column scrolls to the section with that id
```

For Scripta, the TOC entry's `ClickedId id` is mapped to `ScrollToHeading id` by
`scriptaEventToMsg`; for Markdown, the entry has `onClick (ScrollToHeading id)`
directly.

## Error Handling

If a TOC id has no matching element (should not happen given shared `headingId`),
`getElementById` returns null and the JS handler no-ops. No Elm-side error path.

## Testing & Verification

- `elm make src/Main.elm` compiles cleanly.
- `elm-test` — existing 37 tests stay green; add unit tests for `markdownHeadings`
  covering: heading text → slug (lowercase, spaces → dashes), level capture, and
  document order, for a multi-heading sample.
- Manual: in reader mode, open a Scripta document with sections and a Markdown
  document with `#`/`##` headings; confirm a TOC column appears on the right, its
  entries are clickable, and clicking scrolls the display to the matching section.
  Confirm a PlainText snippet (and a heading-less doc) shows no TOC column and the
  display stays full width. Confirm editor mode is unaffected.
- Run with `./scripts/restart.sh --all --opt` and eyeball.

## Risks

- Scripta's `output.toc` is pre-styled by the compiler (a bordered box) and will
  look heavier than the Markdown TOC until the scroll-spy spec unifies rendering.
  Adjust `.col-toc` / override styles during manual verification if it looks off.
- Duplicate heading text yields duplicate ids; `getElementById`/`scrollIntoView`
  targets the first. Acceptable for v1.
- `viewRight` changing from `Html Msg` to `List (Html Msg)` touches the one call
  site in `view`; confirm no other caller exists.
