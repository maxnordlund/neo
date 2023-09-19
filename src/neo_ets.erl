%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% @doc Implementation of {@link neo_collection} for Erlang's builtin
%%% `ets' module.
%%% @end
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%%%_* Module declaration =====================================================
-module(neo_ets).
-compile(
    {no_auto_import, [
        size/1
    ]}
).

%%%_* Behaviours =============================================================
-behaviour(neo_collection).
-behaviour(neo_stream).

%%%_* Exports ================================================================
%%%_ * API -------------------------------------------------------------------
-export([
    from/1,
    new/1,
    new/2
]).

%%%_ * Callbacks -------------------------------------------------------------
-export([
    delete/2,
    get/2,
    get/3,
    keys/1,
    has/2,
    new/0,
    set/3,
    size/1,
    to_list/1
]).

-export([
    iterator/1,
    next/1
]).

%%%_* Types ------------------------------------------------------------------
-export_type([
    iterator/1,
    t/0,
    t/1
]).

%%%_* Includes ===============================================================
-include_lib("stdlib/include/ms_transform.hrl").
-include("internal.hrl").

%%%_* Macros =================================================================
-define(DEFAULT_TABLE_NAME, list_to_atom(?MODULE_STRING ":DEFAULT TABLE NAME")).

%%%_* Types ==================================================================
-record(neo_ets, {
    table :: ets:table(),
    current_key = undefined :: key()
}).

-opaque t() :: #neo_ets{}.

-opaque t(_Object) :: #neo_ets{}.

-type key() :: term().

-type object() :: tuple().

-opaque iterator(_Object) ::
    #neo_ets{
        current_key :: key()
    }.

%%%_* Code ===================================================================
%% @doc Return an opaque handle to {@link ets} with the given name.
-spec from(ets:table()) -> t().
from(Table) ->
    %% Raises `badarg' if `Table' is not an `ets' table identifier.
    _ = ets:info(Table),
    #neo_ets{table = Table}.

%% @doc Return a list of all objects in the given {@link ets} table.
-spec to_list(t()) -> [object()].
to_list(#neo_ets{table = Table}) ->
    ets:tab2list(Table).

%% @doc Return an opaque handle to {@link ets}.
-spec new() -> t().
new() ->
    from(ets:new(?DEFAULT_TABLE_NAME, [])).

%% @equiv new(Name, [])
-spec new(Name) -> t() when
    Name :: atom().
new(Name) ->
    new(Name, []).

%% @doc Return an opaque handle to {@link ets} with the given options.
%%
%% The table will be registed with the given `Name'.
-spec new(Name, proplists:proplist()) -> t() when
    Name :: atom().
new(Name, Options) when is_atom(Name) andalso is_list(Options) ->
    from(ets:new(Name, [named_table | Options])).

