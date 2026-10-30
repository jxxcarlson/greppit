# Changelog

## 2026-10-30 — Editor auto-save

Branch `feat/editor-autosave` (commit `9e4ae1a`). Builds with `--optimize`. Unit tests compile but have not been run, and it has not been tried in the browser yet.

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

- **Compiler version:** `/usr/local/bin/elm` is now 0.19.2, which rejects this project's `elm.json` (0.19.1). So `./scripts/restart.sh` fails at the `elm make` step. Build with `~/.elm/elm-tooling/elm/0.19.1/elm` instead.
- **Tests not run:** the sandbox blocked elm-test, so the suite hasn't been run. To run it: `cd frontend && elm-test --compiler ~/.elm/elm-tooling/elm/0.19.1/elm`
- **Process:** the usual spec and plan were skipped at the user's request. The work is on its own branch, not merged into `main`.
