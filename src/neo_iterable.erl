%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% @doc A behaviour for iterable data types.
%%%
%%% The core of this module builds upon {@link iterator/1} and {@link next/1}.
%%% If you do not implement this, it will fall back to a generic one using
%%% {@link neo_collection:keys/1} and {@link neo_collection:get/2}.
%%%
%%% This means users of this module does not need to worry about it, but for
%%% optimal performance a specialized implementation should be provided.
%%% @end
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%%%_* Module declaration =====================================================
-module(neo_iterable).

%%%_* Exports ================================================================
%%%_ * API -------------------------------------------------------------------
-export([
    iterator/1,
    next/1
]).

-export([
    filter/2,
    filtermap/2,
    fold/3,
    foreach/2,
    group_by/2,
    map/2,
    mapfold/3
]).

%%%_* Types ------------------------------------------------------------------
-export_type([
    iterator/0,
    iterator/2,
    iterator_state/2
]).

-export_type([
    filter/2,
    filter_mapper/3,
    folder/3,
    foreach_fun/2,
    limit/0,
    mapper/3
]).

%%%_* Callbacks ==============================================================
%% This function is called to create an iterator for the given
%% {@link t(). collection}.
%%
%% The returned value is considered an implementation detail of the
%% implementing module.
-callback iterator(neo_collection:t(Key, Value)) -> iterator_state(Key, Value).

%% This function is called to retreive a `Key'-`Value' pair and the next
%% {@link iterator_state(). internal iterator state} from the given
%% {@link iterator_state(). internal iterator state}.
%%
%% @see next/1
-callback next(iterator_state(Key, Value)) ->
    {Key, Value, iterator_state(Key, Value)} | none.

%%%_ * Optional callbacks ----------------------------------------------------
-optional_callbacks([
    iterator/1,
    next/1
]).

%%%_* Includes ===============================================================
-include("internal.hrl").

%%%_* Macros =================================================================

%%%_* Types ==================================================================
-opaque iterator() :: iterator(Key :: term(), Value :: term()).

-opaque iterator(Key, Value) :: {module(), iterator_state(Key, Value)}.
%% Represents an iterator of some iterable, typically a
%% {@link neo_collection:t()}. Is considered an implementation detail of this
%% module.

-type iterator_state(_Key, _Value) :: term().
%% Represents the internal state of an {@link iterator()}.
%%
%% Used to implement {@link next/1}.

-type mapper(Key, ValueIn, ValueOut) ::
    fun((Key, ValueIn) -> ValueOut) | fun((ValueIn) -> ValueOut).
%% A mapping function, just like the first parameter of {@link maps:map/2}.

-type filter(Key, Value) :: fun((Key, Value) -> boolean()) | fun((Value) -> boolean()).
%% A filter function, just like the first parameter of {@link maps:filter/2}.

-type filter_mapper(Key, ValueIn, ValueOut) ::
    fun((Key, ValueIn) -> boolean() | {true, ValueIn | ValueOut})
    | fun((ValueIn) -> boolean() | {true, ValueIn | ValueOut}).
%% A filter and mapping function, just like the first parameter of
%% {@link maps:filtermap/2}.

-type foreach_fun(Key, Value) :: fun((Key, Value) -> any()) | fun((Value) -> any()).
%% A `fun' just like the first parameter of {@link maps:foreach/2}.

-type folder(Accumulator, Key, Value) ::
    fun((Accumulator, Key, Value) -> Accumulator).
%% A folding function, similar like the first parameter of {@link maps:fold/3},
%% except the `Accumulator' comes first.

-type limit() :: pos_integer().
%% Concurrency limit, aka the number of processes to keep in-flight.

%%%_* Private ----------------------------------------------------------------

%%%_* Code ===================================================================
%%%_ * API -------------------------------------------------------------------

%% @doc Returns an {@link iterator()} for the given
%% {@link neo_collection:t(). collection}.
-spec iterator(neo_collection:t(Key, Value)) -> iterator(Key, Value).
iterator(Collection) ->
    Module = implementation_for(Collection),
    case neo_reflect:is_exported(Module, iterator, 1) of
        true ->
            {Module, Module:iterator(Collection)};
        false ->
            {?MODULE, neo_collection:keys(Collection), Collection}
    end.

