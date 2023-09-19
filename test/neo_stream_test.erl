%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% @doc {@link proper. PropEr} tests for {@link neo_iterable} and
%%% {@link neo_stream}.
%%% @end
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%%%_* Module declaration =====================================================
-module(neo_stream_test).

%%%_* Exports ================================================================
%%%_ * API -------------------------------------------------------------------
-compile([export_all, nowarn_export_all]).

%%%_* Types ------------------------------------------------------------------

%%%_* Includes ===============================================================
-include("internal.hrl").
-include("proper_types.hrl").
-include("test_helpers.hrl").
-include_lib("proper/include/proper.hrl").
-include_lib("eunit/include/eunit.hrl").

%%%_* Macros =================================================================

%%%_* Types ==================================================================

%%%_* Code ===================================================================

format(
    #stream_operator{type = Type, orddict_function = OrddictFun}
) ->
    #{module := Module, name := Name, arity := Arity} =
        case maps:from_list(erlang:fun_info(OrddictFun)) of
            #{type := local, module := ?MODULE, env := [InnerFun]} when
                is_function(InnerFun)
            ->
                maps:from_list(erlang:fun_info(InnerFun));
            FunInfo ->
                FunInfo
        end,
    ModuleString =
        case Module of
            ?MODULE -> "";
            _ -> atom_to_binary(Module)
        end,
    io_lib:format("~tp(fun ~s~tp/~p)", [Type, ModuleString, Name, Arity]).

%%%_ * Tests -----------------------------------------------------------------

fold_test_() ->
    neo_test_helpers:test_case(#{
        "iterable" => ?_quickcheck(
            container_type([
                without_lists, {orddict, orddict_type(key_type(), nat())}
            ]),
            #container{
                collection = Collection,
                orddict = Orddict
            },
            lists:foldl(
                fun count_orddict/2,
                new_counter(),
                orddict:map(fun typeof_orddict_mapper/2, Orddict)
            ) =:=
                neo_iterable:fold(
                    Collection,
                    new_counter(),
                    fun count_typeof/3
                )
        ),
        "stream" => #{
            "without limit" => ?_quickcheck(
                {
                    container_type([
                        without_lists, {orddict, orddict_type(key_type(), nat())}
                    ]),
                    count_folder_type()
                },
                {
                    #container{
                        collection = Collection,
                        orddict = Orddict
                    },
                    Folder
                },
                lists:foldl(
                    fun count_orddict/2,
                    new_counter(),
                    orddict:map(fun typeof_orddict_mapper/2, Orddict)
                ) =:=
                    neo_stream:fold(
                        neo_stream:from(Collection),
                        new_counter(),
                        Folder
                    )
            ),
            "with limit" => ?_quickcheck(
                {
                    container_type([
                        without_lists, {orddict, orddict_type(key_type(), nat())}
                    ]),
                    limit_type(),
                    count_folder_type()
                },
                {
                    #container{
                        collection = Collection,
                        orddict = Orddict
                    },
                    Limit,
                    Folder
                },
                lists:foldl(
                    fun count_orddict/2,
                    new_counter(),
                    orddict:map(fun typeof_orddict_mapper/2, Orddict)
                ) =:=
                    neo_stream:fold(
                        neo_stream:from(Collection),
                        new_counter(),
                        Folder,
                        #{limit => min(2, Limit)}
                    )
            )
        }
    }).

map_test_() ->
    neo_test_helpers:test_case(#{
        "iterable" => ?_quickcheck(
            {container_type([non_empty]), typeof_iterable_mapper_type()},
            {
                #container{
                    collection = Collection,
                    from_list = FromList,
                    orddict = Orddict
                } = Container,
                Mapper
            },
            ?assertContainerEqual(
                Container,
                FromList(orddict:map(fun typeof_orddict_mapper/2, Orddict)),
                neo_iterable:map(Collection, Mapper)
            )
        ),
        "stream" => #{
            "without limit" => ?_quickcheck(
                {container_type([non_empty]), typeof_stream_mapper_type()},
                {
                    #container{
                        collection = Collection,
                        from_list = FromList,
                        orddict = Orddict
                    } = Container,
                    Mapper
                },
                ?assertContainerEqual(
                    Container,
                    FromList(orddict:map(fun typeof_orddict_mapper/2, Orddict)),
                    neo_stream:fold(
                        neo_stream:map(neo_stream:from(Collection), Mapper),
                        neo_collection:new(Collection),
                        fun neo_collection:set/3
                    )
                )
            ),
            "with limit" => ?_quickcheck(
                {
                    container_type([non_empty, without_lists]),
                    limit_type(),
                    typeof_stream_mapper_type()
                },
                {
                    #container{
                        collection = Collection,
                        from_list = FromList,
                        orddict = Orddict
                    } = Container,
                    Limit,
                    Mapper
                },
                ?assertContainerEqual(
                    Container,
                    FromList(orddict:map(fun typeof_orddict_mapper/2, Orddict)),
                    neo_stream:fold(
                        neo_stream:map(neo_stream:from(Collection), Mapper),
                        neo_collection:new(Collection),
                        fun neo_collection:set/3,
                        #{limit => min(2, Limit)}
                    )
                )
            )
        }
    }).

