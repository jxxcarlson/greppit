# Changelog

## 2026-10-30 — Fix: duplicate title for Scripta snippets

Branch `fix/scripta-title-header`.

- **Symptom:** a Scripta snippet that starts with a `| title` block showed
  its title twice in the reader: greppit's header (the snippet's Title
  field) and then the compiler's title.
- **Fix:** the source's title wins. The reader header now leaves out the
  snippet title whenever the body supplies one. The check is
  `Render.hasSourceTitle`:
  - Scripta asks the compiler (`Scripta.Document.title`, the text of the
    `| title` block).
  - Markdown uses the existing `%title` rule.
  - Plain text never has a source title.
- **Tests:** `tests/MarkdownTitleTests.elm` became
  `tests/SourceTitleTests.elm`, with Scripta and plain-text cases added.
- **Checked in Chrome** with a temporary Scripta snippet (since deleted):
  no header title, and "Good Podcasts!" shows once. A Scripta snippet
  without a title block still shows its header title.

## 2026-10-30 — Markdown from the xmarkdown-compiler package

Branch `feat/xmarkdown-package`.

- **Change:** Markdown is now compiled by
  [`jxxcarlson/xmarkdown-compiler`](https://package.elm-lang.org/packages/jxxcarlson/xmarkdown-compiler/latest/)
  instead of the vendored `elm-markdown/`, which is deleted. The reader's
  table of contents now comes from the compiler. Its `SelectId` events
  become `ScrollToHeading`. greppit's own heading/TOC code in
  `src/Render.elm` and its test (`MarkdownTocTests`) are gone.
- **Math:** XMarkdown passes math as `data-content` / `data-display`
  attributes, so `<math-text>` in `index.html` now reads those as well as
  the properties the Scripta compiler sets.
- **Title blocks:** a Markdown snippet that starts with a title block
  (`%title`, `%author`, `%date`) gets its title from the compiler, so the
  reader no longer shows the snippet title above it. Without a `%title`,
  the header is unchanged. The check is `Render.hasMarkdownTitle`, tested
  in `tests/MarkdownTitleTests.elm`.
- **`elm.json`:** added the package and `avh4/elm-color`. `elm/regex`
  moved to indirect.
- **Version:** uses xmarkdown 2.2.5. 2.2.4 made paragraphs and lists fit
  panes narrower than 700px. 2.2.5 made a title block count only at the
  start of a document.
- **Checked in Chrome** against the published 2.2.5: the reader and the
  editor preview fit their panes, TOC clicks scroll, a leading title
  block replaces the header title, and a `%title` block later in the
  document renders nothing.

## 2026-10-30 — Scripta from the published package

Branch `feat/scripta-package`.

- **Change:** Scripta is now compiled by the published
  [`jxxcarlson/scripta-compiler-v3`](https://package.elm-lang.org/packages/jxxcarlson/scripta-compiler-v3/latest/)
  package (1.0.1) instead of the copy vendored into `frontend/scripta/`
  on 2026-06-11, which had fallen behind upstream. The vendored directory
  is deleted and `scripta` is gone from `source-directories`.
- **Code:** no source changes. `src/Render.elm` and
  `tests/ScriptaRenderTests.elm` only use the public `Scripta` API, and
  the package exposes the same functions.
- **`elm.json`:** added the package (which brings `jxxcarlson/etex` and
  `elmcraft/core-extra`). Seven dependencies greppit's own code doesn't
  import moved from direct to indirect, because the package still needs
  them: list-extra, maybe-extra, result-extra, maca/elm-rose-tree,
  elm-syntax-highlight, toastal/either, elm/parser.
  `zwilias/elm-rosetree` was removed; nothing uses it.
- **Checked:** the app builds with `--optimize`, and the test modules
  compile. In Chrome, the existing Scripta snippets render. A sample with
  sections, a list, and inline and display math rendered in the editor
  preview: H2/H3 headings, two list items, KaTeX math.
- **Open question:** the "Test" snippet's first line, `| Test (foo)`,
  renders as `[Test]`. This wasn't compared against the vendored
  version.

## 2026-10-30 — Save before switching snippets

Branch `feat/save-before-switch`.

- **What it does:** if you're editing and click another snippet in the
  list, or press New snippet, your unsaved changes are saved first. The
  switch happens once that save succeeds. This also covers a save that
  was already running when you clicked.
- **If the save fails:** you stay in the editor, the status line shows
  the error, and nothing is lost.
- **Fixed along the way:** pressing New snippet while on a new snippet
  used to keep the old text in CodeMirror, because both editors had the
  key `"new"`. Each new-snippet editor now gets its own key.
- **Code:** `saveBeforeLeaving`, `performNav` and `startAutoSave` in
  `frontend/src/Main.elm`; `PendingNav` and `editorSeq` in
  `frontend/src/Types.elm`.
- **Checked in Chrome** (with temporary snippets, since deleted): new
  snippet then list click; new snippet then New snippet; edit an existing
  snippet then list click. Each time the switch happened before
  auto-save's 2 seconds were up, and the server had the right text with
  no duplicates. The save-failure path was not exercised.

## 2026-10-30 — Fix: editor pane empty (CodeMirror failed to load)

Branch `fix/codemirror-esm-lezer`, also cherry-picked onto
`chore/elm-0.19.2`.

- **Symptom:** you couldn't type in a new snippet, and an existing
  snippet showed its rendered preview but no source.
- **Cause:** esm.sh's build of `@codemirror/commands@6.3.3` pulled in its
  own copy of `@lezer/common@^1.1.0`. esm.sh can't build that copy: it
  returns a 500 error ("no space left on device"). The failure spread:
  `commands` failed, then the `codemirror` bundle, then
  `codemirror-element.js`. So `<codemirror-editor>` was never defined.
  This was unrelated to auto-save and to Elm 0.19.2.
- **Fix:** `frontend/index.html` now lists `@lezer/common` as external
  for `@codemirror/commands`, so it uses the import map's copy (1.2.1),
  the same as the other CodeMirror packages. Checked in Chrome: the
  editor loads, existing snippets show their source, and new snippets
  are editable.
- **Note:** browsers may keep the old `index.html` cached. Do a hard
  reload (⇧⌘R) after deploying.

## 2026-10-30 — Build with Elm 0.19.2

Branch `chore/elm-0.19.2`. The frontend now targets Elm 0.19.2, the
version installed at `/usr/local/bin/elm`.

- `frontend/elm.json`: `elm-version` changed from 0.19.1 to 0.19.2. No
  source or dependency changes were needed: all 64 modules build with
  `--optimize`, and the test modules compile.
- `README.md`, `frontend/README.md`, `deploy/README.md`: prerequisites
  now say 0.19.2. The droplet setup installs it with
  `npm install -g elm@latest-0.19.2`.
- **On the droplet:** before the next frontend deploy, install 0.19.2
  there as well, or `elm make` will refuse the new `elm.json`.

## 2026-10-30 — Editor auto-save

Commit `9e4ae1a`. Merged into `main` 2026-10-30. Tested in the browser locally. Unit tests compile but have not been run.

**What it does**

- **When it saves:** any change to title, tags, markup or body starts a 2-second countdown, and each new change restarts it. When the countdown ends, the snippet is saved and you stay in the editor. A new snippet is created on its first save, and later saves update it. A brand-new snippet with no title and no body is never saved.
- **Status line:** a small line next to the buttons says "Saving…", "Saved", "Unsaved changes", or "Auto-save failed: …".
- **Save button:** works as before: it saves and goes back to the reading view.
- **Cancel is now Close:** with auto-save, Cancel could no longer undo anything. If you press Close within those 2 seconds, it saves the pending changes before closing.
- **No editor jumps:** the editor's key and starting text are fixed when it opens, so a save doesn't reload it or move your cursor.
- **Lists stay current:** the results list updates after each save. If you close the editor while a save is still running, the snippet on screen updates when that save finishes.
- **One save at a time:** Save, Close, Export and Delete are greyed out while an auto-save is running, so you can't create a duplicate. Changes made during a save are picked up right after it.

**Where the code is**

- `frontend/src/Main.elm`: the `AutoSaveTick` / `AutoSaveResponded` handlers and the `editorChanged` and `closeEditor` helpers.
- `frontend/src/Types.elm`: the new `EditorState` fields.
- `frontend/src/Editor.elm`: the status line (`autoSaveStatus`).

**Things to know**

- **Compiler version:** `/usr/local/bin/elm` is now 0.19.2, which rejects this project's `elm.json` (0.19.1). So `./scripts/restart.sh` fails at the `elm make` step. Build with `~/.elm/elm-tooling/elm/0.19.1/elm` instead. (Resolved by the Elm 0.19.2 entry above.)
- **Tests not run:** the sandbox blocked elm-test, so the suite hasn't been run. To run it: `cd frontend && elm-test`
- **Process:** the usual spec and plan were skipped at the user's request.
