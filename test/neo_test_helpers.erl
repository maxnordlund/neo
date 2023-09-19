-module(neo_test_helpers).

%%%_* Exports ================================================================
%%%_ * API -------------------------------------------------------------------
-export([
    flat_format/2,
    format_call/2,
    proper_options/1,
    test_case/1
]).

%%%_* Types ------------------------------------------------------------------
-export_type([
    test_case/0,
    test_case/1,
    test_cases/0,
    test_cases/1,
    test_result/0,
    test_result/1
]).

%%%_* Includes ===============================================================
-include("internal.hrl").
-include("test_helpers.hrl").

%%%_* Macros =================================================================
-define(DEFAULT_PROPER_NUMTESTS, 100).

-define(DEFAULT_PROPER_OPTIONS, [
    long_result,
    {numworkers, erlang:system_info(schedulers_online)}
]).

%%%_* Types ==================================================================
-type formatting_options() :: #{
    records => record_information()
}.

-type record_information() ::
    #{
        RecordTag ::
            atom() => #{
                Field :: atom() => FieldInformation :: string()
            }
    }.

-type test_case() :: test_case(SetupReturn :: term()).

-type test_case(SetupReturn) :: #{
    name => string(),
    test := simple_test_fun(),
    setup => setup(SetupReturn),
    cleanup => cleanup(SetupReturn),
    where => where()
}.

-type test_cases() :: test_cases(SetupReturn :: term()).

-type test_cases(SetupReturn) :: #{
    test => eunit_test_case(),
    setup => setup(SetupReturn),
    cleanup => cleanup(SetupReturn),
    where => where(),
    Name :: string() => eunit_test_case() | test_cases(SetupReturn)
}.

-type simple_test_fun() :: fun(() -> _).

-type eunit_test_case() :: simple_test_fun() | {Name :: string(), simple_test_fun()}.

-type setup(SetupReturn) :: fun(() -> SetupReturn).

-type cleanup(SetupReturn) :: fun((SetupReturn) -> _).

-type where() :: local | spawn | {spawn, node()}.

-type foreach(SetupReturn) ::
    {foreach, where(), setup(SetupReturn), cleanup(SetupReturn),
        test_cases(SetupReturn)}
    | {foreach, setup(SetupReturn), cleanup(SetupReturn), test_cases(SetupReturn)}
    | {foreach, where(), setup(SetupReturn), test_cases(SetupReturn)}
    | {foreach, setup(SetupReturn), test_cases(SetupReturn)}.

-type test_result() :: test_result(SetupReturn :: term()).

-type test_result(SetupReturn) :: [eunit_test_case()] | foreach(SetupReturn).

%%%_* Code ===================================================================

%% @doc Turns a map version of EUnits test representation to the tuple based
%% one EUnit expects.
%%
%% I can't for the life of me remember the order which setup and cleanup
%% comes in. So instead I wrote this to be able to use named properties.
%% And while I'm at it, make it a tad nicer by allowing you to specify
%% test names using a Name => Test map instead of {Name, Test} tuples.
%% Also, make `setup' optional, like how `cleanup' already is.
-spec test_case(test_case(SetupReturn) | test_cases(SetupReturn)) ->
    test_result(SetupReturn).
test_case(#{cleanup := _} = Options) when not is_map_key(setup, Options) ->
    %% Allow just cleanup, even though vanilla EUnit does not
    test_case(Options#{
        setup => fun() -> ok end
    });