filter_test_() ->
    neo_test_helpers:test_case(#{
        "iterable" => ?_quickcheck(
            {
                container_type([non_empty, without_lists, without_tuples]),
                typeof_filter_type()
            },
            {
                #container{
                    collection = Collection,
                    from_list = FromList,
                    orddict = Orddict
                } = Container,
                Filter
            },
            ?assertContainerEqual(
                Container,
                FromList(orddict:filter(stream_to_orddict(Filter, #{}), Orddict)),
                neo_iterable:filter(Collection, Filter)
            )
        ),
        "stream" => #{
            "without limit" => ?_quickcheck(
                {
                    container_type([non_empty, without_lists, without_tuples]),
                    typeof_filter_type()
                },
                {
                    #container{
                        collection = Collection,
                        from_list = FromList,
                        orddict = Orddict
                    } = Container,
                    Filter
                },
                ?assertContainerEqual(
                    Container,
                    FromList(orddict:filter(stream_to_orddict(Filter, #{}), Orddict)),
                    neo_stream:fold(
                        neo_stream:filter(neo_stream:from(Collection), Filter),
                        neo_collection:new(Collection),
                        fun neo_collection:set/3
                    )
                )
            ),
            "with limit" => ?_quickcheck(
                {
                    container_type([non_empty, without_lists, without_tuples]),
                    limit_type(),
                    typeof_filter_type()
                },
                {
                    #container{
                        collection = Collection,
                        from_list = FromList,
                        orddict = Orddict
                    } = Container,
                    Limit,
                    Filter
                },
                ?assertContainerEqual(
                    Container,
                    FromList(orddict:filter(stream_to_orddict(Filter, #{}), Orddict)),
                    neo_stream:fold(
                        neo_stream:filter(neo_stream:from(Collection), Filter),
                        neo_collection:new(Collection),
                        fun neo_collection:set/3,
                        #{limit => min(2, Limit)}
                    )
                )
            )
        }
    }).

filtermap_test_() ->
    neo_test_helpers:test_case(#{
        "iterable" => ?_quickcheck(
            {
                container_type([non_empty, without_lists, without_tuples]),
                typeof_iterable_filtermapper_type()
            },
            {
                #container{
                    collection = Collection,
                    from_list = FromList,
                    orddict = Orddict
                } = Container,
                FilterMapper
            },
            ?assertContainerEqual(
                Container,
                FromList(lists:filtermap(fun typeof_list_filtermapper/1, Orddict)),
                neo_iterable:filtermap(Collection, FilterMapper)
            )
        ),
        "stream" => #{
            "without limit" => ?_quickcheck(
                {
                    container_type([non_empty, without_lists, without_tuples]),
                    typeof_stream_filtermapper_type()
                },
                {
                    #container{
                        collection = Collection,
                        from_list = FromList,
                        orddict = Orddict
                    } = Container,
                    FilterMapper
                },
                ?assertContainerEqual(
                    Container,
                    FromList(lists:filtermap(fun typeof_list_filtermapper/1, Orddict)),
                    neo_stream:fold(
                        neo_stream:filtermap(
                            neo_stream:from(Collection),
                            FilterMapper
                        ),
                        neo_collection:new(Collection),
                        fun neo_collection:set/3
                    )
                )
            ),
            "with limit" => ?_quickcheck(
                {
                    container_type([non_empty, without_lists, without_tuples]),
                    limit_type(),
                    typeof_stream_filtermapper_type()
                },
                {
                    #container{
                        collection = Collection,
                        from_list = FromList,
                        orddict = Orddict
                    } = Container,
                    Limit,
                    FilterMapper
                },
                ?assertContainerEqual(
                    Container,
                    FromList(lists:filtermap(fun typeof_list_filtermapper/1, Orddict)),
                    neo_stream:fold(
                        neo_stream:filtermap(
                            neo_stream:from(Collection),
                            FilterMapper
                        ),
                        neo_collection:new(Collection),
                        fun neo_collection:set/3,
                        #{limit => min(2, Limit)}
                    )
                )
            )
        }
    }).

