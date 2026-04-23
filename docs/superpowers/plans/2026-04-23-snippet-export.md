# Snippet Export Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a per-snippet "Export" button in the editor that triggers a browser
download of a plain-text file named by the snippet's `zku_id` timestamp and
(sanitized) title, with body + tags + markup trailer.

**Architecture:** All client-side in Elm. A new pure module `Export.elm`
derives the filename and assembles the body; `Main.update` calls
`File.Download.string` on button press. The `zku_id` is already returned by
the backend JSON but not currently decoded on the frontend, so the plan first
plumbs it through the `Snippet` type.

**Tech Stack:** Elm 0.19.1, `elm/file` (promoted from indirect), `elm-test` for
unit tests. Spec: `docs/superpowers/specs/2026-04-23-snippet-export-design.md`.

---

## File Structure

- **Create:** `frontend/src/Export.elm` — pure functions: `filename`, `body`,
  `sanitizeTitle`, `baseIdOf`, `formatTags`.
- **Create:** `frontend/tests/ExportTests.elm` — elm-test suite.
- **Modify:** `frontend/elm.json` — promote `elm/file` indirect → direct.
- **Modify:** `frontend/src/Types.elm` — add `zkuId : String` to `Snippet`;
  add `ExportPressed` to `Msg`.
- **Modify:** `frontend/src/Api.elm` — decode `zkuId` (9-field decoder via
  `andMap` pattern, since `elm/json` maxes out at `map8`).
- **Modify:** `frontend/tests/ApiDecoderTests.elm` — update JSON fixtures to
  include `zkuId`.
- **Modify:** `frontend/src/Editor.elm` — add Export button.
- **Modify:** `frontend/src/Main.elm` — import `File.Download` and `Export`;
  handle `ExportPressed`.

---

## Task 1: Promote `elm/file` to direct dependency

**Files:**
- Modify: `frontend/elm.json`

- [ ] **Step 1: Edit elm.json**

Move `"elm/file": "1.0.5"` from `dependencies.indirect` to `dependencies.direct`.
Resulting shape of the `dependencies` block:

```json
"dependencies": {
    "direct": {
        "elm/browser": "1.0.2",
        "elm/core": "1.0.5",
        "elm/file": "1.0.5",
        "elm/html": "1.0.1",
        "elm/http": "2.0.0",
        "elm/json": "1.1.4",
        "elm/parser": "1.1.0",
        "elm/regex": "1.0.0",
        "elm/time": "1.0.0",
        "elm/url": "1.0.0",
        "rtfeldman/elm-iso8601-date-strings": "1.1.4"
    },
    "indirect": {
        "elm/bytes": "1.0.8",
        "elm/virtual-dom": "1.0.5"
    }
},
```

- [ ] **Step 2: Verify the project still compiles**

Run (from `frontend/`): `elm make src/Main.elm --output=/dev/null`
Expected: success, no errors.

- [ ] **Step 3: Commit**

```bash
git add frontend/elm.json
git commit -m "chore(frontend): promote elm/file to direct dependency

Needed for upcoming Export.elm module using File.Download.string."
```

---

## Task 2: Plumb `zkuId` through the Elm `Snippet` type

The backend already returns `zkuId` in JSON (see
`backend/src/Api/RequestTypes.hs:58-70` — `spRespZkuId` becomes `zkuId` after
the 6-char prefix strip). The frontend type and decoder don't use it yet.

**Files:**
- Modify: `frontend/src/Types.elm`
- Modify: `frontend/src/Api.elm`
- Modify: `frontend/tests/ApiDecoderTests.elm`

- [ ] **Step 1: Update one decoder test to require `zkuId`**

In `frontend/tests/ApiDecoderTests.elm`, change the `"snippetDecoder (markdown)"`
test to include `zkuId` in the JSON and assert it decodes. Replace that test
block with:

