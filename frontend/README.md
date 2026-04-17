# greppit-frontend

Elm 0.19.1 single-page app for greppit.

## Prerequisites

- `elm` 0.19.1
- `elm-test` (for unit tests)
- Python 3 (for the dev server)
- Backend running on `http://localhost:8085` (see `../backend/README.md`)

## Run

```
./run.sh
```

Compiles `elm.js` and serves on `http://localhost:8011`.

The `apiBase` the app talks to is derived at page load:
- `localhost` / `127.0.0.1` → `http://localhost:8085`
- anything else → `window.location.origin`

## Test

```
elm-test
```

Unit tests for JSON decoders (`tests/ApiDecoderTests.elm`).

## Layout

```
frontend/
  elm.json
  index.html             # KaTeX + math-text custom element + Elm bootstrap
  codemirror-element.js  # vendored CodeMirror 6 custom element
  elm-markdown/          # vendored extended markdown (math via <math-text>)
  serve.py               # dev static-file server on 8011
  run.sh                 # elm make + serve
  src/
    Main.elm             # top-level model, update, view
    Types.elm            # Flags, Model, Msg, Snippet, User, Markup, etc.
    Api.elm              # HTTP calls + JSON codecs
    Auth.elm             # login/signup view
    Search.elm           # left column: search input + result list
    Editor.elm           # right column Editor mode (new + edit + delete)
    Render.elm           # Snippet -> Html (dispatches on markup)
    CodeMirror.elm       # wrapper around <codemirror-editor>
  tests/
    ApiDecoderTests.elm
```

## Auth

Email + password. JWT stored in `localStorage` under the key `greppit-token`.
On page load, if a token is present it is validated via `GET /api/auth/me`.
If the server rejects it, the token is cleared and the user is shown the
sign-in form.

## Search

Conjunctive, case-insensitive, debounced 200ms. Top 5 by `updated_at DESC`.
An empty query returns the 5 most recent snippets. On initial load, sign-in,
or reload, the first result is auto-selected so the right column isn't blank.

## Rendering

- Markdown: vendored `elm-markdown` emits `<math-text>` elements for `$...$`
  and `$$...$$`; KaTeX (loaded from CDN in `index.html`) renders them.
- Scripta: dropdown option is accepted for data, but renders a placeholder
  ("Scripta rendering not yet enabled.") in v1.

## CodeMirror

The `<codemirror-editor>` custom element carries an initial value via the
`load` attribute and emits `text-change` events with `detail.source` as the
new value. `CodeMirror.elm` wraps this with `Html.Keyed` so swapping keys
between New / Edit targets forces a clean remount.