stream_fusion_test_() ->
    Sentinel = make_ref(),
    [
        ?_quickcheck(
            stream_fusion_property(Sentinel),
            [{numtests, 1000}]
        ),
        ?_counterexample(
            stream_fusion_property(Sentinel),
            [
                {
                    neo_proper_types:new_container(maps, #{
                        orddict => [{<<>>, 0}],
                        collection => #{<<>> => 0}
                    }),
                    new_operator(map, fun ?MODULE:typeof/1),
                    new_operator(map, fun ?MODULE:typeof_mapper/2)
                }
            ]
        ),
        ?_counterexample(
            stream_fusion_property(Sentinel),
            [
                {
                    neo_proper_types:new_container(proplists, #{
                        orddict => [{'', true}],
                        collection => [{'', true}]
                    }),
                    new_operator(filter, fun ?MODULE:value_is_atom/2),
                    new_operator(filter, fun ?MODULE:value_is_atom/2)
                }
            ]
        )
    ].

stream_fusion_property(Sentinel) ->
    ?forall(
        {
            container_type([non_empty]),
            stream_operator_type(),
            stream_operator_type()
        },
        {
            #container{collection = Collection, equals = Equals} = Container0,
            #stream_operator{type = FirstOperatorType} = FirstOperator,
            #stream_operator{type = SecondOperatorType} = SecondOperator
        },
        begin
            io:format("---"),
            Container1 = call_operator(FirstOperator, Container0),
            Container2 = call_operator(SecondOperator, Container1),
            Actual0 = neo_stream:fold(
                neo_stream:SecondOperatorType(
                    neo_stream:FirstOperatorType(
                        neo_stream:from(Collection),
                        FirstOperator#stream_operator.stream_function
                    ),
                    SecondOperator#stream_operator.stream_function
                ),
                neo_collection:new(Collection),
                fun(Accumulator, Key, Value) ->
                    neo_stream:set(Accumulator, Key, Value, Sentinel)
                end
            ),
            Actual1 = remove_sentinel(Actual0, Sentinel),
            case
                Equals(Container2#container.collection, Actual0) orelse
                    Equals(Container2#container.collection, Actual1)
            of
                true ->
                    ok;
                false ->
                    Options = #{color => false},
                    erlang:error(
                        {assertEqual, [
                            {module, ?MODULE},
                            {line, ?LINE},
                            {expression,
                                %% Rebar formats the error message like this:
                                %% ?assertEqual(<expected>, <expression>)
                                neo_test_helpers:flat_format(
                                    "~s |> ~s |> ~s~s (using ~s", [
                                        neo_test_helpers:format(Collection, Options),
                                        format(FirstOperator),
                                        format(SecondOperator),
                                        ?RESET(#{color => true}),
                                        neo_test_helpers:format(Equals, Options)
                                    ]
                                )},
                            {expected, Container2#container.collection},
                            {value, Actual1}
                        ]}
                    )
            end
        end
    ).

%% @private
%% @doc Removes the sentinel used to represent missing values in lists and
%% tuples.
%%
%% This is needed because {@link neo_stream:set/4} pads lists and tuples with a
%% sentinel value when the index is out of range. But {@link lists:filter/2},
%% which is used to calculate the facit, does not. The solution is to just
%% delete the sentinel.
remove_sentinel(Collection, Sentinel) when is_list(Collection) ->
    [Element || Element <- Collection, Element =/= Sentinel];
remove_sentinel(Collection, Sentinel) when is_tuple(Collection) ->
    case neo_reflect:implementation_for(Collection, [neo_stream]) of
        neo_tuples ->
            list_to_tuple(remove_sentinel(tuple_to_list(Collection), Sentinel));
        _ ->
            Collection
    end;
remove_sentinel(Collection, _Sentinel) ->
    Collection.

foreach_test_() ->
    neo_test_helpers:test_case(#{
        "iterable" => #{
            "arity 1" => ?_quickcheck(
                container_type([non_empty]),
                #container{
                    collection = Collection,
                    orddict = Orddict
                },
                begin
                    erlang:put(counter, 0),
                    neo_iterable:foreach(Collection, fun(_Value) ->
                        erlang:put(counter, erlang:get(counter) + 1)
                    end),
                    ?assertEqual(length(Orddict), erlang:get(counter))
                end
            ),
            "arity 2" => ?_quickcheck(
                container_type([non_empty]),
                #container{
                    collection = Collection,
                    orddict = Orddict
                },
                begin
                    Tid = reset_table(),
                    Counters = lists:foldl(
                        fun count_orddict/2,
                        new_counter(),
                        orddict:map(fun typeof_orddict_mapper/2, Orddict)
                    ),
                    neo_iterable:foreach(Collection, fun(Key, Value) ->
                        increment_key(Tid, Key, Value)
                    end),
                    ?assertEqual(Counters, #{
                        integer => lookup_counter(Tid, integer),
                        binary => lookup_counter(Tid, binary),
                        term => lookup_counter(Tid, term)
                    })
                end
            )
        },
        "stream" => #{
            "without limit" => ?_quickcheck(
                container_type([non_empty]),
                #container{
                    collection = Collection,
                    orddict = Orddict
                },
                begin
                    Tid = reset_table(),
                    Counters = lists:foldl(
                        fun count_orddict/2,
                        new_counter(),
                        orddict:map(fun typeof_orddict_mapper/2, Orddict)
                    ),
                    neo_stream:fold(
                        neo_stream:foreach(
                            neo_stream:from(Collection), fun(Key, Value) ->
                                increment_key(Tid, Key, Value)
                            end
                        ),
                        ok,
                        fun(_Key, _Value, ok) -> ok end
                    ),
                    ?assertEqual(Counters, #{
                        integer => lookup_counter(Tid, integer),
                        binary => lookup_counter(Tid, binary),
                        term => lookup_counter(Tid, term)
                    })
                end
            ),
            "with limit" => ?_quickcheck(
                {
                    container_type([non_empty]),
                    limit_type()
                },
                {
                    #container{
                        collection = Collection,
                        orddict = Orddict
                    },
                    Limit
                },
                begin
                    Tid = reset_table(),
                    Counters = lists:foldl(
                        fun count_orddict/2,
                        new_counter(),
                        orddict:map(fun typeof_orddict_mapper/2, Orddict)
                    ),
                    neo_stream:fold(
                        neo_stream:foreach(
                            neo_stream:from(Collection), fun(Key, Value) ->
                                increment_key(Tid, Key, Value)
                            end
                        ),
                        ok,
                        fun(_Key, _Value, ok) -> ok end,
                        #{limit => min(2, Limit)}
                    ),
                    ?assertEqual(Counters, #{
                        integer => lookup_counter(Tid, integer),
                        binary => lookup_counter(Tid, binary),
                        term => lookup_counter(Tid, term)
                    })
                end
            )
        }
    }).

