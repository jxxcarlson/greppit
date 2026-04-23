# Snippet Export — Design

**Date:** 2026-04-23
**Status:** Approved, ready for implementation plan
**Scope:** Per-snippet "Export" command in the editor, client-side browser download.

## Motivation

Users maintain a Zettelkasten archive on local disk (e.g., "The Archive" on macOS) of
plain-text notes named by a 14-digit timestamp ID plus title, such as
`20260118003017 Painting Random Walk.txt`. We want a one-click way to export
an individual greppit snippet into that archive's filename convention.

The snippet's `zku_id` already encodes the required timestamp: `zku_id` has the
form `<username>-<YYYYMMDDHHMMSS>` with an optional `-N` collision suffix. Dropping
the username prefix yields the exact filename stem the archive expects.

## Non-goals

- Bulk export / ZIP download.
- Writing directly to a user-chosen filesystem directory (requires the File System
  Access API or a local companion; deferred).
- A separate backend endpoint. No DB change.
- Export from the snippet list view. (Editor-only for v1; list-view button may be
  added later.)
- Round-tripping exported files back into greppit.

## Architecture

All logic lives in the frontend, in a new pure module `frontend/src/Export.elm`.
The editor gains an "Export" button; the update handler calls
`File.Download.string` from `elm/file` with the computed filename, MIME type
`text/plain`, and the assembled body. No network call. No new message pipeline
beyond one `Msg` constructor.

`elm/file` is currently listed as an indirect dependency in `elm.json`; it must
be promoted to a direct dependency for `Export.elm` / `Main.elm` to import
`File.Download`.

### Module boundaries

- `Export.elm` — pure functions only:
  - `filename : Snippet -> String`
  - `body : Snippet -> String`
  - `sanitizeTitle : String -> String` (exposed for testing)
  - `baseIdOf : String -> String` (exposed for testing — takes a `zku_id`)
  - `formatTags : String -> Maybe String` (exposed for testing — returns `Nothing` if no tags)
- `Editor.elm` — one new button; emits `ExportPressed`.
- `Main.elm` — handles `ExportPressed` by invoking `File.Download.string`.
- `Types.elm` — adds `ExportPressed` to `Msg`.

## Filename derivation

`Export.filename` produces `<baseId>[ <sanitizedTitle>].txt`.

### baseId

`baseId = everything after the first '-' in zku_id`.

Examples:

| `zku_id`                         | `baseId`            |
|----------------------------------|---------------------|
| `jxxcarlson-20260118003017`      | `20260118003017`    |
| `jxxcarlson-20260118003017-2`    | `20260118003017-2`  |
| `ab-20260118003017`              | `20260118003017`    |
| `jxxcarlson-20260118003017-100`  | `20260118003017-100`|

Implementation: find the index of the first `-`; take the substring after it.
If there is no `-` at all (should not occur for any well-formed `zku_id`), fall
back to the whole `zku_id` — treat as defensive.

### Title sanitization (rule b2)

Applied in order:

1. Replace each of `/ \ : * ? " < > |` with a single space.
2. Replace ASCII control chars (code points 0–31 and 127) with a single space.
3. Drop all characters whose code point is ≥ 128 (non-ASCII).
4. Collapse runs of whitespace to a single space.
5. Trim leading/trailing whitespace.
6. Truncate to 120 characters.

If the result is empty (empty input, whitespace-only input, or input composed
entirely of dropped/replaced characters), treat as "no title".

### Assembly

- No title → `"<baseId>.txt"`
- With title → `"<baseId> <sanitizedTitle>.txt"` (single space between).

Examples:

| Input title             | Filename (assuming baseId `20260118003017`)             |
|-------------------------|---------------------------------------------------------|
| `Painting Random Walk`  | `20260118003017 Painting Random Walk.txt`               |
| `` (empty)              | `20260118003017.txt`                                    |
| `Notes: 2026/04`        | `20260118003017 Notes  2026 04.txt` (before collapse)<br>`20260118003017 Notes 2026 04.txt` (after) |
| `思考` (CJK)            | `20260118003017.txt` (all non-ASCII dropped → empty)     |
| `Café notes`            | `20260118003017 Caf notes.txt` (the `é` is dropped)     |

## Body assembly

`Export.body` returns a single string:

```
<body with trailing newlines trimmed>
<blank line>
Tags: #alpha, #beta
markup: markdown
```

followed by one trailing newline.

Rules:

- **Body**: `snpBody` with trailing `\n` characters stripped, so the blank-line
  separator between body and trailer is always exactly one blank line.