```elm
        , test "snippetDecoder (markdown)" <|
            \_ ->
                let
                    json =
                        "{\"id\":\"s1\",\"userId\":\"u1\",\"zkuId\":\"alice-20260118003017\",\"title\":\"t\",\"tags\":\"a b\",\"markup\":\"markdown\",\"body\":\"# h\",\"createdAt\":\"2026-04-17T12:00:00Z\",\"updatedAt\":\"2026-04-17T12:00:00Z\"}"
                in
                D.decodeString Api.snippetDecoder json
                    |> Result.map (\s -> ( s.id, s.zkuId, s.markup ))
                    |> Expect.equal (Ok ( "s1", "alice-20260118003017", Markdown ))
```

- [ ] **Step 2: Run tests to verify the new expectation fails**

Run (from `frontend/`): `elm-test tests/ApiDecoderTests.elm`
Expected: compile error — `Snippet` has no `zkuId` field.

- [ ] **Step 3: Add `zkuId` to the `Snippet` record in `Types.elm`**

In `frontend/src/Types.elm`, update the `Snippet` type alias (currently lines
57–66). Place `zkuId` immediately after `userId` to mirror the backend's
`stripPrefixOptions 6` JSON order:

```elm
type alias Snippet =
    { id : String
    , userId : String
    , zkuId : String
    , title : String
    , tags : String
    , markup : Markup
    , body : String
    , createdAt : Posix
    , updatedAt : Posix
    }
```

- [ ] **Step 4: Update `snippetDecoder` to decode `zkuId`**

`elm/json` only exposes `map` through `map8`, and `Snippet` now has 9 fields.
Use the standard `andMap` applicative pattern. Replace the existing decoder in
`frontend/src/Api.elm` (currently lines 45–55) with:

```elm
andMap : D.Decoder a -> D.Decoder (a -> b) -> D.Decoder b
andMap =
    D.map2 (|>)


snippetDecoder : D.Decoder Snippet
snippetDecoder =
    D.succeed Snippet
        |> andMap (D.field "id" D.string)
        |> andMap (D.field "userId" D.string)
        |> andMap (D.field "zkuId" D.string)
        |> andMap (D.field "title" D.string)
        |> andMap (D.field "tags" D.string)
        |> andMap (D.field "markup" markupDecoder)
        |> andMap (D.field "body" D.string)
        |> andMap (D.field "createdAt" Iso8601.decoder)
        |> andMap (D.field "updatedAt" Iso8601.decoder)
```

- [ ] **Step 5: Update the remaining decoder tests to include `zkuId`**

In `frontend/tests/ApiDecoderTests.elm`, add `"zkuId":"..."` to each of the
other three snippet JSON fixtures (scripta, plaintext, unknown-markup).
Suggested values: `"bob-20260118003017"`, `"carol-20260118003017"`,
`"dave-20260118003017"` respectively. No assertion changes needed — those
tests only check `.markup` or the error path.

Example — the scripta test after edit:

```elm
        , test "snippetDecoder (scripta)" <|
            \_ ->
                let
                    json =
                        "{\"id\":\"s2\",\"userId\":\"u1\",\"zkuId\":\"bob-20260118003017\",\"title\":\"\",\"tags\":\"\",\"markup\":\"scripta\",\"body\":\"\",\"createdAt\":\"2026-04-17T12:00:00Z\",\"updatedAt\":\"2026-04-17T12:00:00Z\"}"
                in
                D.decodeString Api.snippetDecoder json
                    |> Result.map .markup
                    |> Expect.equal (Ok Scripta)
```

The plaintext test after edit:

```elm
        , test "snippetDecoder (plaintext)" <|
            \_ ->
                let
                    json =
                        "{\"id\":\"s4\",\"userId\":\"u1\",\"zkuId\":\"carol-20260118003017\",\"title\":\"\",\"tags\":\"\",\"markup\":\"plaintext\",\"body\":\"line1\\nline2\",\"createdAt\":\"2026-04-17T12:00:00Z\",\"updatedAt\":\"2026-04-17T12:00:00Z\"}"
                in
                D.decodeString Api.snippetDecoder json
                    |> Result.map .markup
                    |> Expect.equal (Ok PlainText)
```

The unknown-markup test after edit:

