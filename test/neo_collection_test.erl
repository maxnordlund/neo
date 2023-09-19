%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% @doc {@link proper. PropEr} tests for {@link neo_collection}
%%% @end
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%%%_* Module declaration =====================================================
-module(neo_collection_test).

%%%_* Exports ================================================================
%%%_ * API -------------------------------------------------------------------
-export([]).

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

%%%_ * Collection -----------------------------------------------------------

new_test_() ->
    neo_test_helpers:test_case(#{
        "from module" => ?_quickcheck(
            container_type(),
            #container{new = New, type = Type},
            neo_collection:new(Type) =:= New()
        ),
        "from collection" => ?_quickcheck(
            container_type(),
            #container{collection = Collection, equals = Equals, new = New},
            Equals(neo_collection:new(Collection), New())
        )
    }).

to_test() ->
    ?quickcheck(
        ?LET(
            From,
            container_type([empty]),
            ?LET(
                To,
                ?SUCHTHATMAYBE(
                    To, container_type(), From#container.module =/= To#container.module
                ),
                {From, To, oneof([To#container.type, To#container.collection])}
            )
        ),
        {
            #container{collection = Collection, keys = FromKeys},
            #container{keys = ToKeys},
            TargetType
        },
        ordsets:from_list(FromKeys(Collection)) =:=
            ordsets:from_list(ToKeys(neo_collection:to(Collection, TargetType)))
    ).

size_test() ->
    ?quickcheck(
        container_type(),
        #container{collection = Collection, size = Size},
        Size(Collection) =:= neo_collection:size(Collection)
    ).

keys_test() ->
    ?quickcheck(
        container_type(),
        #container{collection = Collection, keys = Keys},
        lists:sort(neo_collection:keys(Collection)) =:= lists:sort(Keys(Collection))
    ).

values_test() ->
    ?quickcheck(
        container_type(),
        #container{collection = Collection, orddict = Orddict},
        lists:sort(neo_collection:values(Collection)) =:=
            lists:sort([Value || {_Key, Value} <- Orddict])
    ).

has_test_() ->
    neo_test_helpers:test_case(#{
        "existing" => ?_quickcheck(
            container_with_key_type([without_tuples]),
            {#container{collection = Collection}, Key},
            neo_collection:has(Collection, Key)
        ),
        "empty collection" => ?_quickcheck(
            container_with_key_type(),
            {#container{new = New}, Key},
            not neo_collection:has(New(), Key)
        ),
        "missing" => fun() ->
            Sentinel = make_ref(),
            ?quickcheck(
                container_with_missing_key_type(Sentinel),
                {#container{collection = Collection}, MissingKey},
                is_boolean(neo_collection:has(Collection, MissingKey))
            )
        end
    }).

get_test_() ->
    neo_test_helpers:test_case(#{
        "existing prop" => ?_quickcheck(
            container_with_key_type(),
            {#container{collection = Collection, get = Get}, Key},
            neo_collection:get(Collection, Key) =:= Get(Key, Collection)
        ),
        "missing prop" => fun() ->
            Sentinel = make_ref(),
            ?quickcheck(
                container_with_missing_key_type(Sentinel),
                {
                    #container{collection = Collection, module = Module} = Container,
                    MissingKey
                },
                try neo_collection:get(Collection, MissingKey) of
                    _ ->
                        false
                catch
                    error:{badkey, MissingKey} ->
                        true;
                    error:{badarg, MissingKey} when ?is_tuple_type(Container) ->
                        true;
                    error:badarg when Module =:= dict ->
                        true;
                    error:function_clause:Stacktrace ->
                        case Stacktrace of
                            [{orddict, fetch, _, _} | _] ->
                                true;
                            _ ->
                                erlang:raise(error, function_clause, Stacktrace)
                        end
                end
            )
        end,
        "default for existing prop" => fun() ->
            Sentinel = make_ref(),
            ?quickcheck(
                container_with_key_type(),
                {#container{collection = Collection}, Key},
                neo_collection:get(Collection, Key, Sentinel) =/= Sentinel
            )
        end,
        "default for missing prop" => fun() ->
            Sentinel = make_ref(),
            ?quickcheck(
                container_with_missing_key_type(Sentinel),
                {#container{collection = Collection}, MissingKey},
                neo_collection:get(Collection, MissingKey, Sentinel) =:= Sentinel
            )
        end
    }).

fetch_test_() ->
    neo_test_helpers:test_case(#{
        "fetch existing" => ?_quickcheck(
            container_with_key_type(),
            {#container{collection = Collection, get = Get}, Key},
            neo_collection:fetch(Collection, Key) =:= {ok, Get(Key, Collection)}
        ),
        "fetch missing" => fun() ->
            Sentinel = make_ref(),
            ?quickcheck(
                container_with_missing_key_type(Sentinel),
                {#container{collection = Collection}, MissingKey},
                neo_collection:fetch(Collection, MissingKey) =:= {error, notfound}
            )
        end
    }).

set_test_() ->
    neo_test_helpers:test_case(#{
        "set existing" => fun() ->
            Sentinel = make_ref(),
            ?quickcheck(
                container_with_key_type(),
                {#container{collection = Collection, get = Get}, Key},
                Get(Key, neo_collection:set(Collection, Key, Sentinel)) =:= Sentinel
            )
        end,
        "set missing" => fun() ->
            Sentinel = make_ref(),
            ?quickcheck(
                container_with_missing_settable_key_type(Sentinel, []),
                {#container{collection = Collection, get = Get}, MissingKey},
                Get(MissingKey, neo_collection:set(Collection, MissingKey, Sentinel)) =:=
                    Sentinel
            )
        end
    }).

delete_test_() ->
    neo_test_helpers:test_case(#{
        "delete existing" => ?_quickcheck(
            container_with_key_type(),
            {
                #container{collection = Collection, delete = Delete, equals = Equals},
                Key
            },
            Equals(neo_collection:delete(Collection, Key), Delete(Key, Collection))
        ),
        "delete missing" => fun() ->
            Sentinel = make_ref(),
            ?quickcheck(
                container_with_missing_key_type(Sentinel, [non_empty]),
                {#container{collection = Collection}, MissingKey},
                neo_collection:delete(Collection, MissingKey) =:= Collection
            )
        end
    }).

merge_test() ->
    ?quickcheck(
        {
            container_type([non_empty, without_lists, without_tuples, without_array]),
            container_type([without_lists, without_tuples, without_array])
        },
        {
            #container{
                collection = CollectionA, equals = EqualsA, from_list = FromListA
            } = ContainerA,
            #container{collection = CollectionB} = ContainerB
        },
        begin
            Merged = FromListA(prefer_b(ContainerA, ContainerB)),
            EqualsA(Merged, neo_collection:merge(CollectionA, CollectionB))
        end
    ).

merge_with_test_() ->
    [
        {
            lists:flatten(
                string:replace(
                    atom_to_list(element(2, erlang:fun_info(Merger, name))),
                    "_",
                    " ",
                    all
                )
            ),
            ?_quickcheck(
                {
                    container_type([
                        non_empty, without_lists, without_tuples, without_array
                    ]),
                    container_type([without_lists, without_tuples, without_array])
                },
                {
                    #container{
                        collection = CollectionA,
                        equals = EqualsA,
                        from_list = FromListA
                    } = ContainerA,
                    #container{
                        collection = CollectionB,
                        equals = EqualsB,
                        from_list = FromListB
                    } = ContainerB
                },
                EqualsA(
                    FromListA(Merger(ContainerA, ContainerB)),
                    neo_collection:merge_with(
                        CollectionA, CollectionB, Combiner
                    )
                ) orelse
                    EqualsB(
                        FromListB(Merger(ContainerA, ContainerB)),
                        neo_collection:merge_with(
                            CollectionA, CollectionB, Combiner
                        )
                    )
            )
        }
     || {Merger, Combiner, _GetPreferred} <- [
            {fun prefer_a/2, fun prefer_a_combiner/3, fun get_a_preferred/2},
            {fun prefer_b/2, fun prefer_b_combiner/3, fun get_b_preferred/2}
        ]
    ].

%%%_ * Types ----------------------------------------------------------------

%%%_* Private ----------------------------------------------------------------

prefer_a(
    #container{collection = CollectionA, to_list = ToListA},
    #container{collection = CollectionB, to_list = ToListB}
) ->
    lists:sort(
        maps:to_list(
            maps:merge(
                maps:from_list(ToListB(CollectionB)),
                maps:from_list(ToListA(CollectionA))
            )
        )
    ).

prefer_a_combiner(_Key, ValueA, _ValueB) ->
    ValueA.

get_a_preferred(#container{} = Container, #container{}) ->
    Container.

prefer_b(
    #container{collection = CollectionA, to_list = ToListA},
    #container{collection = CollectionB, to_list = ToListB}
) ->
    lists:sort(
        maps:to_list(
            maps:merge(
                maps:from_list(ToListA(CollectionA)),
                maps:from_list(ToListB(CollectionB))
            )
        )
    ).

prefer_b_combiner(_Key, _ValueA, ValueB) ->
    ValueB.

get_b_preferred(#container{}, #container{} = Container) ->
    Container.

%%%_* Tests ==================================================================
-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif.
