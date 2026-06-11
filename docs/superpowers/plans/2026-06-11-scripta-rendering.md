# Scripta Rendering Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Render Scripta-markup snippets in greppit's display pane using the vendored `scripta-compiler-v3` compiler.

**Architecture:** Vendor the compiler's Elm source into `frontend/scripta/` (mirroring the existing `frontend/elm-markdown/` vendoring), replace greppit's incompatible `math-text` custom element with the compiler's property-based version, and replace the `Scripta ->` placeholder branch in `Render.elm` with a `Scripta.compile` call whose interaction events are dropped.

**Tech Stack:** Elm 0.19.1, `scripta-compiler-v3` (vendored source), KaTeX (math custom element), elm-test.

---

## Reference: source paths

- Compiler source (read-only origin): `/Users/carlson/dev/elm-work/scripta/scripta-compiler-v3/src`
- Compiler Demo (reference for the math element): `/Users/carlson/dev/elm-work/scripta/scripta-compiler-v3/Demo/index.html`
- greppit frontend root: `/Users/carlson/dev/greppit/frontend`

All commands below assume the working directory is `/Users/carlson/dev/greppit/frontend` unless stated otherwise.

## File Structure

- **Create** `frontend/scripta/**` — verbatim copy of the compiler's `src/` tree (56 `.elm` files: `Scripta.elm`, `Scripta/`, `Render/`, `Parser/`, `Generic/`, `ETeX/`, `MiniLaTeX/`, `Library/`, `Tools/`, `V3/`, `TestData.elm`). Vendored library; not edited by greppit.
- **Create** `frontend/tests/ScriptaRenderTests.elm` — automated guard that the compiler is wired in and produces rendered output.
- **Modify** `frontend/elm.json` — add `"scripta"` to `source-directories`; add 7 community dependencies (+ resolved indirects).
- **Modify** `frontend/index.html` — replace the `math-text` custom element and KaTeX loader.
- **Modify** `frontend/src/Types.elm` — add a `NoOp` constructor to `Msg`.
- **Modify** `frontend/src/Render.elm` — implement the `Scripta` branch; change `render`'s return type to `Html Msg`.

### Why no collision risk (verified during design)

The compiler's module namespaces (`ETeX.*`, `Generic.*`, `Library.*`, `MiniLaTeX.*`, `Parser.*`, `Render.*`, `Scripta`, `Scripta.*`, `Tools.*`, `V3.*`, `TestData`) do not collide with greppit's `src` modules (`Main`, `Types`, `Api`, `Auth`, `Editor`, `Search`, `Export`, `Render`, `CodeMirror`). greppit's bare `Render` module and the compiler's `Render.*` namespaced modules coexist. The `module Main` strings inside `TestData.elm` are sample-document string literals, not declarations.

---

## Task 1: Vendor the compiler source and dependencies

**Files:**
- Create: `frontend/scripta/**` (copied tree)
- Create: `frontend/tests/ScriptaRenderTests.elm`
- Modify: `frontend/elm.json`

- [ ] **Step 1: Write the failing test**

Create `frontend/tests/ScriptaRenderTests.elm`:

```elm
module ScriptaRenderTests exposing (suite)

import Expect
import Scripta
import Test exposing (Test, describe, test)


suite : Test
suite =
    describe "Scripta compiler integration"
        [ test "compile produces a non-empty body for simple input" <|
            \_ ->
                let
                    output =
                        Scripta.compile Scripta.defaultOptions "Hello world"
                in
                List.length output.body
                    |> Expect.atLeast 1
        ]
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `elm-test tests/ScriptaRenderTests.elm`
Expected: FAIL at compile time — Elm reports it cannot find module `Scripta` (the source is not vendored yet).

- [ ] **Step 3: Vendor the compiler source**

Run (from `frontend/`):

```bash
mkdir -p scripta
cp -R /Users/carlson/dev/elm-work/scripta/scripta-compiler-v3/src/. scripta/
```

Verify the copy landed at the expected roots:

```bash
ls scripta/Scripta.elm scripta/Render/Math.elm scripta/V3/Types.elm
```

Expected: all three paths exist.

- [ ] **Step 4: Add `scripta` to source-directories**

Edit `frontend/elm.json`. Change:

```json
    "source-directories": [
        "src",
        "elm-markdown"
    ],
```

to:

```json
    "source-directories": [
        "src",
        "elm-markdown",
        "scripta"
    ],