```elm
        , test "snippetDecoder rejects unknown markup" <|
            \_ ->
                let
                    json =
                        "{\"id\":\"s3\",\"userId\":\"u1\",\"zkuId\":\"dave-20260118003017\",\"title\":\"\",\"tags\":\"\",\"markup\":\"latex\",\"body\":\"\",\"createdAt\":\"2026-04-17T12:00:00Z\",\"updatedAt\":\"2026-04-17T12:00:00Z\"}"
                in
                D.decodeString Api.snippetDecoder json
                    |> (\r -> case r of
                            Ok _  -> Expect.fail "expected decode error"
                            Err _ -> Expect.pass)
```

- [ ] **Step 6: Run all tests**

Run (from `frontend/`): `elm-test`
Expected: all tests pass.

- [ ] **Step 7: Verify the main compile still works**

Run (from `frontend/`): `elm make src/Main.elm --output=/dev/null`
Expected: success.

- [ ] **Step 8: Commit**

```bash
git add frontend/src/Types.elm frontend/src/Api.elm frontend/tests/ApiDecoderTests.elm
git commit -m "feat(frontend): decode zkuId into Snippet

Backend has always returned zkuId in SnippetResponse; now the Elm
decoder consumes it. Switches snippetDecoder to the andMap applicative
pattern since map8 is not enough for 9 fields."
```

---

## Task 3: `Export.baseIdOf`

**Files:**
- Create: `frontend/src/Export.elm`
- Create: `frontend/tests/ExportTests.elm`

- [ ] **Step 1: Write the failing tests**

Create `frontend/tests/ExportTests.elm` with:

```elm
module ExportTests exposing (suite)

import Expect
import Export
import Test exposing (Test, describe, test)


suite : Test
suite =
    describe "Export"
        [ describe "baseIdOf"
            [ test "strips username prefix" <|
                \_ ->
                    Export.baseIdOf "jxxcarlson-20260118003017"
                        |> Expect.equal "20260118003017"
            , test "preserves collision suffix" <|
                \_ ->
                    Export.baseIdOf "jxxcarlson-20260118003017-2"
                        |> Expect.equal "20260118003017-2"
            , test "splits on the first dash only" <|
                \_ ->
                    Export.baseIdOf "ab-cd-ef"
                        |> Expect.equal "cd-ef"
            , test "returns the input when no dash is present" <|
                \_ ->
                    Export.baseIdOf "nodash"
                        |> Expect.equal "nodash"
            ]
        ]
```

- [ ] **Step 2: Run tests and verify compile error**

Run (from `frontend/`): `elm-test tests/ExportTests.elm`
Expected: FAIL — module `Export` not found.

- [ ] **Step 3: Create minimal `Export.elm` with `baseIdOf`**

Create `frontend/src/Export.elm`:

```elm
module Export exposing (baseIdOf)


{-| Strip a zku_id's username prefix. Takes everything after the first '-'.
If there is no '-', returns the input unchanged.
-}
baseIdOf : String -> String
baseIdOf zkuId =
    case String.indexes "-" zkuId of
        [] ->
            zkuId

        firstDashIndex :: _ ->
            String.dropLeft (firstDashIndex + 1) zkuId
```

- [ ] **Step 4: Run tests**

Run (from `frontend/`): `elm-test tests/ExportTests.elm`
Expected: PASS — 4 tests pass.

- [ ] **Step 5: Commit**

```bash
git add frontend/src/Export.elm frontend/tests/ExportTests.elm
git commit -m "feat(export): add Export.baseIdOf

First pure helper toward per-snippet export: strips the username
prefix from a zku_id to yield the 14-digit timestamp (plus any
collision suffix)."
```

---

## Task 4: `Export.sanitizeTitle`

**Files:**
- Modify: `frontend/src/Export.elm`
- Modify: `frontend/tests/ExportTests.elm`

- [ ] **Step 1: Add failing tests for `sanitizeTitle`**

In `frontend/tests/ExportTests.elm`, add a new `describe` block inside the
top-level list (after the `baseIdOf` block):

