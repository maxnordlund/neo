-ifndef(NEO_TEST_HELPERS).
-define(NEO_TEST_HELPERS, true).

-include("assertions.hrl").

%% Dim red
-define(ATOM_NUMBER_COLOR(Options),
    (case maps:get(color, Options, true) of
        true -> "\e[2;31m";
        false -> ""
    end)
).
%% Dim yellow/orange
-define(NUMBER_COLOR(Options),
    (case maps:get(color, Options, true) of
        true -> "\e[2;33m";
        false -> ""
    end)
).
%% Yellow
-define(MODULE_RECORD_TAG_COLOR(Options),
    (case maps:get(color, Options, true) of
        true -> "\e[33m";
        false -> ""
    end)
).
%% Blue
-define(RECORD_FIELD_COLOR(Options),
    (case maps:get(color, Options, true) of
        true -> "\e[34m";
        false -> ""
    end)
).
%% Bold/bright magenta
-define(KEYWORD_COLOR(Options),
    (case maps:get(color, Options, true) of
        true -> "\e[1;35m";
        false -> ""
    end)
).
%% Green
-define(STRING_COLOR(Options),
    (case maps:get(color, Options, true) of
        true -> "\e[32m";
        false -> ""
    end)
).
%% Cyan
-define(OPERATOR_COLOR(Options),
    (case maps:get(color, Options, true) of
        true -> "\e[36m";
        false -> ""
    end)
).
-define(COMMENT_COLOR(Options),
    (case maps:get(color, Options, true) of
        true -> "\e[2;0m";
        false -> ""
    end)
).
-define(RESET(Options),
    (case maps:get(color, Options, true) of
        true -> "\e[0m";
        false -> ""
    end)
).

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
                        {expression, neo_test_helpers:flat_format("~w", [Tuple])},
                        {pattern,
                            neo_test_helpers:flat_format("{~s, Expected}", [??Arguments])},
                        {value, Tuple}
                    ]}
                )
            end}
    end
 || Tuple <- maps:to_list(Examples)
]).

%% @equiv ?quickcheck(RawType, Pattern, Property, [])
-define(quickcheck(RawType, Pattern, Property),
    ?quickcheck(RawType, Pattern, Property, [])
).
%% @equiv ?quickcheck(?forall(RawType, Pattern, Property), Options)
-define(quickcheck(RawType, Pattern, Property, Options),
    (fun(X__OuterTest, X__Options) ->
        ?__call_proper(
            proper:quickcheck(X__OuterTest, X__Options),
            X__Options,
            ??RawType,
            ??Pattern " when " ??Property
        )
    end)(
        ?forall(RawType, Pattern, Property),
        neo_test_helpers:proper_options(Options)
    )
).

%% Checks the given PropEr property and raises an `assertEqual' error if it
%% fails.
%%
%% This is needed to be able to run PropEr tests using EUnit. You can provide
%% a comment for the assertion error inside the `Options'.
-define(quickcheck(OuterTest, Options),
    (fun(X__Options) ->
        ?__call_proper(proper:quickcheck(OuterTest, X__Options), X__Options, "_", "_")
    end)(
        neo_test_helpers:proper_options(Options)
    )
).

%% @equiv ?_quickcheck(RawType, Pattern, Property, [])
-define(_quickcheck(RawType, Pattern, Property),
    ?_quickcheck(RawType, Pattern, Property, [])
).

%% @equiv ?_quickcheck(?forall(RawType, Pattern, Property), Options)
-define(_quickcheck(RawType, Pattern, Property, Options),
    (fun(X__OuterTest, X__Options) ->
        ?__proper_test_to_eunit(
            proper:quickcheck(X__OuterTest),
            X__Options,
            ??RawType,
            ??Pattern " when " ??Property
        )
    end)(
        ?forall(RawType, Pattern, Property),
        neo_test_helpers:proper_options(Options)
    )
).

%% Similar to the ?_assert* macros from EUnit, this returns a test function
%% checking the given PropEr property.
%%
%% @see ?quickcheck/2
-define(_quickcheck(OuterTest, Options),
    (fun(X__Options) ->
        ?__proper_test_to_eunit(
            proper:quickcheck(OuterTest, X__Options), X__Options, "_", "_"
        )
    end)(
        neo_test_helpers:proper_options(Options)
    )
).

%% @equiv ?counterexample(OuterTest, CounterExample, [])
-define(counterexample(OuterTest, CounterExample),
    ?counterexample(OuterTest, CounterExample, [])
).