test_case(#{setup := Setup} = Options) ->
    Tests =
        case Options of
            #{test := Test} ->
                [Test];
            _ ->
                [
                    test_case(Name, Test)
                 || {Name, Test} <- maps:to_list(Options),
                    is_string(Name)
                ]
        end,
    TestAndMaybeCleanup =
        case Options of
            #{cleanup := Cleanup} -> [Cleanup, Tests];
            _ -> [Tests]
        end,
    SetupAndMaybeWhere =
        case Options of
            #{where := Where} -> [Where, Setup | TestAndMaybeCleanup];
            _ -> [Setup | TestAndMaybeCleanup]
        end,
    list_to_tuple([foreach | SetupAndMaybeWhere]);
test_case(Tests) when is_map(Tests) ->
    [test_case(Name, Test) || {Name, Test} <- maps:to_list(Tests)].

%% @private
is_string(Name) ->
    is_list(Name) andalso lists:all(fun is_integer/1, Name).

%% @private
test_case(Name, Test) ->
    if
        is_map(Test) ->
            {Name, test_case(Test)};
        is_function(Test, 0) orelse is_tuple(Test) ->
            {Name, Test};
        true ->
            error(
                {assertMatch, [
                    {module, ?MODULE},
                    {line, ?LINE},
                    {expression, "Test"},
                    {pattern, "is_map(Test) orelse ?is_eunit_test_case(Test)"},
                    {value, Test}
                ]},
                [Name, Test]
            )
    end.

%% @doc Returns the given options merged with the default.
%%
%% It allows specifying explicit `shrink' and `colors', even though PropEr
%% doesn't.
%%
%% If no `spec_timeout' is given, it is derived from either `ct's current
%% `timetrap' or `eunit's `timeout'.
%%
%% You may also specify some options using OS environmental variables begining
%% with `"PROPER_"'. For example `PROPER_SHRINK' corresponds to `shrink'.
%% Integers may use `"_"' to make them more readable, like in Erlang.
%%
%% The options you can specify as OS environmental variables are:
%% colors, max_shrinks, max_size, numtests, shrinks and spec_timeout.
proper_options(Options) when is_map(Options) ->
    proper_options(proplists:from_map(Options));
proper_options(Options0) ->
    Options1 = Options0 ++ environmental_options() ++ ?DEFAULT_PROPER_OPTIONS,
    Options2 = set_spec_timeout(Options1),
    %% By converting it to a map and back we remove duplicates
    Options3 = proplists:to_map(Options2, [
        %% PropEr only support `noshrink'/`nocolors' as plain atoms (compact
        %% form). So we need to do some finagling to support `shrink' as a
        %% normal boolean proplists property.
        {negations, [
            {shrink, noshrink},
            {colors, nocolors}
        ]},
        {expand, [
            {{noshrink, false}, []},
            {{nocolors, false}, []}
        ]}
    ]),
    Options4 = maps:fold(fun compact_option/3, [], Options3),
    Options4.

%% @private
flat_format(FormatString, Arguments) ->
    lists:flatten(io_lib:format(lists:flatten(FormatString), Arguments)).

%%%_* Private ----------------------------------------------------------------

%% Used by the `?function_test/3' macro.
format_call(Call, Arguments) ->
    [Fun | _] = re:replace(Call, " ?\\(.*", ""),
    FormatString = [
        "~s(",
        lists:join(", ", lists:duplicate(length(Arguments), "~p")),
        ")"
    ],
    flat_format(FormatString, [Fun | Arguments]).

%% @private
environmental_options() ->
    [
        case string:split(EnvironmentalVariable, "=") of
            ["PROPER_SHRINK", Value] ->
                {shrink, boolean_environmental_option(Value)};
            ["PROPER_COLORS", Value] ->
                {colors, boolean_environmental_option(Value)};
            ["PROPER_MAX_SHRINKS", Value] ->
                {max_shrinks, integer_environmental_option(Value)};
            ["PROPER_MAX_SIZE", Value] ->
                {max_size, integer_environmental_option(Value)};
            ["PROPER_NUMTESTS", Value] ->
                {numtests, integer_environmental_option(Value)};
            ["PROPER_NUMWORKERS", Value] ->
                {numworkers, integer_environmental_option(Value)};
            ["PROPER_SPEC_TIMEOUT", Value] ->
                case string:lowercase(Value) of
                    "infinity" ->
                        {spec_timeout, infinity};
                    _ ->
                        {spec_timeout, integer_environmental_option(Value)}
                end;
            [VarName, Value] ->
                error(badarg, [VarName, Value])
        end
     || EnvironmentalVariable <- os:getenv(),
        nomatch =/= string:prefix(EnvironmentalVariable, "PROPER_")
    ].

%% @private
boolean_environmental_option(Value) ->
    case string:lowercase(Value) of
        "no" -> false;
        "false" -> false;
        "yes" -> true;
        "true" -> true;
        "" -> true;
        _ -> error(badarg, [Value])
    end.

%% @private
integer_environmental_option(Value0) ->
    Value1 = string:trim(Value0),
    Value2 = string:replace(Value1, "_", "", all),
    Value3 = unicode:characters_to_list(Value2),
    list_to_integer(Value3).

%% @private
%% Returns a resonable spec timeout for the current test runner,
%% aka EUnit or Common Test.
%%
%% The default number of test runs is 100, this is used together with the
%% default timeout for scale. Then it looks at the actual `numtests' and
%% adjusts accordingly.
%%
%% The default EUnit timeout is 5 seconds while for CT it is 30 minutes.
-ifdef(EUNIT).
set_spec_timeout(Options0) ->
    Numtests = proplists:get_value(numtests, Options0, ?DEFAULT_PROPER_NUMTESTS),
    Options1 =
        case proplists:get_value(spec_timeout, Options0) of
            SpecTimeout when is_integer(SpecTimeout) ->
                Options0;
            infinity ->
                %% To be long enough to be considered infinite, but still stop at
                %% some point, let's take the default timeout per _test case_ and
                %% apply it per _proper call_.
                proplist_set(Options0, spec_timeout, 5000);
            undefined ->
                proplist_set(Options0, spec_timeout, round(5000 / Numtests))
        end,
    erlang:put(
        neo_eunit_timeout,
        round(
            Numtests * proplists:get_value(spec_timeout, Options1) / 1000
        )
    ),
    Options1.
-else.
set_spec_timeout(Options) ->
    Numtests = proplists:get_value(numtests, Options, ?DEFAULT_PROPER_NUMTESTS),
    case ct:get_timetrap_info() of
        {infinity, {_Scaling, _ScaleValue}} ->
            proplist_set(Options, spec_timeout, infinity);
        {Time, {_Scaling, ScaleValue}} ->
            TimeoutInMilliseconds = round(Time * ScaleValue * 1000),
            SpecScale = TimeoutInMilliseconds / ?DEFAULT_PROPER_NUMTESTS,
            SpecTimeout = SpecScale * Numtests,
            %% Try to match the spec timeout, while allowing some time for
            %% setup/cleanup
            ct:timetrap(10 * ScaleValue + SpecTimeout / 1000.0),
            proplist_set(Options, spec_timeout, SpecTimeout);
        undefined ->
            DefaultTimoutInMilliseconds = 30 * 60 * 60 * 1000,
            SpecScale = DefaultTimoutInMilliseconds / ?DEFAULT_PROPER_NUMTESTS,
            proplist_set(Options, spec_timeout, SpecScale * Numtests)
    end.
-endif.

%% @private
%% Most boolean properties must be specified as atoms, but not `stop_nodes'
%% for some reason. This handles that correctly.
compact_option(stop_nodes, Value, Options) ->
    [{stop_nodes, Value} | Options];
compact_option(Option, true, Options) ->
    [Option | Options];
compact_option(Option, Value, Options) ->
    [{Option, Value} | Options].

%% @private
proplist_set(Proplist, Key, Value) ->
    lists:keystore(Key, 1, Proplist, {Key, Value}).
