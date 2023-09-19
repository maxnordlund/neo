%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% @doc Implementation of {@link neo_collection} for Erlang's builtin `maps'.
%%% @end
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%%%_* Module declaration =====================================================
-module(neo_maps).

%%%_* Behaviours =============================================================
-behaviour(neo_collection).
-behaviour(neo_stream).

%%%_* Exports ================================================================
%%%_ * API -------------------------------------------------------------------
%%%_ * Callbacks -------------------------------------------------------------
-export([
    delete/2,
    fetch/2,
    from_list/1,
    get/2,
    has/2,
    keys/1,
    new/0,
    set/3,
    size/1,
    to_list/1,
    values/1
]).

-export([
    filter/2,
    filtermap/2,
    foreach/2,
    fold/3,
    iterator/1,
    map/2,
    merge/2,
    merge_with/3,
    next/1
]).

%%%_* Types ------------------------------------------------------------------
-export_type([
    iterator/2,
    t/0,
    t/2
]).

%%%_* Includes ===============================================================

%%%_* Macros =================================================================

%%%_* Types ==================================================================
-type t() :: map().

-type t(Key, Value) :: #{Key => Value}.

-record(neo_maps, {
    iterator :: maps:iterator()
}).

-opaque iterator(Key, Value) ::
    #neo_maps{
        iterator :: maps:iterator(Key, Value)
    }.

%%%_* Code ===================================================================
%%%_ * API -------------------------------------------------------------------

%%%_ * Callbacks -------------------------------------------------------------
%% @doc Returns an empty map.
-compile({inline, [new/0]}).
-spec new() -> t().
new() ->
    #{}.

%% @doc Returns a map from the given list of `Key'-`Value' tuples.
-compile({inline, [from_list/1]}).
-spec from_list([{Key, Value}]) -> t(Key, Value).
from_list(List) when is_list(List) ->
    maps:from_list(List).

%% @doc Returns a list of `Key'-`Value' tuples from the given map.
-compile({inline, [to_list/1]}).
-spec to_list(t(Key, Value)) -> [{Key, Value}].
to_list(Dict) ->
    maps:to_list(Dict).

%% @doc Returns the size of the given map.
-compile({inline, [size/1]}).
-spec size(t()) -> non_neg_integer().
size(Map) when is_map(Map) ->
    map_size(Map).

%% @doc Returns the keys in the given map.
-compile({inline, [keys/1]}).
-spec keys(t(Key, _Value)) -> [Key].
keys(Map) when is_map(Map) ->
    maps:keys(Map).

%% @doc Returns the values in the given map.
-compile({inline, [values/1]}).
-spec values(t(Key, _Value)) -> [Key].
values(Map) when is_map(Map) ->
    maps:values(Map).

%% @doc Returns `true' if `Key' is in the given map.
-compile({inline, [has/2]}).
-spec has(t(Key, _Value), Key) -> boolean().
has(Map, Key) when is_map(Map) ->
    is_map_key(Key, Map).

%% @doc Returns the `Value' associated with the given `Key' in the given map.
-compile({inline, [get/2]}).
-spec get(t(Key, Value), Key) -> Value.
get(Map, Key) when is_map(Map) ->
    map_get(Key, Map).

-compile({inline, [fetch/2]}).
-spec fetch(t(Key, Value), Key) -> {ok, Value} | {error, notfound}.
fetch(Map, Key) when is_map(Map) ->
    case maps:find(Key, Map) of
        {ok, Value} -> {ok, Value};
        error -> {error, notfound}
    end.

%% @doc Returns a map with the given `Key' set to the given `Value'.
-compile({inline, [set/3]}).
-spec set(t(Key, Value), Key, Value) -> t(Key, Value).
set(Map, Key, Value) when is_map(Map) ->
    Map#{Key => Value}.