- **Tags line**:
  - Split `snpTags` on whitespace; drop empty tokens.
  - If the resulting list is empty, **omit the entire `Tags:` line**.
  - Otherwise prefix each token with `#`, join with `, `, and emit
    `Tags: #<tok1>, #<tok2>, ...`.
- **Markup line**: always present. Use the existing lowercase forms from
  `Types.markupToString`: `markdown`, `scripta`, `plaintext`.
- **Trailing newline**: the final output ends with exactly one `\n`.

Example with empty tags:

```
Some body text.

markup: markdown
```

Example with tags `alpha beta`:

```
Some body text.

Tags: #alpha, #beta
markup: markdown
```

## UI

`Editor.elm` gains an **Export** button in the existing `editor-actions` row,
shown only when `st.editing` is `Just _` (same visibility condition as the
Delete button — a brand-new unsaved snippet has no `zku_id`).

```
[Save] [Cancel] [Export] [Delete]
```

- Styling: reuse the existing `btn btn-secondary` class to keep it visually
  subordinate to Save.
- No confirmation dialog.
- No spinner or toast. The browser's download UI is the feedback.
- Disabled when `st.saving` is true, matching the other buttons.

`Msg`: `ExportPressed` (no payload).

`Main.update` handler:

```elm
ExportPressed ->
    case model.editorState.editing of
        Just s ->
            ( model
            , File.Download.string (Export.filename s) "text/plain" (Export.body s)
            )

        Nothing ->
            ( model, Cmd.none )
```

## Error handling

None. `File.Download.string` is fire-and-forget — it produces a `Cmd msg` that
the Elm runtime hands to the browser; there is no failure path visible to the
program. If the user's browser is configured to block or prompt for downloads,
that is handled by the browser, not by us.

## Testing

New file `frontend/tests/ExportTests.elm` using `elm-explorations/test`.
Cases:

### filename / baseIdOf
- `zku_id = "jxxcarlson-20260118003017"` → baseId `"20260118003017"`.
- `zku_id = "jxxcarlson-20260118003017-2"` → baseId `"20260118003017-2"`.
- `zku_id = "ab-cd-ef"` (multiple dashes) → baseId `"cd-ef"`.
- No dash (defensive) → baseId equals input.

### filename / sanitizeTitle
- Plain ASCII title preserved.
- Each of `/ \ : * ? " < > |` replaced with space.
- Control char (e.g. `\t`, `\n`) replaced with space.
- Non-ASCII (é, 思) dropped.
- Runs of whitespace collapsed.
- Trimmed.
- Truncated at 120 chars.
- Empty / whitespace-only → empty string.
- All-non-ASCII title → empty string.

### filename (assembly)
- Normal title: `20260118003017 Painting Random Walk.txt`.
- Empty title: `20260118003017.txt`.
- Collision suffix: `20260118003017-2 Some Title.txt`.
- Title with illegal chars: correctly sanitized.

### body / formatTags
- `""` → `Nothing`.
- `"   "` → `Nothing`.
- `"alpha"` → `Just "Tags: #alpha"`.
- `"alpha beta"` → `Just "Tags: #alpha, #beta"`.
- `"  alpha   beta  "` → `Just "Tags: #alpha, #beta"`.

### body (assembly)
- With tags and each markup variant (markdown, scripta, plaintext).
- With no tags — `Tags:` line absent.
- Body ending with one trailing `\n` — blank-line separator remains one blank line.
- Body ending with several trailing `\n`s — trimmed to one blank line.
- Empty body → starts with a blank line, then trailer. (Acceptable; matches
  "body, blank line, trailer, trailing newline" literally.)

## Dependencies

- Promote `elm/file` from indirect to direct in `frontend/elm.json`
  (`dependencies.direct` section).
- No new backend deps, no migrations.

## Out of scope / future work

- A "Export all my snippets" bulk action.
- File System Access API path for Chromium users (write directly to a chosen
  Archive directory without the Downloads detour).
- List-view per-row Export button.
- Making Tags line and markup line parsers so that files can be re-imported.

## Open assumptions flagged

- The user's Archive tool does not require a BOM or specific encoding; we emit
  UTF-8 (Elm's default string encoding).
- `text/plain` is the right MIME for both Markdown and Scripta source files.
  (The Archive's files are always `.txt` by convention.)
- 120-char title truncation is generous enough; the combined filename stays
  under any realistic FS limit (14 + 1 + 120 + 4 = 139 bytes worst case ASCII).
