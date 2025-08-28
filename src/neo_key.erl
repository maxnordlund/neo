%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% @doc Functions for working with {@link neo_collection:t() collections} of
%%% {@link neo_collection:t() collections} via their keys.
%%%
%%% Heavily inspired by the `key*' functions in `lists'.
%%% @end
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%%%_* Module declaration =====================================================
-module(neo_key).

%%%_* Behaviours =============================================================

%%%_* Exports ================================================================
%%%_ * API -------------------------------------------------------------------
-export([
    delete/3,
    find/3,
    get/2,
    get/3,
    map/3,
    member/3,
    merge/3,
    replace/4,
    sort/2,
    store/4,
    take/3,
    unique_merge/3,
    unique_sort/2
]).

%%%_* Types ------------------------------------------------------------------

%%%_* Includes ===============================================================

%%%_* Macros =================================================================

%%%_* Types ==================================================================

%%%_* Code ===================================================================
%%%_ * API -------------------------------------------------------------------
%% @doc Returns a list of maps where each map with Key = Value is removed.
delete(Maps, Key, Value) ->
    [
        Current
     || Current <- Maps,
        case Current of
            #{Key := CurrentValue} -> CurrentValue =/= Value;
            _Otherwise -> true
        end
    ].

%% @doc Returns the map that has Key associated with Value, or false if not found.
-spec find([Map], Key, Value) -> Map | false when Map :: #{Key => Value}.
find([Map | _Maps], Key, Value) when map_get(Key, Map) == Value ->
    Map;
find([_Map | Maps], Key, Value) ->
    find(Maps, Key, Value);
find([], _Key, _Value) ->
    false.

%% @doc Returns the value associated with Key for each map that contains Key.
get([Map | Maps], Key) when is_map_key(Key, Map) ->
    [maps:get(Key, Map) | get(Maps, Key)];
get([_Map | Maps], Key) ->
    get(Maps, Key);
get([], _Key) ->
    [].

%% @doc Like get/2 except maps missing Key are replaced with Default.
get([Map | Maps], Key, Default) when is_map(Map) ->
    [maps:get(Key, Map, Default) | get(Maps, Key, Default)];
get([_Map | Maps], Key, Default) ->
    get(Maps, Key, Default);
get([], _Key, _Default) ->
    [].

%% @doc Returns a list of maps where each map with Key is replaced by Fun(Map).
-spec map([Map], Key, Fun) -> [Map] when
    Map :: #{Key => _Value},
    Fun :: fun((Map) -> Map).
map([Map | Maps], Key, Fun) when is_map_key(Key, Map) ->
    [Fun(Map) | map(Maps, Key, Fun)];
map([Map | Maps], Key, Fun) ->
    [Map | map(Maps, Key, Fun)];
map(Maps, _Key, _Fun) ->
    Maps.

%% @doc Returns true if there is a map with Key = Value, false otherwise.
member([Map | _Maps], Key, Value) when map_get(Key, Map) == Value -> true;
member([_Map | Maps], Key, Value) -> member(Maps, Key, Value);
member([], _Key, _Value) -> false.

%% @doc Similar to lists:keymerge except lists need not be sorted or deduped.
merge(Maps, Key, Defaults) ->
    merger(Maps, Key, Defaults, fun lists:keysort/2, fun lists:keymerge/3).

%% @doc Similar to lists:ukeymerge except lists need not be sorted or deduped.
unique_merge(Maps, Key, Defaults) ->
    merger(Maps, Key, Defaults, fun lists:ukeysort/2, fun lists:ukeymerge/3).

%% @doc Returns a list of maps where each map with Key = Value is replaced by Replacement.
replace([Map | Maps], Key, Value, Replacement) when map_get(Key, Map) == Value ->
    [Replacement | Maps];
replace([Map | Maps], Key, Value, Replacement) ->
    [Map | replace(Maps, Key, Value, Replacement)];
replace([], _Key, _Value, _Replacement) ->
    [].

%% @doc Sorts maps by Key using lists:keysort.
sort(Maps, Key) ->
    sorter(Maps, Key, fun lists:keysort/2).

%% @doc Sorts maps by Key using lists:ukeysort.
unique_sort(Maps, Key) ->
    sorter(Maps, Key, fun lists:ukeysort/2).