%% @doc Returns a `Key'-`Value' pair and the next iterator, or `none' if the
%% iterator is empty.
-spec next(iterator(Key, Value)) -> {Key, Value, iterator(Key, Value)} | none.
next({?MODULE, [], _Collection}) ->
    none;
next({?MODULE, [Key | Keys], Collection}) ->
    {Key, neo_collection:get(Collection, Key), {?MODULE, Keys, Collection}};
next({Module, Iterator}) ->
    case Module:next(Iterator) of
        {Key, Value, NextIterator} ->
            {Key, Value, {Module, NextIterator}};
        none ->
            none
    end.

%% @doc Folds the given function over the given collection.
%%
%% It has the same order guarantees, or not, as the given collection.
%%
%% Like {@link maps:fold/3} but for an arbitrary {@link neo_collection:t().
%% collection}.
-spec fold(
    neo_collection:t(Key, Value), InitialAccumulator, folder(Accumulator, Key, Value)
) -> Accumulator when
    InitialAccumulator :: Accumulator.
fold(Collection, InitialAccumulator, Folder) when is_function(Folder, 3) ->
    Module = implementation_for(Collection),
    case neo_reflect:is_exported(Module, fold, 3) of
        true ->
            Module:fold(Collection, InitialAccumulator, Folder);
        false ->
            fold_internal(iterator(Collection), InitialAccumulator, Folder)
    end.

%% @private
fold_internal(Iterator, Accumulator, Folder) ->
    case next(Iterator) of
        {Key, Value, NextIterator} ->
            fold_internal(NextIterator, Folder(Accumulator, Key, Value), Folder);
        none ->
            Accumulator
    end.

%% @doc Maps the given `Mapper' `fun' over the given
%% {@link neo_collection:t(). collection}.
%%
%% The results are returned with the same ordering guarantee, or not, as the
%% underlying collection.
-spec map(neo_collection:t(Key, ValueIn), mapper(Key, ValueIn, ValueOut)) ->
    neo_collection:t(ValueOut, Key).
map(Collection, Mapper) when ?is_callback(Mapper) ->
    Module = implementation_for(Collection),
    case neo_reflect:is_exported(Module, map, 2) of
        true ->
            Module:map(Collection, Mapper);
        false ->
            fold(Collection, neo_collection:new(Collection), fun(
                CollectionOut, Key, Value
            ) ->
                neo_collection:set(
                    CollectionOut, Key, ?call_callback(Mapper, Key, Value)
                )
            end)
    end.

mapfold(Collection, InitialAccumulator, MapFolder) when
    is_function(MapFolder, 2) orelse is_function(MapFolder, 3)
->
    Module = implementation_for(Collection),
    case neo_reflect:is_exported(Module, mapfold, 3) of
        true ->
            Module:mapfold(Collection, MapFolder, InitialAccumulator);
        false ->
            fold(Collection, InitialAccumulator, fun(
                {CollectionOut, AccumulatorIn}, KeyIn, ValueIn
            ) ->
                Result =
                    if
                        is_function(MapFolder, 2) ->
                            MapFolder(ValueIn, AccumulatorIn);
                        is_function(MapFolder, 3) ->
                            MapFolder(KeyIn, ValueIn, AccumulatorIn)
                    end,
                case Result of
                    {ValueOut, AccumulatorOut} ->
                        {
                            neo_collection:set(CollectionOut, KeyIn, ValueOut),
                            AccumulatorOut
                        };
                    {KeyOut, ValueOut, AccumulatorOut} ->
                        {
                            neo_collection:set(CollectionOut, KeyOut, ValueOut),
                            AccumulatorOut
                        }
                end
            end)
    end.

%% @doc Returns a new {@link neo_collection:t(). collection} for each `Key'-`Value' pair in the given one where `Filter' returns true.
-spec filter(neo_collection:t(Key, Value), filter(Key, Value)) ->
    neo_collection:t(Key, Value).