%% @doc Returns a map without the given `Key'.
-compile({inline, [delete/2]}).
-spec delete(t(Key, Value), Key) -> Value.
delete(Map, Key) when is_map(Map) ->
    maps:remove(Key, Map).

%% @doc Returns an {@link maps:iterator(). iterator} for this map.
-compile({inline, [iterator/1]}).
-spec iterator(t(Key, Value)) -> iterator(Key, Value).
iterator(Map) when is_map(Map) ->
    #neo_maps{
        iterator = maps:iterator(Map)
    }.

%% @doc Returns the next `Key'-`Value' pair and new iterator for the given
%% {@link maps:iterator()}. iterator}, or `none' if there's no more pairs.
-spec next(iterator(Key, Value)) ->
    {Key, Value, iterator(Key, Value)} | none.
next(#neo_maps{iterator = MapIterator0} = Iterator) ->
    case maps:next(MapIterator0) of
        {Key, Value, MapIterator1} ->
            {Key, Value, Iterator#neo_maps{iterator = MapIterator1}};
        none ->
            none
    end.

%% @doc Mostly equivalent to `maps:fold(Folder, InitialAccumulator, Map)',
%% however the `Folder' expects the `Accumulator' as the first argument,
%% instead of last like {@link maps:fold/3} does.
-compile({inline, [fold/3]}).
-spec fold(
    t(Key, Value), InitialAccumulator, neo_stream:folder(Accumulator, Key, Value)
) -> Accumulator when
    InitialAccumulator :: term(),
    Accumulator :: InitialAccumulator.
fold(Map, InitialAccumulator, Folder) when is_function(Folder, 3) ->
    maps:fold(
        fun(Key, Value, Accumulator) ->
            Folder(Accumulator, Key, Value)
        end,
        InitialAccumulator,
        Map
    ).

-compile({inline, [map/2]}).
-spec map(t(KeyIn, ValueIn), neo_stream:mapper(KeyIn, ValueIn, KeyOut, ValueOut)) ->
    t(KeyOut, ValueOut).
map(Map, Mapper) when is_function(Mapper, 2) ->
    maps:map(Mapper, Map);
map(Map, Mapper) when is_function(Mapper, 1) ->
    maps:map(
        fun(_Key, ValueIn) ->
            Mapper(ValueIn)
        end,
        Map
    ).

-compile({inline, [filter/2]}).
-spec filter(t(Key, Value), neo_stream:filter(Key, Value)) -> t(Key, Value).
filter(Map, Filter) when is_function(Filter, 2) ->
    maps:filter(Filter, Map);
filter(Map, Filter) when is_function(Filter, 1) ->
    maps:filter(
        fun(_Key, Value) ->
            Filter(Value)
        end,
        Map
    ).

-compile({inline, [filtermap/2]}).
-spec filtermap(
    t(KeyIn, ValueIn), neo_stream:filter_mapper(KeyIn, ValueIn, KeyOut, ValueOut)
) ->
    t(KeyOut, ValueOut).
filtermap(Map, FilterMapper) when is_function(FilterMapper, 2) ->
    maps:filtermap(FilterMapper, Map);
filtermap(Map, FilterMapper) when is_function(FilterMapper, 1) ->
    maps:filtermap(
        fun(_Key, ValueIn) ->
            FilterMapper(ValueIn)
        end,
        Map
    ).

%% @doc
-compile({inline, [foreach/2]}).
-spec foreach(t(Key, Value), neo_stream:foreach_fun(Key, Value)) -> ok.
foreach(Map, Fun) when is_function(Fun, 2) ->
    maps:foreach(Fun, Map);
foreach(Map, Fun) when is_function(Fun, 1) ->
    maps:foreach(
        fun(_Key, Value) ->
            Fun(Value)
        end,
        Map
    ).

-compile({inline, [merge/2]}).
-spec merge(t(KeyA, ValueA), t(KeyB, ValueB)) -> t(KeyOut, ValueOut) when
    KeyOut :: KeyA | KeyB,
    ValueOut :: ValueA | ValueB.
merge(MapA, MapB) ->
    maps:merge(MapA, MapB).

-compile({inline, [merge_with/3]}).
-spec merge_with(
    t(KeyA, ValueA),
    t(KeyB, ValueB),
    neo_collection:combiner(KeyIn, ValueA, ValueB, ValueOut)
) -> t(KeyOut, ValueOut) when
    %% Key is really the _intersection_ of KeyA and KeyB, but Erlang doesn't
    %% support intersection types.
    KeyIn :: KeyA | KeyB,
    KeyOut :: KeyA | KeyB.
merge_with(MapA, MapB, Combiner) ->
    maps:merge_with(Combiner, MapA, MapB).

%%%_* Private ----------------------------------------------------------------

%%%_* Tests ==================================================================
-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif.
