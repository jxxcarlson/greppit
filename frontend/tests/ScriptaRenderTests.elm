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