```elm
        , describe "sanitizeTitle"
            [ test "preserves plain ASCII" <|
                \_ ->
                    Export.sanitizeTitle "Painting Random Walk"
                        |> Expect.equal "Painting Random Walk"
            , test "replaces illegal filename chars with space and collapses" <|
                \_ ->
                    Export.sanitizeTitle "Notes: 2026/04"
                        |> Expect.equal "Notes 2026 04"
            , test "replaces all of / \\ : * ? \" < > |" <|
                \_ ->
                    Export.sanitizeTitle "a/b\\c:d*e?f\"g<h>i|j"
                        |> Expect.equal "a b c d e f g h i j"
            , test "replaces control characters with space" <|
                \_ ->
                    Export.sanitizeTitle "foo\tbar\nbaz"
                        |> Expect.equal "foo bar baz"
            , test "drops non-ASCII characters" <|
                \_ ->
                    Export.sanitizeTitle "Café notes"
                        |> Expect.equal "Caf notes"
            , test "all-non-ASCII yields empty" <|
                \_ ->
                    Export.sanitizeTitle "思考"
                        |> Expect.equal ""
            , test "empty input yields empty" <|
                \_ ->
                    Export.sanitizeTitle ""
                        |> Expect.equal ""
            , test "whitespace-only yields empty" <|
                \_ ->
                    Export.sanitizeTitle "   \t  "
                        |> Expect.equal ""
            , test "truncates at 120 chars" <|
                \_ ->
                    Export.sanitizeTitle (String.repeat 200 "a")
                        |> String.length
                        |> Expect.equal 120
            ]
```

- [ ] **Step 2: Run tests and verify failure**

Run (from `frontend/`): `elm-test tests/ExportTests.elm`
Expected: FAIL — `Export.sanitizeTitle` not found.

- [ ] **Step 3: Implement `sanitizeTitle` in `Export.elm`**

Update `frontend/src/Export.elm` to (full file):

```elm
module Export exposing (baseIdOf, sanitizeTitle)

import Char


{-| Strip a zku_id's username prefix. Takes everything after the first '-'.
If there is no '-', returns the input unchanged.
-}
baseIdOf : String -> String
baseIdOf zkuId =
    case String.indexes "-" zkuId of
        [] ->
            zkuId

        firstDashIndex :: _ ->
            String.dropLeft (firstDashIndex + 1) zkuId


{-| Sanitize a title for use as the descriptive part of a filename.

Rules (applied in order):
1. Replace each of / \ : * ? " < > | with a single space.
2. Replace ASCII control chars (0-31, 127) with a single space.
3. Drop all non-ASCII (code point >= 128).
4. Collapse runs of whitespace to a single space.
5. Trim leading/trailing whitespace.
6. Truncate to 120 chars.
-}
sanitizeTitle : String -> String
sanitizeTitle raw =
    raw
        |> String.map replaceIllegal
        |> String.filter isAscii
        |> String.words
        |> String.join " "
        |> String.left 120


replaceIllegal : Char -> Char
replaceIllegal c =
    let
        code =
            Char.toCode c
    in
    if code < 32 || code == 127 then
        ' '

    else
        case c of
            '/' ->
                ' '

            '\\' ->
                ' '

            ':' ->
                ' '

            '*' ->
                ' '

            '?' ->
                ' '

            '"' ->
                ' '

            '<' ->
                ' '

            '>' ->
                ' '

            '|' ->
                ' '

            _ ->
                c


isAscii : Char -> Bool
isAscii c =
    Char.toCode c < 128
```

Note: `String.words` both splits on any whitespace and drops empty tokens, so
`String.words >> String.join " "` collapses runs of whitespace and trims in a
single pass.

- [ ] **Step 4: Run tests**

Run (from `frontend/`): `elm-test tests/ExportTests.elm`
Expected: PASS — all tests pass (13 total so far).

- [ ] **Step 5: Commit**

```bash
git add frontend/src/Export.elm frontend/tests/ExportTests.elm
git commit -m "feat(export): add Export.sanitizeTitle

Applies the filename-safety rule: replace /\\\\:*?\"<>| and controls
with space, drop non-ASCII, collapse whitespace, truncate at 120."
```

---

## Task 5: `Export.filename`

**Files:**
- Modify: `frontend/src/Export.elm`
- Modify: `frontend/tests/ExportTests.elm`