concat_test_() ->
    [
        ?_quickcheck(
            container_of_containers_type([
                non_empty, without_lists, without_tuples, without_array
            ]),
            #container{
                collection = Collection
            },
            begin
                Expected = [
                    Term
                 || {_, Container} <- neo_stream:to_list(neo_stream:from(Collection)),
                    Term <- neo_stream:to_list(
                        neo_stream:from(Container#container.collection)
                    )
                ],
                IteratorOfIterators = iterator_of_iterators(Collection),
                Actual = neo_stream:to_list(neo_stream:concat(IteratorOfIterators)),
                ?assertEqual(Expected, Actual)
            end
        )
    ].

%%%_ * Types -----------------------------------------------------------------

limit_type() ->
    default(1, ?SIZED(Size, proper_types:integer(1, Size))).

count_folder_type() ->
    oneof([
        fun ?MODULE:count_typeof/2,
        fun ?MODULE:count_typeof/3
    ]).

typeof_stream_mapper_type() ->
    oneof([
        fun ?MODULE:typeof/1,
        fun ?MODULE:typeof_mapper/2
    ]).

typeof_iterable_mapper_type() ->
    oneof([
        fun ?MODULE:typeof/1,
        fun ?MODULE:typeof_iterable_mapper/2
    ]).

typeof_filter_type() ->
    oneof([
        %% Arity 1
        oneof([
            fun erlang:is_binary/1,
            fun erlang:is_integer/1,
            fun erlang:is_atom/1,
            fun ?MODULE:value_is_binary_or_integer/1
        ]),
        %% Arity 2
        oneof([
            fun ?MODULE:key_is_integer/2,
            fun ?MODULE:key_is_binary/2,
            fun ?MODULE:value_is_integer/2,
            fun ?MODULE:value_is_binary/2,
            fun ?MODULE:key_and_value_are_same_type/2
        ])
    ]).

