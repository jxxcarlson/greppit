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