filter(Collection, Filter) when ?is_callback(Filter) ->
    Module = implementation_for(Collection),
    case neo_reflect:is_exported(Module, filter, 2) of
        true ->
            Module:filter(Collection, Filter);
        false ->
            fold(Collection, neo_collection:new(Collection), fun(
                CollectionOut, Key, Value
            ) ->
                case ?call_callback(Filter, Key, Value) of
                    true ->
                        neo_collection:set(CollectionOut, Key, Value);
                    false ->
                        CollectionOut
                end
            end)
    end.

%% @doc Maps the given `Mapper' `fun' in parallell over the given
%% {@link neo_collection:t(). collection}.
%%
%% The `fun' must behave like the first parameter of {@link maps:filtermap/2}.
%%
%% It will have at most `Limit' number of mapping processes in flight at any
%% given point in time.
%%
%% The results are returned in an undefined order.
-spec filtermap(
    neo_collection:t(Key, ValueIn), filter_mapper(Key, ValueIn, ValueOut)
) -> neo_collection:t(Key, ValueIn | ValueOut).
filtermap(Collection, FilterMapper) when ?is_callback(FilterMapper) ->
    Module = implementation_for(Collection),
    case neo_reflect:is_exported(Module, filtermap, 2) of
        true ->
            Module:filtermap(Collection, FilterMapper);
        false ->
            fold(Collection, neo_collection:new(Collection), fun(
                CollectionOut, Key, Value
            ) ->
                case ?call_callback(FilterMapper, Key, Value) of
                    true ->
                        neo_collection:set(CollectionOut, Key, Value);
                    {true, ValueOut} ->
                        neo_collection:set(CollectionOut, Key, ValueOut);
                    false ->
                        CollectionOut
                end
            end)
    end.

%% @doc Calls given `fun' in parallell over the given
%% {@link neo_collection:t(). collection}.
%%
%% It will have at most `Limit' number of processes in flight at any given
%% point in time.
%%
%% The evaluation order is undefined.
%%
%% @see maps:foreach/2
-spec foreach(neo_collection:t(Key, Value), foreach_fun(Key, Value)) -> ok.
foreach(Collection, Fun) when ?is_callback(Fun) ->
    Module = implementation_for(Collection),
    case neo_reflect:is_exported(Module, foreach, 2) of
        true ->
            Module:foreach(Collection, Fun);
        false ->
            fold(Collection, ok, fun(ok, Key, Value) ->
                ?call_callback(Fun, Key, Value),
                ok
            end)
    end.

group_by(Collection, Grouper) when ?is_callback(Grouper) ->
    Module = implementation_for(Collection),
    case neo_reflect:is_exported(Module, group_by, 2) of
        true ->
            Module:group_by(Collection, Grouper);
        false ->
            {Groups, _} = fold(Collection, {#{}, Grouper}, fun group_by_internal/3),
            Groups
    end.

group_by_internal({Groups0, Mapper}, Key, Value) ->
    Group = ?call_callback(Mapper, Key, Value),
    Groups1 = maps:update_with(
        Group,
        fun(Values) -> [{Key, Value} | Values] end,
        [{Key, Value}],
        Groups0
    ),
    {Groups1, Mapper}.

%%%_* Private ----------------------------------------------------------------
implementation_for(Collection) ->
    neo_reflect:implementation_for(Collection, [?MODULE]).

%%%_* Tests ==================================================================
-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-include_lib("neo/include/test_helpers.hrl").

group_by_test_() ->
    ?function_test(
        group_by(Collection, Mapper),
        [Collection, Mapper],
        #{
            [#{a => map, c => map}, fun value/2] => #{map => [{a, map}, {c, map}]},
            [array:from_list([a, b, a]), fun value/2] => #{
                a => [{2, a}, {0, a}], b => [{1, b}]
            },
            [dict:from_list([{a, dict}, {b, dict}]), fun value/2] => #{
                dict => [{a, dict}, {b, dict}]
            },
            [gb_trees:from_orddict([{a, gb_trees}, {b, gb_trees}]), fun value/2] => #{
                gb_trees => [{b, gb_trees}, {a, gb_trees}]
            }
        }
    ).

value(_Key, Value) -> Value.

-endif.