typeof_stream_filtermapper_type() ->
    oneof([
        fun ?MODULE:typeof_filtermapper/1,
        fun ?MODULE:typeof_filtermapper/2
    ]).

typeof_iterable_filtermapper_type() ->
    oneof([
        fun ?MODULE:typeof_filtermapper/1,
        fun ?MODULE:typeof_iterable_filtermapper/2
    ]).

stream_operator_type() ->
    oneof([
        map_stream_operator(),
        filter_stream_operator(),
        filtermap_stream_operator()
    ]).

map_stream_operator() ->
    ?LET(Mapper, typeof_stream_mapper_type(), new_operator(map, Mapper)).

filter_stream_operator() ->
    ?LET(Filter, typeof_filter_type(), new_operator(filter, Filter)).

filtermap_stream_operator() ->
    ?LET(
        FilterMapper,
        typeof_stream_filtermapper_type(),
        new_operator(filtermap, FilterMapper)
    ).

%%%_* Private ----------------------------------------------------------------

new_operator(map, Mapper) ->
    #stream_operator{
        type = map,
        orddict_function = stream_to_orddict(Mapper, #{
            fun erlang:is_binary/1 => fun ?MODULE:value_is_binary/2,
            fun erlang:is_integer/1 => fun ?MODULE:value_is_integer/2,
            fun erlang:is_atom/1 => fun ?MODULE:value_is_atom/2,
            fun ?MODULE:value_is_binary_or_integer/1 => fun ?MODULE:value_is_binary_or_integer/2,
            fun ?MODULE:typeof_mapper/2 => fun ?MODULE:typeof_orddict_mapper/2
        }),
        stream_function = Mapper
    };
new_operator(filter, Filter) ->
    #stream_operator{
        type = filter,
        orddict_function = stream_to_orddict(Filter, #{}),
        stream_function = Filter
    };
new_operator(filtermap, FilterMapper0) ->
    FilterMapper1 = stream_to_orddict(FilterMapper0, #{}),
    #stream_operator{
        type = filtermap,
        module = lists,
        orddict_function = fun({Key, Value}) ->
            case FilterMapper1(Key, Value) of
                {true, NewKey, NewValue} -> {true, {NewKey, NewValue}};
                {true, NewValue} -> {true, {Key, NewValue}};
                true -> true;
                false -> false
            end
        end,
        stream_function = FilterMapper0
    }.

stream_to_orddict(Fun, Lookup) when is_map_key(Fun, Lookup) ->
    maps:get(Fun, Lookup);
stream_to_orddict(Fun, _Lookup) when is_function(Fun, 1) ->
    fun(_Key, Value) -> Fun(Value) end;
stream_to_orddict(Fun, _Lookup) when is_function(Fun, 2) ->
    Fun.

call_operator(
    #stream_operator{type = Type, module = Module, orddict_function = OrddictFun} =
        Operator,
    #container{from_list = FromList, orddict = Orddict0} = Container
) ->
    Orddict1 = Module:Type(OrddictFun, Orddict0),
    io:format("~p |> ~s |> ~p\n", [
        Orddict0, format(Operator), Orddict1
    ]),
    Container#container{collection = FromList(Orddict1), orddict = Orddict1}.

%% @doc `count/3' for use with {@link lists:fold/3} over a orddict/list of
%% two-tuples.
count_orddict({_Key, Type}, Counters) ->
    Counters#{Type := 1 + maps:get(Type, Counters)}.

%% @doc Increments the count for the given `Type'.
%%
%% This is used to test folding.
count_typeof(Counters, _Key, Value) ->
    count_typeof(Counters, Value).

%% @doc Increments the count for the given `Type'.
%%
%% This is used to test folding.
count_typeof(Counters, Value) ->
    Type = typeof(Value),
    Counters#{Type := 1 + maps:get(Type, Counters)}.

%% @private
new_counter() ->
    #{
        integer => 0,
        binary => 0,
        term => 0
    }.

%% @doc Return the type of the given `Term'.
%%
%% Used for testing mapping and filtering functions.
-spec typeof(term()) -> integer | binary | term.
typeof(Integer) when is_integer(Integer) ->
    integer;
