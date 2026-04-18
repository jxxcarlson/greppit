module Auth exposing (view)

import Html exposing (Html, a, button, div, form, h2, input, label, text)
import Html.Attributes exposing (autofocus, class, disabled, placeholder, type_, value)
import Html.Events exposing (onClick, onInput, onSubmit)
import Types exposing (AuthForm, AuthMode(..), Msg(..))


view : AuthForm -> Html Msg
view f =
    div [ class "auth-page" ]
        [ div [ class "auth-tagline" ]
            [ text "Greppit: a manager for snippets of text. Supports extended markdown and plain text." ]
        , div [ class "auth-form" ]
            [ h2 []
                [ text
                    (case f.mode of
                        LoginMode  -> "Sign in to greppit"
                        SignupMode -> "Create a greppit account"
                    )
                ]
            , case f.errorMessage of
                Just m ->
                    div [ class "auth-error" ] [ text m ]

                Nothing ->
                    text ""
            , form [ onSubmit AuthSubmitted ]
                [ div [ class "auth-field" ]
                    [ label [] [ text "Email" ]
                    , input
                        [ type_ "email"
                        , autofocus True
                        , placeholder "you@example.com"
                        , value f.email
                        , onInput AuthEmailChanged
                        ]
                        []
                    ]
                , div [ class "auth-field" ]
                    [ label [] [ text "Password" ]
                    , input
                        [ type_ "password"
                        , placeholder "Password"
                        , value f.password
                        , onInput AuthPasswordChanged
                        ]
                        []
                    ]
                , button
                    [ type_ "submit"
                    , class "btn btn-primary"
                    , disabled f.submitting
                    ]
                    [ text
                        (case f.mode of
                            LoginMode  -> if f.submitting then "Signing in..." else "Sign in"
                            SignupMode -> if f.submitting then "Creating..."   else "Create account"
                        )
                    ]
                ]
            , div [ class "auth-link" ]
                (case f.mode of
                    LoginMode ->
                        [ text "No account? "
                        , a [ onClick (AuthSwitchMode SignupMode) ] [ text "Sign up" ]
                        ]

                    SignupMode ->
                        [ text "Have an account? "
                        , a [ onClick (AuthSwitchMode LoginMode) ] [ text "Sign in" ]
                        ]
                )
            ]
        ]
