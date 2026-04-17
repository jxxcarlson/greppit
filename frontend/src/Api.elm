module Api exposing
    ( signup, login, me
    , listSnippets, createSnippet, updateSnippet, deleteSnippet
    , userDecoder, snippetDecoder, authResponseDecoder
    )

import Http
import Iso8601
import Json.Decode as D
import Json.Encode as E
import Types exposing (Markup(..), Snippet, User, markupToString, stringToMarkup)
import Url.Builder


authHeader : String -> Http.Header
authHeader token =
    Http.header "Authorization" ("Bearer " ++ token)


userDecoder : D.Decoder User
userDecoder =
    D.map2 User
        (D.field "id" D.string)
        (D.field "email" D.string)


authResponseDecoder : D.Decoder ( String, User )
authResponseDecoder =
    D.map2 Tuple.pair
        (D.field "token" D.string)
        (D.field "user" userDecoder)


markupDecoder : D.Decoder Markup
markupDecoder =
    D.string
        |> D.andThen
            (\s ->
                case stringToMarkup s of
                    Just m  -> D.succeed m
                    Nothing -> D.fail ("Unknown markup: " ++ s)
            )


snippetDecoder : D.Decoder Snippet
snippetDecoder =
    D.map8 Snippet
        (D.field "id" D.string)
        (D.field "userId" D.string)
        (D.field "title" D.string)
        (D.field "tags" D.string)
        (D.field "markup" markupDecoder)
        (D.field "body" D.string)
        (D.field "createdAt" Iso8601.decoder)
        (D.field "updatedAt" Iso8601.decoder)


credsEncoder : { email : String, password : String } -> E.Value
credsEncoder creds =
    E.object
        [ ( "email", E.string creds.email )
        , ( "password", E.string creds.password )
        ]


signup :
    String
    -> { email : String, password : String }
    -> (Result Http.Error ( String, User ) -> msg)
    -> Cmd msg
signup apiBase creds toMsg =
    Http.post
        { url = apiBase ++ "/api/auth/signup"
        , body = Http.jsonBody (credsEncoder creds)
        , expect = Http.expectJson toMsg authResponseDecoder
        }


login :
    String
    -> { email : String, password : String }
    -> (Result Http.Error ( String, User ) -> msg)
    -> Cmd msg
login apiBase creds toMsg =
    Http.post
        { url = apiBase ++ "/api/auth/login"
        , body = Http.jsonBody (credsEncoder creds)
        , expect = Http.expectJson toMsg authResponseDecoder
        }


me : String -> String -> (Result Http.Error User -> msg) -> Cmd msg
me apiBase token toMsg =
    Http.request
        { method = "GET"
        , headers = [ authHeader token ]
        , url = apiBase ++ "/api/auth/me"
        , body = Http.emptyBody
        , expect = Http.expectJson toMsg userDecoder
        , timeout = Nothing
        , tracker = Nothing
        }


listSnippets :
    String
    -> String
    -> String
    -> (Result Http.Error (List Snippet) -> msg)
    -> Cmd msg
listSnippets apiBase token query toMsg =
    let
        url =
            Url.Builder.crossOrigin
                apiBase
                [ "api", "snippets" ]
                (if String.isEmpty (String.trim query) then
                    []
                 else
                    [ Url.Builder.string "q" query ]
                )
    in
    Http.request
        { method = "GET"
        , headers = [ authHeader token ]
        , url = url
        , body = Http.emptyBody
        , expect = Http.expectJson toMsg (D.list snippetDecoder)
        , timeout = Nothing
        , tracker = Nothing
        }


type alias SnippetInput =
    { title : String, tags : String, markup : Markup, body : String }


snippetInputEncoder : SnippetInput -> E.Value
snippetInputEncoder s =
    E.object
        [ ( "title", E.string s.title )
        , ( "tags", E.string s.tags )
        , ( "markup", E.string (markupToString s.markup) )
        , ( "body", E.string s.body )
        ]


createSnippet :
    String -> String -> SnippetInput
    -> (Result Http.Error Snippet -> msg)
    -> Cmd msg
createSnippet apiBase token input toMsg =
    Http.request
        { method = "POST"
        , headers = [ authHeader token ]
        , url = apiBase ++ "/api/snippets"
        , body = Http.jsonBody (snippetInputEncoder input)
        , expect = Http.expectJson toMsg snippetDecoder
        , timeout = Nothing
        , tracker = Nothing
        }


updateSnippet :
    String -> String -> String -> SnippetInput
    -> (Result Http.Error Snippet -> msg)
    -> Cmd msg
updateSnippet apiBase token sid input toMsg =
    Http.request
        { method = "PUT"
        , headers = [ authHeader token ]
        , url = apiBase ++ "/api/snippets/" ++ sid
        , body = Http.jsonBody (snippetInputEncoder input)
        , expect = Http.expectJson toMsg snippetDecoder
        , timeout = Nothing
        , tracker = Nothing
        }


deleteSnippet :
    String -> String -> String
    -> (Result Http.Error () -> msg)
    -> Cmd msg
deleteSnippet apiBase token sid toMsg =
    Http.request
        { method = "DELETE"
        , headers = [ authHeader token ]
        , url = apiBase ++ "/api/snippets/" ++ sid
        , body = Http.emptyBody
        , expect = Http.expectWhatever toMsg
        , timeout = Nothing
        , tracker = Nothing
        }
