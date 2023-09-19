%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% @doc Functions for getting/setting deeply nested structures.
%%% @end
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%%%_* Module declaration =====================================================
-module(neo_deep).

%%%_* Behaviours =============================================================

%%%_* Exports ================================================================
%%%_ * API -------------------------------------------------------------------
-export([
    delete/2,
    fetch/2,
    has/2,
    get/2,
    get/3,
    set/3
]).

-export([
    fold/3,
    map/2,
    filter/2,
    filtermap/2
]).

%%%_ * Callbacks -------------------------------------------------------------

%%%_* Types ------------------------------------------------------------------

%%%_* Includes ===============================================================
-include("internal.hrl").

%%%_* Macros =================================================================

%%%_* Types ==================================================================

%%%_* Code ===================================================================
%%%_ * API -------------------------------------------------------------------

%% @doc Returns `true' if the given collection has a value at the given nested
%% path of `Key's, `false' otherwise.
-spec has(neo_collection:t(Key, _Value), [Key]) -> boolean().
has(_Collection, []) ->
    false;
has(Collection, [Key]) ->
    neo_collection:has(Collection, Key);
has(Collection, [Key | Path]) ->
    case neo_collection:fetch(Collection, Key) of
        {ok, InnerCollection} -> has(InnerCollection, Path);
        {error, notfound} -> false
    end.

%% @doc Returns the `Value' at the given nested path of `Key's.
-spec get(neo_collection:t(Key, Value), [Key]) -> Value.
get(Collection, Keys) ->
    case fetch(Collection, Keys) of
        {ok, Value} -> Value;
        {error, notfound} -> error({badkey, Keys}, [Collection, Keys])
    end.

%% @doc Returns the `Value' at the given nested path of `Key's, or
%% `Default' if there's no such `Value'.
-spec get(neo_collection:t(Key, Value), [Key], Default) -> Value | Default.
get(Collection, Keys, Default) ->
    case fetch(Collection, Keys) of
        {ok, Value} -> Value;
        {error, notfound} -> Default
    end.

%% @doc Returns the `Value' at the given nested path of `Key's, or
%% `{error, notfound}' if there's no such `Value'.
-spec fetch(neo_collection:t(Key, Value), [Key]) -> Value.
fetch(_Collection, []) ->
    {error, notfound};
fetch(Collection, Keys) ->
    lists:foldl(fun fetch_internal/2, {ok, Collection}, Keys).

%% @private
fetch_internal(Key, {ok, InnerCollection}) ->
    neo_collection:fetch(InnerCollection, Key);
fetch_internal(_Key, {error, notfound}) ->
    {error, notfound}.

%% @doc Returns the given collection with the given `Value' set at the nested
%% path of `Key's.
%%
%% If the next key is 0, an the there's no list at the current position, it
%% will insert an empty list and continue.
%% If the next key is something else, and there's no collection at the current
%% position, it will insert an empty map and continue.
-spec set(neo_collection:t(Key, Value), [Key], Value) -> neo_collection:t(Key, Value).
set(Collection, [], Value) ->
    error({badkey, []}, [Collection, [], Value]);
set(Collection, Path, Value) ->
    set_internal(Collection, Path, Value).

%% @private
set_internal(_Collection, [], Value) ->
    Value;
set_internal(OuterCollection, [Key | Path], Value) ->
    InnerCollection =
        case neo_collection:fetch(OuterCollection, Key) of
            {ok, Collection} ->
                Collection;
            {error, notfound} when is_integer(hd(Path)) ->
                [];
            {error, notfound} ->
                #{}
        end,
    neo_collection:set(
        OuterCollection, Key, set_internal(InnerCollection, Path, Value)
    ).