This task assembles `baseIdOf` + `sanitizeTitle` into the full filename. It
takes a `Snippet` value, so the tests need a helper to build one.

- [ ] **Step 1: Add failing tests for `filename`**

In `frontend/tests/ExportTests.elm`, add at the top of the file (below the
existing imports):

```elm
import Time
import Types exposing (Markup(..), Snippet)


fixture : { zkuId : String, title : String } -> Snippet
fixture x =
    { id = "00000000-0000-0000-0000-000000000000"
    , userId = "u1"
    , zkuId = x.zkuId
    , title = x.title
    , tags = ""
    , markup = Markdown
    , body = ""
    , createdAt = Time.millisToPosix 0
    , updatedAt = Time.millisToPosix 0
    }
```

Then add a new `describe` block to `suite`:

```elm
        , describe "filename"
            [ test "base id + sanitized title" <|
                \_ ->
                    fixture { zkuId = "jxxcarlson-20260118003017", title = "Painting Random Walk" }
                        |> Export.filename
                        |> Expect.equal "20260118003017 Painting Random Walk.txt"
            , test "empty title uses base id alone" <|
                \_ ->
                    fixture { zkuId = "jxxcarlson-20260118003017", title = "" }
                        |> Export.filename
                        |> Expect.equal "20260118003017.txt"
            , test "whitespace-only title uses base id alone" <|
                \_ ->
                    fixture { zkuId = "jxxcarlson-20260118003017", title = "   " }
                        |> Export.filename
                        |> Expect.equal "20260118003017.txt"
            , test "all-non-ASCII title uses base id alone" <|
                \_ ->
                    fixture { zkuId = "jxxcarlson-20260118003017", title = "思考" }
                        |> Export.filename
                        |> Expect.equal "20260118003017.txt"
            , test "collision suffix is preserved" <|
                \_ ->
                    fixture { zkuId = "jxxcarlson-20260118003017-2", title = "Some Title" }
                        |> Export.filename
                        |> Expect.equal "20260118003017-2 Some Title.txt"
            , test "illegal chars sanitized" <|
                \_ ->
                    fixture { zkuId = "jxxcarlson-20260118003017", title = "a/b:c" }
                        |> Export.filename
                        |> Expect.equal "20260118003017 a b c.txt"
            ]
```

- [ ] **Step 2: Run tests and verify failure**

Run (from `frontend/`): `elm-test tests/ExportTests.elm`
Expected: FAIL — `Export.filename` not found.

- [ ] **Step 3: Implement `filename` in `Export.elm`**

In `frontend/src/Export.elm`:

1. Add `Types` to imports:

```elm
import Types exposing (Snippet)
```

2. Expose `filename` in the module declaration:

```elm
module Export exposing (baseIdOf, filename, sanitizeTitle)
```

3. Add the function (append below `sanitizeTitle`):

```elm
{-| Derive the export filename from a Snippet.

Pattern: "<baseId> <sanitizedTitle>.txt" if the sanitized title is
non-empty, else "<baseId>.txt".
-}
filename : Snippet -> String
filename snippet =
    let
        base =
            baseIdOf snippet.zkuId

        sanitized =
            sanitizeTitle snippet.title
    in
    if String.isEmpty sanitized then
        base ++ ".txt"

    else
        base ++ " " ++ sanitized ++ ".txt"
```

- [ ] **Step 4: Run tests**

Run (from `frontend/`): `elm-test tests/ExportTests.elm`
Expected: PASS — all tests pass.

- [ ] **Step 5: Commit**

```bash
git add frontend/src/Export.elm frontend/tests/ExportTests.elm
git commit -m "feat(export): add Export.filename

Assembles baseId + sanitized title + .txt; falls back to
'<baseId>.txt' when the title is empty or drops to empty after
sanitization."
```

---

## Task 6: `Export.formatTags`

**Files:**
- Modify: `frontend/src/Export.elm`
- Modify: `frontend/tests/ExportTests.elm`

- [ ] **Step 1: Add failing tests for `formatTags`**