-define(counterexample(OuterTest, CounterExample, Options),
    (fun(X__Options) ->
        ?__call_proper(
            proper:check(OuterTest, CounterExample, X__Options), X__Options, "_", "_"
        )
    end)(
        neo_test_helpers:proper_options(Options)
    )
).

%% @equiv ?_counterexample(OuterTest, CounterExample, [])
-define(_counterexample(OuterTest, CounterExample),
    ?_counterexample(OuterTest, CounterExample, [])
).

-define(_counterexample(OuterTest, CounterExample, Options),
    (fun(X__Options) ->
        ?__proper_test_to_eunit(
            proper:check(OuterTest, CounterExample, X__Options), X__Options, "_", "_"
        )
    end)(
        neo_test_helpers:proper_options(Options)
    )
).

%% Similar to `?FORALL(Patttern, RawType, Property)'.
%%
%% Unlike PropEr however, this also allows raising an assertion or returning
%% `ok' as well as returning a boolean.
-define(forall(RawType, Pattern, Property), begin
    erlang:put('neo_test:expression', ??RawType),
    erlang:put('neo_test:pattern', ??Pattern " when " ??Property),
    proper:forall(RawType, fun(Pattern) ->
        try Property of
            ok ->
                true;
            true ->
                true;
            false ->
                false
        catch
            error:{X__Type, X__Info}:X__Stacktrace when
                is_list(X__Info) andalso
                    %% Ordered by what's (assumed to be) most common
                    (?oneof(X__Type, assertEqual, assertMatch, assertNotEqual) orelse
                        ?oneof(X__Type, assertNotMatch, assert, assertException))
            ->
                erlang:put('neo_test:assertion', {X__Type, X__Info, X__Stacktrace}),
                false
        end
    end)
end).

-define(__proper_test_to_eunit(Call, Options, Expression, Pattern),
    (fun
        (X__Test, X__EUnitTimeout) when is_integer(X__EUnitTimeout) ->
            {timeout, X__EUnitTimeout, X__Test};
        (X__Test, _) ->
            X__Test
    end)(
        {?LINE, fun() -> ?__call_proper(Call, Options, Expression, Pattern) end},
        %% neo_test_helpers:proper_options sets `neo_eunit_timeout'
        %% It's the responsibility of the caller make sure it is set.
        erlang:get(neo_eunit_timeout)
    )
).

-define(__call_proper(Call, Options, Expression, Pattern), begin
    erlang:erase('neo_test:assertion'),
    case Call of
        true ->
            ok;
        false ->
            case erlang:get('neo_test:assertion') of
                {X__Assertion, X__Info, X__Stacktrace} ->
                    erlang:raise(error, {X__Assertion, X__Info}, X__Stacktrace);
                undefined ->
                    erlang:error(
                        {assertMatch, [
                            {module, ?MODULE},
                            {line, ?LINE},
                            %% Must escape ~ because it is output using `io:format/1'
                            {expression, string:replace(Expression, "~", "~~", all)},
                            {pattern, string:replace(Pattern, "~", "~~", all)},
                            {value, false}
                            | proplists:lookup_all(comment, Options)
                        ]}
                    )
            end;
        {error, X__Reason} ->
            erlang:error(
                {assertNotException, [
                    {module, ?MODULE},
                    {line, ?LINE},
                    {expression, string:replace(Expression, "~", "~~", all)},
                    %% Must match ?assertNotException/3
                    {pattern,
                        string:replace("{ _ , " Pattern " , [...] }", "~", "~~", all)},
                    {unexpected_exception, {'_', X__Reason, []}}
                    | proplists:lookup_all(comment, Options)
                ]}
            );
        [X__Value] ->
            case erlang:get('neo_test:assertion') of
                {X__Assertion, X__Info, X__Stacktrace} ->
                    erlang:raise(
                        error,
                        {X__Assertion,
                            X__Info ++
                                [
                                    {counterexample, X__Value}
                                    | proplists:lookup_all(comment, Options)
                                ]},
                        X__Stacktrace
                    );
                undefined ->
                    erlang:error(
                        {assertMatch, [
                            {module, ?MODULE},
                            {line, ?LINE},
                            {expression, string:replace(Expression, "~", "~~", all)},
                            {pattern, string:replace(Pattern, "~", "~~", all)},
                            {value, X__Value}
                            | proplists:lookup_all(comment, Options)
                        ]}
                    )
            end
    end
end).

-define(is_tuple_type(Container), Container#container.type =:= {}).

-define(is_gb_tree(Tree),
    (tuple_size(Tree) =:= 2 andalso is_integer(element(1, Tree)) andalso
        (element(2, Tree) =:= nil orelse tuple_size(element(2, Tree)) =:= 4))
).

-endif.