%% @doc Returns a {@link neo_collection:t(). collection} without an
%% association at the given nested path of `Key's.
%%
%% If the any part of the path is missing, the original collection is returned
%% as is.
-spec delete(neo_collection:t(Key, Value), [Key]) -> neo_collection:t(Key, Value).
delete(Collection, []) ->
    error({badkey, []}, [Collection, []]);
delete(Collection, [Key]) ->
    neo_collection:delete(Collection, Key);
delete(OuterCollection, [Key | Path]) ->
    case neo_collection:fetch(OuterCollection, Key) of
        {ok, InnerCollection} ->
            neo_collection:set(OuterCollection, Key, delete(InnerCollection, Path));
        {error, notfound} ->
            OuterCollection
    end.

%% @doc Folds the given function over the given collection, recursively.
%%
%% This means that it skips they values that are
%% {@link neo_collection:t(). collections}, and instead folds over the inner
%% values of said collections.
-spec fold(
    neo_collection:t(Key, Value),
    InitialAccumulator,
    Folder
) -> Accumulator when
    InitialAccumulator :: Accumulator,
    Folder ::
        fun((Accumulator, Value) -> Accumulator)
        | fun((Accumulator, Key, Value) -> Accumulator).
fold(Collection, InitialAccumulator, Folder) when
    is_function(Folder, 2) orelse is_function(Folder, 3)
->
    neo_iterable:fold(Collection, InitialAccumulator, fun(Accumulator, Key, Value) ->
        case neo_reflect:has_implementation(Value, [neo_stream]) of
            true ->
                fold(Value, Accumulator, Folder);
            false when is_function(Folder, 3) ->
                Folder(Accumulator, Key, Value);
            false when is_function(Folder, 2) ->
                Folder(Accumulator, Value)
        end
    end).

%% @doc Returns a new collection with the given function applied to each
%% element, recursively.
-spec map(
    neo_collection:t(KeyIn, ValueIn),
    neo_stream:mapper(KeyIn, ValueIn, KeyOut, ValueOut)
) -> neo_collection:t(KeyOut, ValueOut).
map(Collection, Mapper) when is_function(Mapper, 2) ->
    neo_stream:fold(
        neo_stream:from(Collection),
        neo_collection:new(Collection),
        fun(Accumulator, KeyIn, ValueIn) ->
            case neo_reflect:has_implementation(ValueIn, [neo_stream]) of
                true ->
                    ValueOut = map(ValueIn, Mapper),
                    neo_collection:set(Accumulator, KeyIn, ValueOut);
                false ->
                    {KeyOut, ValueOut} = Mapper(KeyIn, ValueIn),
                    neo_collection:set(Accumulator, KeyOut, ValueOut)
            end
        end
    );
map(Collection, Mapper) when is_function(Mapper, 1) ->
    neo_iterable:map(Collection, fun(_Key, Value) ->
        case neo_reflect:has_implementation(Value, [neo_stream]) of
            true ->
                map(Value, Mapper);
            false ->
                Mapper(Value)
        end
    end).

%% @doc Returns a new collection with all elements that satisfy the given
%% predicate, recursively.
-spec filter(
    neo_collection:t(Key, Value),
    neo_iterable:filter(Key, Value)
) -> neo_collection:t(Key, Value).
filter(Collection, Filterer) when ?is_callback(Filterer) ->
    filtermap(Collection, Filterer).

%% @doc Returns a new collection that satisfies the given predicate, recursively,
%% optionally transforming the elemtent in question.
-spec filtermap(
    neo_collection:t(Key, Value),
    neo_iterable:filter_mapper(Key, Value, NewValue)
) -> neo_collection:t(Key, NewValue) when
    NewValue :: any().
filtermap(Collection, FilterMapper) when ?is_callback(FilterMapper) ->
    neo_iterable:filtermap(Collection, fun(KeyIn, ValueIn) ->
        case neo_reflect:has_implementation(ValueIn, [neo_stream]) of
            true ->
                {true, filtermap(ValueIn, FilterMapper)};
            false ->
                ?call_callback(FilterMapper, KeyIn, ValueIn)
        end
    end).

%%%_ * Callbacks -------------------------------------------------------------

%%%_* Private ----------------------------------------------------------------

%%%_* Tests ==================================================================
-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").

has_test_() ->
    neo_test_helpers:test_case(#{
        "empty collection" => #{
            "empty path" => ?_assertNot(has(#{}, [])),
            "single key" => ?_assertNot(has([], [key])),
            "multiple keys" => ?_assertNot(has(dict:new(), [top, bottom]))
        },
        "non-empty collection" => #{
            "empty path" => ?_assertNot(has([{key, value}], [])),
            "single key" => #{
                "key exists" => ?_assert(has(#{key => value}, [key])),
                "key doesn't exist" => ?_assertNot(has(#{key => value}, [other]))
            },
            "multiple keys" => #{
                "keys exist" => ?_assert(
                    has(dict:from_list([{top, #{bottom => value}}]), [top, bottom])
                ),
                "keys don't exist" => ?_assertNot(
                    has(dict:from_list([{top, #{bottom => value}}]), [top, other])
                )
            }
        }
    }).

get_test_() ->
    neo_test_helpers:test_case(#{
        "without default" => #{
            "empty collection" => ?_assertError(
                {badkey, [key]},
                get(#{}, [key])
            ),
            "single key" => #{
                "key exists" => ?_assertEqual(
                    value,
                    get(#{key => value}, [key])
                ),
                "key doesn't exist" => ?_assertError(
                    {badkey, [other]},
                    get(#{key => value}, [other])
                )
            },
            "multiple keys" => #{
                "keys exist" => ?_assertEqual(
                    value,
                    get(#{top => #{bottom => value}}, [top, bottom])
                ),
                "keys don't exist" => ?_assertError(
                    {badkey, [top, other]},
                    get(#{top => #{bottom => value}}, [top, other])
                )
            }
        },
        "with default" => #{
            "empty collection" => ?_assertEqual(
                default,
                get(#{}, [key], default)
            ),
            "single key" => #{
                "key exists" => ?_assertEqual(
                    value,
                    get(#{key => value}, [key], default)
                ),
                "key doesn't exist" => ?_assertEqual(
                    default,
                    get([value], [2], default)
                )
            },
            "multiple keys" => #{
                "keys exist" => ?_assertEqual(
                    value,
                    get(#{top => [{bottom, [value]}]}, [top, bottom, 1], default)
                ),
                "keys don't exist" => ?_assertEqual(
                    default,
                    get(#{top => #{bottom => value}}, [top, other], default)
                )
            }
        }
    }).

fetch_test_() ->
    neo_test_helpers:test_case(#{
        "empty path" => #{
            "empty collection" => ?_assertEqual(
                {error, notfound},
                fetch(#{}, [])
            ),
            "non-empty collection" => ?_assertEqual(
                {error, notfound},
                fetch(#{key => value}, [])
            )
        },
        "single key" => #{
            "key exists" => ?_assertEqual(
                {ok, value},
                fetch(#{key => value}, [key])
            ),
            "key doesn't exist" => ?_assertEqual(
                {error, notfound},
                fetch(#{key => value}, [other])
            )
        },
        "multiple keys" => #{
            "keys exist" => ?_assertEqual(
                {ok, value},
                fetch(#{top => #{bottom => value}}, [top, bottom])
            ),
            "first key don't exist" => ?_assertEqual(
                {error, notfound},
                fetch(#{top => #{bottom => value}}, [other, bottom])
            ),
            "second key don't exist" => ?_assertEqual(
                {error, notfound},
                fetch(#{top => #{bottom => value}}, [top, other])
            )
        }
    }).

set_test_() ->
    neo_test_helpers:test_case(#{
        "empty collection" => #{
            "empty path" => ?_assertError(
                {badkey, []},
                set(#{}, [], value)
            ),
            "single key" => ?_assertEqual(
                #{key => value},
                set(#{}, [key], value)
            ),
            "multiple keys" => ?_assertEqual(
                dict:from_list([{top, #{bottom => value}}]),
                set(dict:new(), [top, bottom], value)
            )
        },
        "non-empty collection" => #{
            "empty path" => ?_assertError(
                {badkey, []},
                set(#{key => other}, [], value)
            ),
            "single key" => #{
                "key exists" => ?_assertEqual(
                    [value],
                    set([other], [1], value)
                ),
                "key doesn't exist" => ?_assertEqual(
                    dict:from_list([{key, value}, {new_key, other}]),
                    set(dict:from_list([{key, value}]), [new_key], other)
                ),
                "index doesn't exist" => ?_assertEqual(
                    [other, value],
                    set([value], [0], other)
                )
            },
            "multiple keys" => #{
                "keys exist" => ?_assertEqual(
                    #{top => #{bottom => other}},
                    set(#{top => #{bottom => value}}, [top, bottom], other)
                ),
                "keys don't exist" => ?_assertEqual(
                    #{top => #{bottom => other}, new_key => value},
                    set(#{top => #{bottom => other}}, [new_key], value)
                ),
                "some keys exist, other doesn't" => ?_assertEqual(
                    #{top => #{middle => [value]}},
                    set(#{top => #{}}, [top, middle, 1], value)
                )
            }
        }
    }).

delete_test_() ->
    neo_test_helpers:test_case(#{
        "empty collection" => #{
            "empty path" => ?_assertError(
                {badkey, []},
                delete(#{}, [])
            ),
            "single key" => ?_assertEqual(
                #{},
                delete(#{}, [key])
            ),
            "multiple keys" => ?_assertEqual(
                [],
                delete([], [top, bottom])
            )
        },
        "non-empty collection" => #{
            "empty path" => ?_assertError(
                {badkey, []},
                delete(#{key => value}, [])
            ),
            "single key" => #{
                "key exists" => ?_assertEqual(
                    #{},
                    delete(#{key => value}, [key])
                ),
                "key doesn't exist" => ?_assertEqual(
                    #{key => value},
                    delete(#{key => value}, [other])
                )
            },
            "multiple keys" => #{
                "keys exist" => ?_assertEqual(
                    [{top, #{}}],
                    delete([{top, #{bottom => value}}], [top, bottom])
                ),
                "keys don't exist" => ?_assertEqual(
                    #{top => #{bottom => value}},
                    delete(#{top => #{bottom => value}}, [top, other])
                )
            }
        }
    }).

fold_test_() ->
    neo_test_helpers:test_case(#{
        "folder has arity 2" => ?_assertEqual(
            [dict, inner_map, key, <<"list">>],
            fold(
                #{
                    key => key,
                    list => [<<"list">>],
                    map => #{inner_key => inner_map},
                    dict => dict:from_list([{dictionary_key, dict}])
                },
                ordsets:new(),
                fun(Set, Value) ->
                    ordsets:add_element(Value, Set)
                end
            )
        ),
        "folder has arity 3" => ?_assertEqual(
            #{
                <<"key">> => key,
                1 => <<"list">>,
                <<"inner_key">> => inner_map,
                <<"dictionary_key">> => dict
            },
            fold(
                #{
                    key => key,
                    list => [<<"list">>],
                    map => #{inner_key => inner_map},
                    dict => dict:from_list([{dictionary_key, dict}])
                },
                #{},
                fun
                    (Map, Key, Value) when is_atom(Key) ->
                        Map#{atom_to_binary(Key) => Value};
                    (Map, Key, Value) ->
                        Map#{Key => Value}
                end
            )
        )
    }).

map_test_() ->
    [
        {
            neo_test_helpers:format(Mapper),
            ?_assertEqual(
                #{
                    key => <<"key">>,
                    proplist => [{list, <<"true">>}],
                    map => #{inner_key => <<"inner_value">>},
                    dict => dict:from_list([{inner_key, <<"dict">>}])
                },
                map(
                    #{
                        key => key,
                        proplist => [list],
                        map => #{inner_key => inner_value},
                        dict => dict:from_list([{inner_key, dict}])
                    },
                    Mapper
                )
            )
        }
     || Mapper <- [
            fun atom_to_binary/1,
            fun(Key, Value) ->
                {Key, atom_to_binary(Value)}
            end
        ]
    ].

filter_test_() ->
    [
        {
            neo_test_helpers:format(Filter),
            ?_assertEqual(
                #{
                    proplist => [{list, true}],
                    map => #{},
                    dict => dict:new()
                },
                filter(
                    #{
                        key => <<"key">>,
                        proplist => [list],
                        map => #{inner_key => <<"inner_value">>},
                        dict => dict:from_list([{inner_key, <<"dict">>}])
                    },
                    Filter
                )
            )
        }
     || Filter <- [
            fun is_atom/1,
            fun(_Key, Value) ->
                is_atom(Value)
            end
        ]
    ].

-endif.