In `frontend/tests/ExportTests.elm`, add a new `describe` block:

```elm
        , describe "formatTags"
            [ test "empty string returns Nothing" <|
                \_ ->
                    Export.formatTags ""
                        |> Expect.equal Nothing
            , test "whitespace-only returns Nothing" <|
                \_ ->
                    Export.formatTags "   "
                        |> Expect.equal Nothing
            , test "single tag" <|
                \_ ->
                    Export.formatTags "alpha"
                        |> Expect.equal (Just "Tags: #alpha")
            , test "multiple tags joined with comma" <|
                \_ ->
                    Export.formatTags "alpha beta"
                        |> Expect.equal (Just "Tags: #alpha, #beta")
            , test "ignores extra whitespace between tags" <|
                \_ ->
                    Export.formatTags "  alpha   beta  "
                        |> Expect.equal (Just "Tags: #alpha, #beta")
            ]
```

- [ ] **Step 2: Run tests and verify failure**

Run (from `frontend/`): `elm-test tests/ExportTests.elm`
Expected: FAIL — `Export.formatTags` not found.

- [ ] **Step 3: Implement `formatTags`**

Expose it in `Export.elm`:

```elm
module Export exposing (baseIdOf, filename, formatTags, sanitizeTitle)
```

Append the function:

```elm
{-| Format a space-separated tags string as a single "Tags: #a, #b" line.
Returns Nothing when there are no tags.
-}
formatTags : String -> Maybe String
formatTags raw =
    case String.words raw of
        [] ->
            Nothing

        tokens ->
            Just ("Tags: " ++ String.join ", " (List.map (\t -> "#" ++ t) tokens))
```

- [ ] **Step 4: Run tests**

Run (from `frontend/`): `elm-test tests/ExportTests.elm`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add frontend/src/Export.elm frontend/tests/ExportTests.elm
git commit -m "feat(export): add Export.formatTags

Space-separated tags -> 'Tags: #a, #b' line, or Nothing when empty.
elm/core's String.words drops empty tokens automatically."
```

---

## Task 7: `Export.body`

**Files:**
- Modify: `frontend/src/Export.elm`
- Modify: `frontend/tests/ExportTests.elm`

- [ ] **Step 1: Add failing tests for `body`**

In `frontend/tests/ExportTests.elm`, add:

```elm
        , describe "body"
            [ test "with tags and markdown markup" <|
                \_ ->
                    { (fixture { zkuId = "jxxcarlson-20260118003017", title = "t" })
                        | body = "Some body text."
                        , tags = "alpha beta"
                        , markup = Markdown
                    }
                        |> Export.body
                        |> Expect.equal "Some body text.\n\nTags: #alpha, #beta\nmarkup: markdown\n"
            , test "omits Tags line when no tags" <|
                \_ ->
                    { (fixture { zkuId = "x-20260118003017", title = "t" })
                        | body = "Body."
                        , tags = ""
                        , markup = Markdown
                    }
                        |> Export.body
                        |> Expect.equal "Body.\n\nmarkup: markdown\n"
            , test "scripta markup variant" <|
                \_ ->
                    { (fixture { zkuId = "x-20260118003017", title = "t" })
                        | body = "B"
                        , tags = ""
                        , markup = Scripta
                    }
                        |> Export.body
                        |> Expect.equal "B\n\nmarkup: scripta\n"
            , test "plaintext markup variant" <|
                \_ ->
                    { (fixture { zkuId = "x-20260118003017", title = "t" })
                        | body = "B"
                        , tags = ""
                        , markup = PlainText
                    }
                        |> Export.body
                        |> Expect.equal "B\n\nmarkup: plaintext\n"
            , test "trims trailing newlines from body to one blank separator" <|
                \_ ->
                    { (fixture { zkuId = "x-20260118003017", title = "t" })
                        | body = "B\n\n\n"
                        , tags = ""
                        , markup = Markdown
                    }
                        |> Export.body
                        |> Expect.equal "B\n\nmarkup: markdown\n"
            ]
