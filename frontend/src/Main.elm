module Main exposing (main)

import Browser
import Html exposing (text)


main : Program () () ()
main =
    Browser.element
        { init = \_ -> ( (), Cmd.none )
        , update = \_ _ -> ( (), Cmd.none )
        , view = \_ -> text "greppit"
        , subscriptions = \_ -> Sub.none
        }