```

- [ ] **Step 5: Install the compiler's dependencies**

The compiler needs 7 community packages. Run each (piping `Y` to accept the elm.json edit; indirect deps resolve automatically):

```bash
echo "Y" | elm install elm-community/list-extra
echo "Y" | elm install elm-community/maybe-extra
echo "Y" | elm install elm-community/result-extra
echo "Y" | elm install maca/elm-rose-tree
echo "Y" | elm install pablohirafuji/elm-syntax-highlight
echo "Y" | elm install toastal/either
echo "Y" | elm install zwilias/elm-rosetree
```

Expected versions (match the compiler's `elm.json`): `list-extra 8.7.0`, `maybe-extra 5.3.0`, `result-extra 2.4.0`, `maca/elm-rose-tree 1.2.1`, `pablohirafuji/elm-syntax-highlight 3.7.1`, `toastal/either 3.6.3`, `zwilias/elm-rosetree 1.5.0`.

- [ ] **Step 6: Run the test to verify it passes**

Run: `elm-test`
Expected: PASS. The existing 36 tests plus the 1 new test = 37 tests pass. (This compiles a large portion of the vendored compiler via the `Scripta` import, confirming the vendoring and dependencies are correct.)

Also confirm the app still compiles:

Run: `elm make src/Main.elm --output=/dev/null`
Expected: `Success!`

- [ ] **Step 7: Commit**

```bash
git add frontend/scripta frontend/tests/ScriptaRenderTests.elm frontend/elm.json
git commit -m "feat(scripta): vendor scripta-compiler-v3 source and deps

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: Replace the `math-text` custom element

greppit's current element reads HTML *attributes*; the v3 compiler sets DOM *properties* (`HA.property "content"/"display"`). They are incompatible — math would render nothing. Replace greppit's element and KaTeX loader with the compiler Demo's property-based, shadow-DOM version that also loads KaTeX and mhchem dynamically.

**Files:**
- Modify: `frontend/index.html`

- [ ] **Step 1: Drop the eager KaTeX `<script>` tag (keep the CSS link)**

Edit `frontend/index.html`. Replace:

```html
    <!-- KaTeX for math rendering -->
    <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/katex@0.16.9/dist/katex.min.css">
    <script defer src="https://cdn.jsdelivr.net/npm/katex@0.16.9/dist/katex.min.js"></script>
```

with:

```html
    <!-- KaTeX CSS for math rendering; the JS is loaded dynamically below
         so the math-text custom element is defined only after KaTeX exists. -->
    <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/katex@0.16.9/dist/katex.min.css">
```

- [ ] **Step 2: Replace the custom element definition**

In `frontend/index.html`, replace this block:

```html
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
```

