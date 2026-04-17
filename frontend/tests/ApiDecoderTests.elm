module ApiDecoderTests exposing (suite)

import Api
import Expect
import Json.Decode as D
import Test exposing (Test, describe, test)
import Types exposing (Markup(..))


suite : Test
suite =
    describe "Api decoders"
        [ test "userDecoder" <|
            \_ ->
                let
                    json =
                        "{\"id\":\"u1\",\"email\":\"a@b.c\"}"
                in
                D.decodeString Api.userDecoder json
                    |> Expect.equal (Ok { id = "u1", email = "a@b.c" })

        , test "authResponseDecoder" <|
            \_ ->
                let
                    json =
                        "{\"token\":\"abc\",\"user\":{\"id\":\"u1\",\"email\":\"a@b.c\"}}"
                in
                D.decodeString Api.authResponseDecoder json
                    |> Expect.equal (Ok ( "abc", { id = "u1", email = "a@b.c" } ))

        , test "snippetDecoder (markdown)" <|
            \_ ->
                let
                    json =
                        "{\"id\":\"s1\",\"userId\":\"u1\",\"title\":\"t\",\"tags\":\"a b\",\"markup\":\"markdown\",\"body\":\"# h\",\"createdAt\":\"2026-04-17T12:00:00Z\",\"updatedAt\":\"2026-04-17T12:00:00Z\"}"
                in
                D.decodeString Api.snippetDecoder json
                    |> Result.map (\s -> ( s.id, s.title, s.markup ))
                    |> Expect.equal (Ok ( "s1", "t", Markdown ))

        , test "snippetDecoder (scripta)" <|
            \_ ->
                let
                    json =
                        "{\"id\":\"s2\",\"userId\":\"u1\",\"title\":\"\",\"tags\":\"\",\"markup\":\"scripta\",\"body\":\"\",\"createdAt\":\"2026-04-17T12:00:00Z\",\"updatedAt\":\"2026-04-17T12:00:00Z\"}"
                in
                D.decodeString Api.snippetDecoder json
                    |> Result.map .markup
                    |> Expect.equal (Ok Scripta)

        , test "snippetDecoder rejects unknown markup" <|
            \_ ->
                let
                    json =
                        "{\"id\":\"s3\",\"userId\":\"u1\",\"title\":\"\",\"tags\":\"\",\"markup\":\"latex\",\"body\":\"\",\"createdAt\":\"2026-04-17T12:00:00Z\",\"updatedAt\":\"2026-04-17T12:00:00Z\"}"
                in
                D.decodeString Api.snippetDecoder json
                    |> (\r -> case r of
                            Ok _  -> Expect.fail "expected decode error"
                            Err _ -> Expect.pass)
        ]