```

- [ ] **Step 2: Run tests and verify failure**

Run (from `frontend/`): `elm-test tests/ExportTests.elm`
Expected: FAIL — `Export.body` not found.

- [ ] **Step 3: Implement `body`**

In `frontend/src/Export.elm`, import `markupToString` from Types (extend the
existing import):

```elm
import Types exposing (Snippet, markupToString)
```

Expose `body` by updating the module declaration:

```elm
module Export exposing (baseIdOf, body, filename, formatTags, sanitizeTitle)
```

Append the function:

```elm
{-| Assemble the exported file body:

    <body with trailing newlines trimmed>
    <one blank line>
    Tags: #a, #b        (omitted entirely if no tags)
    markup: <markup>
    <trailing newline>

-}
body : Snippet -> String
body snippet =
    let
        trimmedBody =
            stripTrailingNewlines snippet.body

        trailerLines =
            case formatTags snippet.tags of
                Just tagsLine ->
                    [ tagsLine, "markup: " ++ markupToString snippet.markup ]

                Nothing ->
                    [ "markup: " ++ markupToString snippet.markup ]
    in
    trimmedBody ++ "\n\n" ++ String.join "\n" trailerLines ++ "\n"


stripTrailingNewlines : String -> String
stripTrailingNewlines s =
    if String.endsWith "\n" s then
        stripTrailingNewlines (String.dropRight 1 s)

    else
        s
```

- [ ] **Step 4: Run tests**

Run (from `frontend/`): `elm-test`
Expected: all tests across both suites pass.

- [ ] **Step 5: Commit**

```bash
git add frontend/src/Export.elm frontend/tests/ExportTests.elm
git commit -m "feat(export): add Export.body

Assembles body + blank line + optional Tags: line + markup: line
+ trailing newline. Trims trailing newlines from user body so the
blank-line separator is always exactly one blank line."
```

---

## Task 8: Add `ExportPressed` to `Msg`

**Files:**
- Modify: `frontend/src/Types.elm`

- [ ] **Step 1: Add the constructor**

In `frontend/src/Types.elm`, append `ExportPressed` to the `Msg` type (line 147
currently ends with `SearchDebounceTick Int String`). Add a new line above it
or at the end — order doesn't matter functionally; put it near the other
editor-related constructors for readability:

```elm
type Msg
    = AuthEmailChanged String
    | AuthPasswordChanged String
    | AuthSwitchMode AuthMode
    | AuthSubmitted
    | AuthResponded (Result Http.Error ( String, User ))
    | TokenValidated String (Result Http.Error User)
    | SignedOutPressed
    | SearchInputChanged String
    | SearchResponded (Result Http.Error (List Snippet))
    | SelectResult String
    | NewSnippetPressed
    | EditPressed Snippet
    | CancelEditor
    | EditorTitleChanged String
    | EditorTagsChanged String
    | EditorMarkupChanged Markup
    | EditorBodyChanged String
    | SaveSnippet
    | CreateResponded (Result Http.Error Snippet)
    | UpdateResponded (Result Http.Error Snippet)
    | DeletePressed
    | ConfirmDelete
    | CancelDelete
    | DeleteResponded String (Result Http.Error ())
    | ExportPressed
    | SearchDebounceTick Int String
```

- [ ] **Step 2: Verify compile**

Run (from `frontend/`): `elm make src/Main.elm --output=/dev/null`
Expected: compile error in `Main.elm` — `ExportPressed` is unhandled in the
`case msg of` expression. This is expected; we'll handle it in Task 10.

**Do not commit yet** — Tasks 8, 9, and 10 form a single wiring commit.

---

## Task 9: Add Export button to the editor

**Files:**
- Modify: `frontend/src/Editor.elm`

- [ ] **Step 1: Add the button**

In `frontend/src/Editor.elm`, locate the `if isEdit then ...` block that adds
the Delete button (currently lines 79–89). Prepend an Export button so the
row becomes `[Save] [Cancel] [Export] [Delete]`:

```elm
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
```

- [ ] **Step 2: Verify compile**

Run (from `frontend/`): `elm make src/Main.elm --output=/dev/null`
Expected: same compile error as Task 8 — `ExportPressed` unhandled in
`Main.update`. Resolve in Task 10.

---

## Task 10: Handle `ExportPressed` in `Main.update`

**Files:**
- Modify: `frontend/src/Main.elm`

- [ ] **Step 1: Add imports**

At the top of `frontend/src/Main.elm`, add:

```elm
import Export
import File.Download
```

Place them in alphabetical order with the existing imports (between `Editor`
and `Html`, and between `Editor`/`Export` and `File.Download`).

- [ ] **Step 2: Add the `ExportPressed` branch**

In `Main.update`, add a new branch in the `case msg of` expression (place it
near the other editor-related handlers — e.g. right after `CancelDelete`):

```elm
        ExportPressed ->
            case s.rightMode of
                EditorMode e ->
                    case e.editing of
                        Just snippet ->
                            ( model
                            , File.Download.string
                                (Export.filename snippet)
                                "text/plain"
                                (Export.body snippet)
                            )

                        Nothing ->
                            ( model, Cmd.none )

                _ ->
                    ( model, Cmd.none )