with this block (property-based, matches the v3 compiler's `Render.Math` output; loads KaTeX + mhchem dynamically):

```html
        // KaTeX <math-text> custom element. The v3 Scripta compiler sets the
        // `content` and `display` DOM *properties* (not attributes), so this
        // element exposes property setters and recovers properties that Elm
        // set before the element was upgraded.
        function initKatex() {
            class MathText extends HTMLElement {
                constructor() {
                    super();
                    this.attachShadow({ mode: "open" });
                    this._content = '';
                    this._display = false;
                }
                connectedCallback() {
                    this._upgradeProperty('content');
                    this._upgradeProperty('display');
                    this._render();
                }
                _upgradeProperty(prop) {
                    if (this.hasOwnProperty(prop)) {
                        let value = this[prop];
                        delete this[prop];
                        this[prop] = value;
                    }
                }
                set content(val) { this._content = val; if (this.isConnected) this._render(); }
                get content() { return this._content; }
                set display(val) { this._display = val; if (this.isConnected) this._render(); }
                get display() { return this._display; }
                _render() {
                    if (!this._content) return;
                    try {
                        this.shadowRoot.innerHTML = katex.renderToString(this._content, {
                            throwOnError: false,
                            displayMode: this._display,
                            trust: true
                        });
                    } catch (e) {
                        this.shadowRoot.innerHTML =
                            '<span style="color:red">' + (e && e.message ? e.message : 'KaTeX error') + '</span>';
                    }
                    let link = document.createElement('link');
                    link.setAttribute('rel', 'stylesheet');
                    link.setAttribute('href', 'https://cdn.jsdelivr.net/npm/katex@0.16.9/dist/katex.min.css');
                    this.shadowRoot.appendChild(link);
                }
            }
            customElements.define('math-text', MathText);
        }

        function loadMhchem() {
            var mhchem = document.createElement('script');
            mhchem.type = 'text/javascript';
            mhchem.src = "https://cdn.jsdelivr.net/npm/katex@0.16.9/dist/contrib/mhchem.min.js";
            document.head.appendChild(mhchem);
        }

        var katexJs = document.createElement('script');
        katexJs.type = 'text/javascript';
        katexJs.onload = function() { initKatex(); loadMhchem(); };
        katexJs.onerror = function(e) { console.error("KaTeX failed to load", e); };
        katexJs.src = "https://cdn.jsdelivr.net/npm/katex@0.16.9/dist/katex.min.js";
        document.head.appendChild(katexJs);
```

The remainder of the `<script>` block (the `apiBase` flag computation, `Elm.Main.init`, and the `saveToken`/`removeToken` port subscriptions) stays unchanged.

- [ ] **Step 3: Verify the app still compiles**

Run: `elm make src/Main.elm --output=/dev/null`
Expected: `Success!` (this step only changed static HTML/JS, so compilation is unaffected; this is a sanity check that nothing else was disturbed).

- [ ] **Step 4: Commit**

```bash
git add frontend/index.html
git commit -m "fix(scripta): make math-text element property-based for v3 compiler

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: Wire Scripta rendering into the display pane

**Files:**
- Modify: `frontend/src/Types.elm` (add `NoOp` to `Msg`)
- Modify: `frontend/src/Render.elm` (implement `Scripta` branch, change return type)

Note: `update` and `updateSignedIn` in `src/Main.elm` both end with a catch-all `_ -> ( model, Cmd.none )`, so `NoOp` is handled with no `Main.elm` change.

- [ ] **Step 1: Add `NoOp` to the `Msg` type**

Edit `frontend/src/Types.elm`. The `Msg` type's last constructor is:

```elm
    | SearchDebounceTick Int String
```

Add a `NoOp` constructor immediately after it:

```elm
    | SearchDebounceTick Int String
    | NoOp
```

`Msg(..)` is already in the module's `exposing` list, so `NoOp` is exported.

- [ ] **Step 2: Implement the `Scripta` branch in `Render.elm`**

Replace the entire contents of `frontend/src/Render.elm` with:

```elm
module Render exposing (render)

import Html exposing (Html, div, text)
import Html.Attributes exposing (class)
import Markdown
import Scripta
import Types exposing (Markup(..), Msg(..), Snippet)


{-| Render a snippet's body for the display pane. The return type is `Html Msg`
because Scripta's rendered output carries interaction events; for this
read-only view every event is mapped to `NoOp`.
-}
render : Snippet -> Html Msg
render s =
    case s.markup of
        Markdown ->
            div [ class "display-body" ] (Markdown.toHtml Nothing s.body)

        PlainText ->
            -- Preserve line breaks and whitespace; no markdown parsing.
            -- `.display-body-plain` sets `white-space: pre-wrap`.
            div [ class "display-body display-body-plain" ] [ text s.body ]

        Scripta ->
            let
                options =
                    Scripta.defaultOptions
                        |> Scripta.withContentWidth 700
                        |> Scripta.withWindowWidth 700

                output =
                    Scripta.compile options s.body
                        |> Scripta.mapEvent (\_ -> NoOp)
            in
            div [ class "display-body" ] (output.title :: output.body)
```

- [ ] **Step 3: Verify the app compiles**

Run: `elm make src/Main.elm --output=/dev/null`
Expected: `Success!`

If Elm reports a type error at the `Render.render snippet` call site in `src/Main.elm:535`, it means a surrounding `Html msg` context needs to be `Html Msg`; the display view already lives in a `Html Msg`-typed `view`, so no change is expected. Do not weaken the type — fix the actual mismatch if one appears.

- [ ] **Step 4: Verify all tests pass**

Run: `elm-test`
Expected: PASS — 37 tests (36 existing + the Scripta integration test).

- [ ] **Step 5: Commit**

```bash
git add frontend/src/Types.elm frontend/src/Render.elm
git commit -m "feat(scripta): render Scripta snippets in the display pane

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: End-to-end manual verification

**Files:** none (verification only; a commit happens only if Step 4 requires CSS).

- [ ] **Step 1: Build and start the app**

Run (from repo root `/Users/carlson/dev/greppit`):

```bash
./scripts/restart.sh --all
```

Expected: backend on `:8085`, frontend on `:8011`, ending with `Open http://localhost:8011`.

- [ ] **Step 2: Create a Scripta snippet**

In the browser at `http://localhost:8011`, sign in, click to create a new snippet, set the Markup dropdown to **Scripta**, and paste a body that exercises headings, math, a list, and code. Save it.

Suggested body:

```
# Scripta test

A paragraph with inline math $a^2 + b^2 = c^2$ and a display equation:

$$\int_0^1 x^2 \, dx = \frac{1}{3}$$

- first item
- second item

`inline code` and a block:

| code
print("hello")
```

- [ ] **Step 3: Confirm rendering**

Select the snippet to open the display pane. Verify:
- The heading, paragraph, list, and code block render (not raw Scripta text, and not the old "Scripta rendering not yet enabled" placeholder).
- Inline math `a^2 + b^2 = c^2` and the display integral render via KaTeX.
- The browser console shows no errors about `math-text` or KaTeX.

- [ ] **Step 4: Port Scripta CSS if needed**

If rendered output is visibly unstyled or misaligned compared with the compiler Demo, compare against `/Users/carlson/dev/elm-work/scripta/scripta-compiler-v3/Demo/index.html` and copy the relevant Scripta style rules into the `<style>` block of `frontend/index.html`. If you change CSS, commit:

```bash
git add frontend/index.html
git commit -m "style(scripta): port required Scripta display styles

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

If no CSS changes are needed, note that verification passed and stop here.

---

## Self-Review notes

- **Spec coverage:** vendoring + deps (Task 1) ✓; math-text fix (Task 2) ✓; `Scripta.compile` wiring + `NoOp` + `Html Msg` signature (Task 3) ✓; manual verification incl. CSS-porting risk (Task 4) ✓. Fixed 700px width and dropped events are both implemented as specified.
- **Type consistency:** `render : Snippet -> Html Msg`; `Scripta.compile : Options -> String -> Output Event`; `Scripta.mapEvent : (Event -> msg) -> Output Event -> Output msg` yields `Output Msg`; `output.title : Html Msg`, `output.body : List (Html Msg)`. Consistent throughout.
