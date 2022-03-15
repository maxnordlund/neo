-ifdef(TEST).

-define(function_test(Call, Arguments, Examples), [
    case Tuple of
        {Arguments, Expected} ->
            {neo_test_helpers:format_call(??Call, Arguments), fun() ->
                ?assertEqual(Expected, Call)
            end};
        _Otherwise ->
            {??Call, fun() ->
                io:format(
                    "Bad test example. Must be a `[Arg1, Arg2, ...] => Expected` mapping.~n"
                ),
                io:format("Maybe you forgot to wrap the arguments in brackets?~n"),
                %% To allow easy opening in your favorite editor
                io:format("~s:~p", [?FILE, ?LINE]),
                error(
                    {assertMatch_failed, [
                        {module, ?MODULE},
                        {line, ?LINE},
                        {expression, neo_test_helpers:format("~w", [Tuple])},
                        {pattern,
                            neo_test_helpers:format("{~s, Expected}", [??Arguments])},
                        {value, Tuple}
                    ]}
                )
            end}
    end
 || Tuple <- maps:to_list(Examples)
]).

-endif.
