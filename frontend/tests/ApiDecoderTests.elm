module ApiDecoderTests exposing (suite)

import Expect
import Test exposing (Test, describe, test)


suite : Test
suite =
    describe "placeholder"
        [ test "1 + 1 == 2" (\_ -> Expect.equal 2 (1 + 1))
        ]