%% @doc Return the number of {@link ets} tables.
-spec size(t()) -> non_neg_integer().
size(#neo_ets{table = Table}) ->
    ets:info(Table, size).

%% @doc Return `true' if the given {@link ets} table has a the given `Key',
%% otherwise `false'.
-spec has(t(), key()) -> boolean().
has(#neo_ets{table = Table}, Key) ->
    ets:member(Table, Key).

%% @doc Return the keys for the given {@link ets} table.
-spec keys(t()) -> [key()].
keys(#neo_ets{table = Table}) ->
    KeyPos = ets:info(Table, keypos),
    ets:select(Table, ets:fun2ms(fun(Object) -> element(KeyPos, Object) end)).

%% @doc Return the value for the given `Key' in the given {@link ets} table.
-spec get(t(), key()) -> object().
get(#neo_ets{} = State, Key) ->
    case fetch(State, Key) of
        {ok, ObjectOrObjects} -> ObjectOrObjects;
        {error, notfound} -> error({badkey, Key}, [State, Key])
    end.

%% @doc Return the value for the given `Key' in the given {@link ets} table,
%% or `Default' if no such value can be found.
-spec get(t(), key(), term()) -> term().
get(#neo_ets{} = State, Key, Default) ->
    case fetch(State, Key) of
        {ok, Value} -> Value;
        {error, notfound} -> Default
    end.

%% @doc Return the value associated with the given `Key' in the given
%% {@link ets} table, or `{error, notfound}' if the table does not contain
%% `Key'.
-spec fetch(t(), key()) -> {ok, object()} | {error, notfound}.
fetch(#neo_ets{table = Table}, Key) ->
    case ets:lookup(Table, Key) of
        [] ->
            {error, notfound};
        ObjectOrObjects ->
            case ets:info(Table, type) of
                Set when ?oneof(Set, set, ordered_set) ->
                    ?assertMatch(
                        [_],
                        ObjectOrObjects,
                        "set like ETS tables must have only one object per key"
                    ),
                    {ok, hd(ObjectOrObjects)};
                _ ->
                    {ok, ObjectOrObjects}
            end
    end.

%% @doc Inserts the given object into the given {@link ets} table.
%%
%% The given `Key' must match the one inside the given `Value'.
-spec set(t(), key(), object()) -> t().
set(#neo_ets{table = Table} = State, Key, Value) ->
    ?assertMatch(
        {Key, KeyPos, Value} when Key =:= element(KeyPos, Value),
        {Key, ets:info(Table, keypos), Value},
        "the given Key must match the one inside the given Value"
    ),
    _ = Key,
    ets:insert(Table, Value),
    State.

%% @doc Deletes the object with the given `Key' in the given {@link ets} table.
-spec delete(t(), key()) -> t().
delete(#neo_ets{table = Table} = State, Key) ->
    ets:delete(Table, Key),
    State.

%% @doc Return an {@link neo_stream:iterator()} for the given {@link ets}
%% table.
-spec iterator(t(Object)) -> iterator(Object).
iterator(#neo_ets{table = Table} = State) ->
    ets:safe_fixtable(Table, true),
    State#neo_ets{current_key = ets:first(Table)};
iterator(Table) ->
    iterator(from(Table)).

%% @doc Return the next object in the given {@link neo_stream:iterator()}.
-spec next(iterator(Object)) -> {key(), Object, iterator(Object)} | none.
next(#neo_ets{table = Table, current_key = '$end_of_table'}) ->
    ets:safe_fixtable(Table, false),
    none;
next(#neo_ets{table = Table, current_key = Key} = State) ->
    {Key, get(State, Key), State#neo_ets{current_key = ets:next(Table, Key)}}.

%%%_* Private ----------------------------------------------------------------

%%%_* Tests ==================================================================
-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").

-define(TEST_TABLE, 'neo_ets:test table').
-define(TEST_BAG, 'neo_ets:test bag').

e2e_test_() ->
    neo_test_helpers:test_case(#{
        where => local,
        setup => fun() ->
            Table = ets:new(?TEST_TABLE, [public, ordered_set, named_table]),
            ets:insert(Table, [
                {1, <<"Jane">>, <<"Doe">>},
                {2, <<"John">>, <<"Smith">>}
            ]),
            Table
        end,
        cleanup => fun ets:delete/1,
        "size" => #{
            "empty" => ?_assertEqual(0, size(new())),
            "non-empty" => ?_assertEqual(2, size(from(?TEST_TABLE)))
        },
        "keys" => #{
            "empty" => ?_assertEqual([], keys(new('some table'))),
            "non-empty" => ?_assertEqual([1, 2], keys(from(?TEST_TABLE)))
        },
        "has" => #{
            "existing" => ?_assert(has(from(?TEST_TABLE), 1)),
            "non existing" => ?_assertNot(has(from(?TEST_TABLE), 3))
        },
        "get" => #{
            "existing" => ?_assertEqual(
                {1, <<"Jane">>, <<"Doe">>},
                get(from(?TEST_TABLE), 1)
            ),
            "non existing" => ?_assertError(
                {badkey, 3},
                get(from(?TEST_TABLE), 3)
            )
        },
        "get with default" => #{
            "existing" => ?_assertEqual(
                {2, <<"John">>, <<"Smith">>},
                get(from(?TEST_TABLE), 2, <<"Default value">>)
            ),
            "non-existing" => ?_assertEqual(
                <<"Default value">>, get(from(?TEST_TABLE), 3, <<"Default value">>)
            )
        },
        "fetch" => #{
            "existing" => ?_assertEqual(
                {ok, {1, <<"Jane">>, <<"Doe">>}},
                fetch(from(?TEST_TABLE), 1)
            ),
            "non existing" => ?_assertEqual(
                {error, notfound},
                fetch(from(?TEST_TABLE), 3)
            ),
            "bag" => fun() ->
                Table = new(?TEST_BAG, [public, bag]),
                ets:insert(Table#neo_ets.table, [
                    {1, <<"Jane">>, <<"Doe">>},
                    {1, <<"John">>, <<"Smith">>}
                ]),
                ?assertEqual(
                    {ok, [{1, <<"Jane">>, <<"Doe">>}, {1, <<"John">>, <<"Smith">>}]},
                    fetch(Table, 1)
                ),
                ets:delete(Table#neo_ets.table)
            end
        },
        "set" => #{
            "existing" => fun() ->
                Table = from(?TEST_TABLE),
                set(Table, 1, {1, <<"Janet">>, <<"Smith">>}),
                ?assertEqual(
                    [{1, <<"Janet">>, <<"Smith">>}], ets:lookup(?TEST_TABLE, 1)
                )
            end,
            "non existing" => fun() ->
                Table = from(?TEST_TABLE),
                set(Table, new, {new, <<"Some">>, <<"Name">>}),
                ?assertEqual(
                    [{new, <<"Some">>, <<"Name">>}], ets:lookup(?TEST_TABLE, new)
                )
            end
        },
        "delete" => #{
            "existing" => fun() ->
                Table = from(?TEST_TABLE),
                delete(Table, 1),
                ?assertEqual([], ets:lookup(?TEST_TABLE, 1))
            end,
            "non existing" => fun() ->
                Table = from(?TEST_TABLE),
                delete(Table, new),
                ?assertEqual([], ets:lookup(?TEST_TABLE, new))
            end
        },
        "to_list" => ?_assertEqual(
            [{1, <<"Jane">>, <<"Doe">>}, {2, <<"John">>, <<"Smith">>}],
            to_list(from(?TEST_TABLE))
        ),
        "iterator" => #{
            "empty" => fun() ->
                Table = ets:new('neo_ets:test empty table', []),
                ?assertEqual(none, next(iterator(Table)))
            end,
            "non-empty" => fun() ->
                Table = from(?TEST_TABLE),
                Iterator0 = iterator(Table),
                ?assertMatch(
                    {1, {1, <<"Jane">>, <<"Doe">>}, _},
                    next(Iterator0)
                ),
                {_, _, Iterator1} = next(Iterator0),
                ?assertMatch(
                    {2, {2, <<"John">>, <<"Smith">>}, _},
                    next(Iterator1)
                ),
                {_, _, Iterator2} = next(Iterator1),
                ?assertEqual(none, next(Iterator2))
            end
        }
    }).

-endif.