%% @doc Returns a list of maps where the first map with Key = Value is replaced by NewMap.
store([Map | Maps], Key, Value, NewMap) when map_get(Key, Map) == Value ->
    [NewMap | Maps];
store([Map | Maps], Key, Value, NewMap) ->
    [Map | store(Maps, Key, Value, NewMap)];
store([], _Key, _Value, NewMap) ->
    [NewMap].

%% @doc Takes the first map with Key = Value, returns {value, Map, Rest} or false.
take([Map | Maps], Key, Value) when map_get(Key, Map) == Value ->
    {value, Map, Maps};
take([Map | Maps], Key, Value) ->
    case take(Maps, Key, Value) of
        {value, Found, Tail} -> {value, Found, [Map | Tail]};
        false -> false
    end;
take([], _Key, _Value) ->
    false.

%%%_* Private ----------------------------------------------------------------
%% @private
%% @doc Returns a list of {Value, Map} tuples for each map with Key.
-spec to_value_map_tuple_list([Map], Key) -> [{Value, Map}] when
    Map :: #{Key => Value}.
to_value_map_tuple_list(Maps, Key) ->
    [
        {Value, Map}
     || #{Key := Value} = Map <- Maps
    ].

%% @private
%% @doc Helper for merge/3 and unique_merge/3.
merger(Maps, Key, Defaults, SorterFun, MergerFun) ->
    List = SorterFun(1, to_value_map_tuple_list(Maps, Key)),
    DefaultList = SorterFun(1, to_value_map_tuple_list(Defaults, Key)),
    [
        Map
     || {_Value, Map} <- MergerFun(1, List, DefaultList)
    ].

%% @private
%% @doc Helper for sort/2 and unique_sort/2.
-spec sorter([Map], Key, fun((pos_integer(), TupleList) -> TupleList)) -> [Map] when
    Map :: #{Key => Value},
    TupleList :: [{Value, Map}].
sorter(Maps, Key, SorterFun) ->
    [
        %% dialyzer complains if you match the tuple directly:
        %% {_Value, Map} <- SorterFun(...)
        %% This is a workaround, but while we're at it, let's make a nicer
        %% error message in case the impossible happens.
        case Tuple of
            {_Value, Map} ->
                Map;
            Unknown ->
                erlang:error(
                    unicode:characters_to_list(
                        io_lib:format(
                            "expected neo_key:to_value_map_tuple_list to return 2-tuples only, instead got ~W",
                            [Unknown, 10]
                        )
                    ),
                    [Maps, Key, SorterFun]
                )
        end
     || Tuple <- SorterFun(1, to_value_map_tuple_list(Maps, Key))
    ].

%%%_* Tests ==================================================================
-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-include("test_helpers.hrl").

replace_test_() ->
    ?function_test(
        replace(Maps, Key, Value, Target),
        [Maps, Key, Value, Target],
        #{
            [[], key, target, #{replacement => map}] =>
                [],
            [[#{key => target}], key, other, #{replacement => map_per}] =>
                [#{key => target}],
            [[#{key => target}], key, target, #{replacement => map}] =>
                [#{replacement => map}],
            [[#{key => target, unrelated => 123}], key, other, #{replacement => map}] =>
                [#{key => target, unrelated => 123}],
            [[#{key => target, unrelated => 123}], key, target, #{replacement => map}] =>
                [#{replacement => map}],
            [
                [#{key => target}, #{unrelated => 123}],
                key,
                target,
                #{replacement => map}
            ] =>
                [#{replacement => map}, #{unrelated => 123}]
        }
    ).

delete_test_() ->
    ?function_test(
        delete(Maps, Key, Target),
        [Maps, Key, Target],
        #{
            [[], some_key, target] =>
                [],
            [[#{}], some_key, target] =>
                [#{}],
            [[#{key => target}], key, other] =>
                [#{key => target}],
            [[#{key => target}], key, target] =>
                [],
            [[#{key => target}, #{key => unrelated}], key, target] =>
                [#{key => unrelated}]
        }
    ).

find_test_() ->
    ?function_test(
        find(Maps, Key, Target),
        [Maps, Key, Target],
        #{
            [[], key, target] =>
                false,
            [[#{}], key, target] =>
                false,
            [[#{key => target}], key, other] =>
                false,
            [[#{key => target}], key, target] =>
                #{key => target},
            [[#{key => target}, #{key => other}], key, target] =>
                #{key => target}
        }
    ).

-endif.
