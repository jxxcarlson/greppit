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
