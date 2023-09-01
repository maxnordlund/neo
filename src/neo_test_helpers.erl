-module(neo_test_helpers).

-export([
    format/2,
    format_call/2,
    test_case/1
]).

format_call(Call, Arguments) ->
    [Fun | _] = re:replace(Call, " ?\\(.*", ""),
    FormatString = [
        "~s(",
        lists:join(", ", lists:duplicate(length(Arguments), "~p")),
        ")"
    ],
    format(FormatString, [Fun | Arguments]).

format(FormatString, Arguments) ->
    lists:flatten(io_lib:format(lists:flatten(FormatString), Arguments)).

%% @doc Turns a map version of EUnits test representaion to the tuple based
%% one EUnit expects.
%%
%% I can't for the life of me remeber the order which Setup and Cleanup
%% comes in. So instead I wrote this to be able to use named properties.
%% And while I'm at it, make it a tad nicer by allowing you to specify
%% test names using a Name => Test map instead of {Name, Test} tuples.
%% Also, make the setup optional, like how the cleanup is already.
-spec test_case(TestCase | TestCases) -> Result when
    TestCase :: #{
        name => string(),
        test := SimpleTestFun,
        setup => Setup,
        cleanup => Cleanup,
        where => Where
    },
    TestCases :: #{
        tests := [EUnitTestCase] | #{string() := SimpleTestFun},
        setup => Setup,
        cleanup => Cleanup,
        where => Where
    },
    SimpleTestFun :: fun(() -> any()),
    EUnitTestCase :: SimpleTestFun | {string(), SimpleTestFun},
    Setup :: fun(() -> SetupReturn),
    Cleanup :: fun((SetupReturn) -> any()),
    Where :: local | spawn | {spawn, node()},
    Tests :: [EUnitTestCase],
    Foreach ::
        {foreach, Where, Setup, Cleanup, Tests}
        | {foreach, Setup, Cleanup, Tests}
        | {foreach, Where, Setup, Tests}
        | {foreach, Setup, Tests},
    Result :: [EUnitTestCase] | Foreach.
test_case(#{name := Name, test := Test} = Options) ->
    test_case(
        maps:without([name, test], Options#{
            tests => [{Name, Test}]
        })
    );
test_case(#{test := Test} = Options) ->
    test_case(
        maps:remove(test, Options#{
            tests => [Test]
        })
    );
test_case(#{tests := Tests} = Options) when is_map(Tests) ->
    test_case(Options#{
        tests => maps:to_list(Tests)
    });
test_case(#{cleanup := _} = Options) when not is_map_key(setup, Options) ->
    %% Allow just cleanup, even though vanilla EUnit does not
    test_case(Options#{
        setup => fun() -> ok end
    });
test_case(#{setup := Setup, tests := Tests} = Options) ->
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
test_case(#{tests := Tests}) ->
    Tests.