```

Note: `s` is the already-destructured `SignedInData` in scope — this mirrors
the existing `SaveSnippet` and `ConfirmDelete` branches.

- [ ] **Step 3: Verify compile**

Run (from `frontend/`): `elm make src/Main.elm --output=/dev/null`
Expected: success.

- [ ] **Step 4: Run full test suite**

Run (from `frontend/`): `elm-test`
Expected: all tests pass.

- [ ] **Step 5: Commit (covers Tasks 8, 9, 10)**

```bash
git add frontend/src/Types.elm frontend/src/Editor.elm frontend/src/Main.elm
git commit -m "feat(export): wire Export button into editor

Adds ExportPressed Msg, Export button in the editor action row (only
when editing an existing snippet), and a Main.update branch that
triggers File.Download.string with the filename and body produced by
the pure Export module."
```

---

## Task 11: Manual browser verification

**Files:** none (manual QA).

- [ ] **Step 1: Start backend and frontend**

From the repo root:

```bash
cd backend && ./run.sh &
cd frontend && ./run.sh
```

The frontend serves at `http://localhost:8011`; backend at `http://localhost:8085`.

- [ ] **Step 2: Exercise the happy path**

1. Open `http://localhost:8011`. Sign in (or sign up a new user).
2. Create a snippet: Title = `Painting Random Walk`, Tags = `alpha beta`,
   Markup = Markdown, Body = `# Hello\n\nWorld.`. Save.
3. Reopen the snippet in the editor (click it in the list, then Edit).
4. Click **Export**. The browser should download a file named roughly
   `<username>-20260423XXXXXX`-based — exact baseId will reflect the real
   creation time — e.g. `20260423120530 Painting Random Walk.txt`.
5. Open the downloaded file. Confirm the content:
   ```
   # Hello

   World.

   Tags: #alpha, #beta
   markup: markdown
   ```
   (Blank line between body and Tags line, trailing newline at EOF.)

- [ ] **Step 3: Exercise edge cases manually**

1. Snippet with empty title → filename is `<baseId>.txt`.
2. Snippet with no tags → exported file omits the `Tags:` line entirely.
3. Snippet with a title like `Plan: 2026/04` → filename becomes
   `<baseId> Plan 2026 04.txt`.
4. Snippet with markup = `scripta` or `plaintext` → trailer line reflects
   the choice.

- [ ] **Step 4: Confirm the button's visibility**

- Opening a brand-new (unsaved) snippet via "New snippet" — Export button
  should **not** appear (matches Delete button behavior).
- In Edit mode on an existing snippet — Export button visible.

- [ ] **Step 5: No commit**

Manual verification; nothing to commit unless you find a bug and fix it.

---

## Self-review checklist (for the implementer)

Before opening a PR:

- [ ] `elm-test` passes from `frontend/`.
- [ ] `elm make src/Main.elm --output=/dev/null` from `frontend/` succeeds.
- [ ] No `zku_id` collision-suffix examples trip up the filename builder.
- [ ] The Export button is disabled while `st.saving` (prevents click racing
      with in-flight Save).
- [ ] No unrelated changes slipped into any commit.
