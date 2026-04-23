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