typeof(Binary) when is_binary(Binary) ->
    binary;
typeof(_Term) ->
    term.

%% @doc `typeof/2' for use in {@link orddict:map/2}.
typeof_orddict_mapper(_Key, Value) ->
    typeof(Value).

%% @doc `typeof/2' for use in {@link neo_stream:map/2}.
typeof_mapper(Key, Value) ->
    {Key, typeof(Value)}.

%% @doc `typeof/2' for use in {@link neo_iterable:map/2}.
typeof_iterable_mapper(_Key, Value) ->
    typeof(Value).

%% @doc Return `true' if the given `Value' is a binary or integer.
%%
%% Used for testing filtering functions.
value_is_binary_or_integer(Value) ->
    typeof(Value) =/= term.

%% @equiv value_is_binary_or_integer(Value)
value_is_binary_or_integer(_Key, Value) ->
    value_is_binary_or_integer(Value).

%% @doc `key_is_integer/2' for use in {@link orddict:filter/2}.
key_is_integer(Key, _Value) ->
    is_integer(Key).

%% @doc `key_is_binary/2' for use in {@link orddict:filter/2}.
key_is_binary(Key, _Value) ->
    is_binary(Key).

%% @doc `value_is_atom/2' for use in {@link orddict:filter/2}.
value_is_atom(_Key, Value) ->
    is_atom(Value).

%% @doc `value_is_binary/2' for use in {@link orddict:filter/2}.
value_is_binary(_Key, Value) ->
    is_binary(Value).

%% @doc `value_is_integer/2' for use in {@link orddict:filter/2}.
value_is_integer(_Key, Value) ->
    is_integer(Value).

%% @doc `key_and_value_are_same_type/2' for use in {@link orddict:filter/2}.
key_and_value_are_same_type(Key, Value) ->
    typeof(Key) =:= typeof(Value).

%% @doc `typeof_filtermapper/1' for use in {@link lists:filtermap/2} over a
%% orddict/list of two-tuples.
typeof_list_filtermapper({Key, Value}) ->
    case typeof(Value) of
        binary -> {true, {Key, binary}};
        integer -> true;
        term -> false
    end.

%% @doc `typeof_filtermapper/1' for use in {@link neo_stream:filtermap/2}.
typeof_filtermapper(Value) ->
    case typeof(Value) of
        binary -> {true, binary};
        integer when Value rem 2 =:= 0 -> {true, Value};
        integer -> true;
        term -> false
    end.

%% @doc `typeof_filtermapper/2' for use in {@link neo_stream:filtermap/2}.
typeof_filtermapper(Key, Value) ->
    case typeof(Value) of
        binary -> {true, Key, binary};
        integer when Value rem 2 =:= 0 -> {true, Value};
        integer -> true;
        term -> false
    end.

%% @doc `typeof_filtermapper/2' for use in {@link neo_iterable:filtermap/2}.
typeof_iterable_filtermapper(_Key, Value) ->
    case typeof(Value) of
        binary -> {true, binary};
        integer when Value rem 2 =:= 0 -> {true, Value};
        integer -> true;
        term -> false
    end.

reset_table() ->
    case ets:whereis(foreach_test_table) of
        undefined ->
            ets:new(foreach_test_table, [public]);
        Tid ->
            ets:delete_all_objects(Tid),
            Tid
    end.

increment_key(Tid, _Key, Value) ->
    Type = typeof(Value),
    ets:update_counter(Tid, Type, 1, {Type, 0}).

lookup_counter(Tid, Type) ->
    case ets:match(Tid, {Type, '$1'}) of
        [[Count]] -> Count;
        [] -> 0
    end.

iterator_of_iterators(Collection) ->
    iterator_of_iterators(Collection, neo_stream:next(neo_stream:from(Collection))).

iterator_of_iterators(Collection, none) ->
    neo_stream:from(Collection);
iterator_of_iterators(
    Collection, {Key, #container{collection = InnerCollection}, Iterator}
) ->
    InnerIterator = neo_stream:from(InnerCollection),
    iterator_of_iterators(
        neo_collection:set(Collection, Key, InnerIterator),
        neo_stream:next(Iterator)
    ).
