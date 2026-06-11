# Scripta Rendering in the Display Pane

**Date:** 2026-06-11
**Status:** Approved (design)
**Scope:** Display-pane rendering only

## Goal

greppit stores each snippet with a `markup` field that is one of `Markdown`,
`PlainText`, or `Scripta`. The display pane (`Render.render`) renders Markdown
and PlainText today; the `Scripta` branch is a placeholder reading
"Scripta rendering not yet enabled." This work replaces that placeholder with
real rendering driven by the `scripta-compiler-v3` compiler.

## Non-Goals (YAGNI)

- No live preview while editing (the editor stays plain text input).
- No interactive Scripta events (clicked internal links, footnotes, citations,
  TOC navigation, R-to-L editor sync) — all interaction events are dropped.
- No responsive/auto width — a fixed content width is used.
- No publishing the compiler as an Elm package — it is vendored as source.

## Architecture

### 1. Vendor the compiler source

The compiler at `/Users/carlson/dev/elm-work/scripta/scripta-compiler-v3` is an
`application`-type Elm project, not a published package. greppit already vendors
a library this way (`frontend/elm-markdown/`), so we follow that precedent.

- Copy the compiler's `src/**` into `frontend/scripta/`.
- Add `"scripta"` to `source-directories` in `frontend/elm.json`.
- Add the compiler's 7 direct community dependencies to `frontend/elm.json`
  (`elm install` will also pull the required indirect deps):
  - `elm-community/list-extra` 8.7.0
  - `elm-community/maybe-extra` 5.3.0
  - `elm-community/result-extra` 2.4.0
  - `maca/elm-rose-tree` 1.2.1
  - `pablohirafuji/elm-syntax-highlight` 3.7.1
  - `toastal/either` 3.6.3
  - `zwilias/elm-rosetree` 1.5.0

### 2. Fix the `math-text` custom element (compatibility bug)

greppit's `index.html` defines a `math-text` custom element ("lifted from
scripta-app-v4") that reads HTML **attributes**:

```js
static get observedAttributes() { return ['content', 'display']; }
var content = this.getAttribute('content') || '';
```

The v3 compiler emits the element by setting JS **properties** instead
(`src/Render/Math.elm:49`):

```elm
Html.node "math-text"
    [ HA.property "display" (Json.Encode.bool ...)
    , HA.property "content" (Json.Encode.string content)
    ]
    []
```

`HA.property` sets DOM properties, not attributes, so greppit's attribute-based
element would receive nothing and render no math. **Fix:** replace greppit's
`math-text` definition in `index.html` with the property-based version used by
the compiler's Demo app (`Demo/index.html`), which exposes `content`/`display`
setters. KaTeX (and mhchem) loading is preserved.

### 3. Wire rendering in `Render.elm`

Replace the `Scripta ->` placeholder branch:

```elm
Scripta ->
    let
        opts =
            Scripta.defaultOptions
                |> Scripta.withContentWidth 700
                |> Scripta.withWindowWidth 700

        out =
            Scripta.compile opts s.body
                |> Scripta.mapEvent (\_ -> NoOp)
    in
    div [ class "display-body" ] (out.title :: out.body)
```

`Scripta.compile : Options -> String -> Output Event` is `parse` followed by
`render`. `Output` is `{ title, body, toc, banner }` of `Html`. For the display
pane we render `title :: body` and ignore `toc`/`banner`.

Because `Output Event` carries the compiler's interaction events, and this pass
is read-only, every event is mapped to a new no-op message:

- Add `NoOp` to the `Msg` type in `Types.elm`; handle it in `update` as
  `( model, Cmd.none )`.
- Change `render : Snippet -> Html msg` to `render : Snippet -> Html Msg`.
  The Markdown and PlainText branches (currently `Html msg`) specialize to
  `Html Msg` with no change. `Render` already imports `Types`; no import cycle
  is introduced.

The content width is a fixed `700` px sized to the display pane. Making it
responsive (driven by viewport width) is deferred.

## Data Flow

```
Snippet.body (String, Scripta markup)
  -> Scripta.compile opts            -- parse + render
  -> Output Event { title, body, .. }
  -> mapEvent (\_ -> NoOp)           -- drop interaction events
  -> div [class "display-body"] (title :: body)
  -> math-text nodes rendered by KaTeX via the custom element
```

## Error Handling

The Scripta compiler does not fail on malformed input; it renders error
indicators inline. No additional error handling is required in `Render.elm`.
KaTeX errors are surfaced inline by the `math-text` element's catch block.

## Testing & Verification

- `elm make src/Main.elm` compiles cleanly with the vendored source and new deps.
- `elm-test` — existing 36 tests stay green (no behavior they cover changes).
- Manual verification: create a Scripta snippet containing a heading, an inline
  math expression, a display math block, a bullet list, and a code block; view
  it in the display pane and confirm correct rendering, including math via KaTeX.
- Run the app with `./scripts/restart.sh` and eyeball the result.

## Risks

- The vendored copy is a point-in-time snapshot. Future compiler changes require
  re-vendoring. This is accepted and matches the `elm-markdown` arrangement.
- Rendered output may depend on Scripta CSS classes. During implementation,
  compare against the Demo's `index.html` and port any required styles into
  greppit's stylesheet.
