%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% @doc A behaviour for iterable data types, and functions for manipulating
%%% them in a streaming fashion.
%%% @end
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%%%_* Module declaration =====================================================
-module(neo_stream).

%%%_* Exports ================================================================
%%%_ * API -------------------------------------------------------------------
-export([
    from/1,
    next/1,
    next/2,
    to_list/1
]).

-export([
    concat/1,
    filter/2,
    filtermap/2,
    flatmap/2,
    fold/3,
    fold/4,
    foreach/2,
    map/2
]).

%% Needed to be able to asynchronously map over lists and tuples
-export([
    set/4
]).

%%%_* Types ------------------------------------------------------------------
-export_type([
    t/0,
    t/2
]).

-export_type([
    iterator/0,
    iterator/2,
    iterator_state/2,
    next_fun/3
]).

-export_type([
    filter/2,
    filter_mapper/4,
    folder/3,
    foreach_fun/2,
    mapper/4,
    options/0
]).

%%%_* Callbacks ==============================================================
%% This function is called to create an iterator for the given
%% {@link t(). collection}.
%%
%% It must return either a tuple whose first element is the name of the module
%% that implements {@link next/1}, and any internal state it may need. Or a
%% two-tuple whose first element is a {@link next_fun(). next `fun'}.
%%
%% The latter is to make it easy to wrap third-party modules.
%%
%% @see next/1
%% @see iterator()
-callback iterator(neo_collection:t(Key, Value)) -> iterator(Key, Value).

%% This function is called to retreive a `Key'-`Value' pair and the next
%% {@link iterator_state(). internal iterator state} from the given
%% {@link iterator_state(). internal iterator state}.
%%
%% If the {@link iterator()} is a two-tuple, the function is called with just
%% the {@link iterator_state(). internal state}. Otherwise it is called with
%% the original {@link iterator()}.
%%
%% This is done to make it easier to implement wrappers for third-party
%% modules.
%%
%% @see next/1
-callback next(iterator(Key, Value)) ->
    {Key, Value, iterator_state(Key, Value)} | none.

%%%_ * Optional callbacks ----------------------------------------------------

%%%_* Includes ===============================================================
-include("internal.hrl").
-include("assertions.hrl").

%%%_* Macros =================================================================

%%%_* Types ==================================================================
-type iterator() :: iterator(Key :: term(), Value :: term()).
%% Equivalent to `iterator(term(), term())'.

-type iterator(Key, Value) ::
    {next_fun(Key, Value, iterator_state(Key, Value))} | tuple().
%% Represents the return value for the {@link next/1} callback.
%%
%% This type is not as precise as it should be, due to limitations in Erlang.
%% It must be a tuple whose first element is a module that implements this
%% behaviour, <em>or</em> a two-tuple whose first element is a
%% `t:next_fun/3'.

-type iterator_state(_Key, _Value) :: term().
%% Represents the internal state for an {@link iterator()}.
%%
%% Used by {@link next/1} and its corresponding callback.

-opaque t() :: t(Key :: term(), Value :: term()).
%% Equivalent to `t(term(), term())'.

-opaque t(Key, Value) :: iterator(Key, Value).
%% Represents an iterator for some {@link neo_collection:t(). collection}.

-type next_fun(Key, Value, IteratorState) :: fun(
    (iterator(Key, Value)) -> {Key, Value, IteratorState} | none
).
%% A {@link next/1} function.

-type mapper(KeyIn, ValueIn, KeyOut, ValueOut) ::
    fun((KeyIn, ValueIn) -> {KeyOut, ValueOut}) | fun((ValueIn) -> ValueOut).
%% A mapping function, just like the first parameter of {@link maps:map/2}.

-type filter(Key, Value) :: fun((Key, Value) -> boolean()) | fun((Value) -> boolean()).
%% A filter function, just like the first parameter of {@link maps:filter/2}.

-type filter_mapper(KeyIn, ValueIn, KeyOut, ValueOut) ::
    fun((KeyIn, ValueIn) -> boolean() | {true, ValueOut} | {true, KeyOut, ValueOut})
    | fun((ValueIn) -> boolean() | {true, ValueOut}).
%% A filter and mapping function, similar to the first parameter of
%% {@link maps:filtermap/2}.
%%
%% It also allows returning both a new <em>key</em> and value.

-type foreach_fun(Key, Value) :: fun((Key, Value) -> any()) | fun((Value) -> any()).
%% A `fun' just like the first parameter of {@link maps:foreach/2}.

-type folder(Accumulator, Key, Value) ::
    fun((Accumulator, Key, Value) -> Accumulator)
    | fun((Accumulator, Value) -> Accumulator).
%% A folding function, similar like the first parameter of {@link maps:fold/3},
%% except the `Accumulator' comes first.

-type limit() :: pos_integer().
%% Concurrency limit, aka the number of processes to keep in-flight.

-type options() ::
    #{
        limit => limit()
    }
    | proplists:proplist()
    | neo_collection:t(limit, term()).
%% Represents running options for evaluating a stream.

%%%_* Private ----------------------------------------------------------------
-record(neo_stream, {
    type :: map | filter | filtermap | foreach,
    source :: iterator() | none,
    function :: function()
}).

-type neo_stream(KeyIn, ValueIn, KeyOut, ValueOut) ::
    #neo_stream{
        type :: map, function :: mapper(KeyIn, ValueIn, KeyOut, ValueOut)
    }
    | #neo_stream{
        type :: filter, function :: filter(KeyIn, ValueIn)
    }
    | #neo_stream{
        type :: filtermap, function :: filter_mapper(KeyIn, ValueIn, KeyOut, ValueOut)
    }
    | #neo_stream{
        type :: foreach, function :: foreach_fun(KeyIn, ValueIn)
    }.

-record(neo_stream_parallell, {
    ref = make_ref() :: reference(),
    caller = self() :: pid(),
    %% When limit reaches 0 no more workers are spawned.
    limit = 1 :: 0 | limit(),
    in_flight = 0 :: non_neg_integer(),
    source :: #neo_stream{}
}).

-type neo_stream_parallell(KeyIn, ValueIn, KeyOut, ValueOut) ::
    #neo_stream_parallell{
        source :: neo_stream(KeyIn, ValueIn, KeyOut, ValueOut)
    }.

%%%_* Code ===================================================================
%%%_ * API -------------------------------------------------------------------
%% @doc Returns an {@link t(). iterator} for the given
%% {@link neo_collection:t(). collection}
-spec from(neo_collection:t(Key, Value)) -> t(Key, Value).
from(Collection) ->
    Module = implementation_for(Collection),
    case neo_reflect:is_exported(Module, iterator, 1) of
        true -> Module:iterator(Collection);
        false -> neo_collection:iterator(Collection)
    end.

%% @doc Returns a list of all key-value pairs in the given
%% {@link neo_collection:t(). collection}.
-spec to_list(neo_collection:t(Key, Value)) -> [{Key, Value}].
to_list(Iterator) ->
    to_list_internal(next(Iterator), []).

%% @private
to_list_internal(none, List) ->
    lists:reverse(List);
to_list_internal({Key, Value, Iterator}, List) ->
    to_list_internal(next(Iterator), [{Key, Value} | List]).

%% @equiv next(Iterator, #{limit => 1})
-spec next(Iterator) -> {Key, Value, Iterator} | none when
    Iterator :: t(Key, Value).
next(none) ->
    none;
next(#neo_stream{type = map} = Stream) ->
    map_next(Stream);
next(#neo_stream{type = filter} = Stream) ->
    filter_next(Stream);
next(#neo_stream{type = filtermap} = Stream) ->
    filtermap_next(Stream);
next(#neo_stream{type = foreach} = Stream) ->
    foreach_next(Stream);
next(#neo_stream_parallell{source = #neo_stream{type = map}} = State) ->
    map_next_parallell(State);
next(#neo_stream_parallell{source = #neo_stream{type = filter}} = State) ->
    filter_next_parallell(State);
next(#neo_stream_parallell{source = #neo_stream{type = filtermap}} = State) ->
    filtermap_next_parallell(State);
next(#neo_stream_parallell{source = #neo_stream{type = foreach}} = State) ->
    foreach_next_parallell(State);
next({Next, InternalState0}) when is_function(Next, 1) ->
    case Next(InternalState0) of
        {Key, Value, InternalState1} ->
            {Key, Value, {Next, InternalState1}};
        none ->
            none
    end;
next(Iterator) when is_atom(element(1, Iterator)) ->
    Module = element(1, Iterator),
    ?assertImplementsBehaviour(Module),
    Module:next(Iterator).

%% @doc Returns the next `Key'-`Value' pair from the given
%% {@link iterator(). iterator}. If the iterator is exhausted, `none' is
%% returned.
%%
%% The `limit' option enables parallell execution of the iterator, if
%% supported by the iterator. It will keep at most `limit' processes
%% in-flight at any given time. If given as `1' (the default), the iterator
%% is executed sequentially.
%%
%% Only in the latter case is the order guaranteed to be the same as the
%% underlying iterator.
%%
%% Most iterators from this module supports parallell execution.
-spec next(t(Key, Value), options()) -> {Key, Value, t(Key, Value)} | none.
next(#neo_stream{type = Type} = Stream, Options) ->
    case neo_collection:get(Options, limit, 1) of
        1 ->
            next(Stream);
        Limit when ?is_pos_integer(Limit) ->
            State = #neo_stream_parallell{
                source = Stream,
                limit = Limit
            },
            case Type of
                map -> map_next_parallell(State);
                filter -> filter_next_parallell(State);
                filtermap -> filtermap_next_parallell(State);
                foreach -> foreach_next_parallell(State)
            end
    end;
next(Iterator, Options) when is_atom(element(1, Iterator)) ->
    Module = element(1, Iterator),
    case neo_reflect:is_exported(Module, next, 2) of
        true ->
            ?assertImplementsBehaviour(Module),
            Module:next(Iterator, Options);
        false ->
            next(Iterator)
    end.

%% keys(Iterator) ->
%%     map(Iterator, fun(Key, _Value) -> Key end).

%% values(Iterator) ->
%%     map(Iterator, fun(Value) -> Value end).

%% @doc Returns a new {@link t(). iterator} that emits the elements of each
%% iterator in `IteratorOfIterators'.
concat(IteratorOfIterators) ->
    {fun concat_next/1, {none, IteratorOfIterators}}.

%% @private
-spec concat_next({Iterator, IteratorOfIterators}) ->
    {Key, Value, {Iterator, IteratorOfIterators}} | none
when
    IteratorOfIterators :: t(_, Iterator) | none,
    Iterator :: t(Key, Value) | none,
    Key :: term(),
    Value :: term().
concat_next({none, none}) ->
    none;
concat_next({none, Tail0}) ->
    case next(Tail0) of
        {_Key, Head, Tail1} ->
            concat_next({Head, Tail1});
        none ->
            none
    end;
concat_next({Head0, Tail}) ->
    case next(Head0) of
        {Key, Value, Head1} ->
            {Key, Value, {Head1, Tail}};
        none ->
            concat_next({none, Tail})
    end.

%% @equiv fold(Iterator, Accumulator, Folder, [])
-spec fold(
    t(KeyIn, ValueIn), Accumulator, folder(Accumulator, KeyIn, ValueIn)
) -> Accumulator when
    Accumulator :: term(),
    KeyIn :: term(),
    ValueIn :: term().
fold(none, Accumulator, Folder) when is_function(Folder, 3) ->
    Accumulator;
fold(Iterator0, Accumulator, Folder) when
    is_tuple(Iterator0) andalso is_function(Folder, 3)
->
    case next(Iterator0) of
        {Key, Value, Iterator1} when is_tuple(Iterator1) ->
            fold(Iterator1, Folder(Accumulator, Key, Value), Folder);
        none ->
            Accumulator
    end;
fold(Iterator0, Accumulator, Folder) when
    is_tuple(Iterator0) andalso is_function(Folder, 2)
->
    case next(Iterator0) of
        {_Key, Value, Iterator1} when is_tuple(Iterator1) ->
            fold(Iterator1, Folder(Accumulator, Value), Folder);
        none ->
            Accumulator
    end.

%% @doc Returns the result of folding the given function over the elements of
%% the given {@link t(). iterator}.
%%
%% `Folder's with arity 2 are called with the accumulator and value.
%% `Folder's with arity 3 are called with the accumulator, key and value.
%%
%% Use `Options' to control the parallelism of the iterator.
%%
%% @see next/2
-spec fold(
    t(KeyIn, ValueIn),
    Accumulator,
    folder(Accumulator, KeyIn, ValueIn),
    options()
) -> Accumulator when
    Accumulator :: term(),
    KeyIn :: term(),
    ValueIn :: term().
fold(none, Accumulator, Folder, _Options) when is_function(Folder, 3) ->
    Accumulator;
fold(Iterator0, Accumulator, Folder, Options) when
    is_tuple(Iterator0) andalso is_function(Folder, 3)
->
    case next(Iterator0, Options) of
        {Key, Value, Iterator1} when is_tuple(Iterator1) ->
            fold(Iterator1, Folder(Accumulator, Key, Value), Folder, Options);
        none ->
            Accumulator
    end;
fold(Iterator0, Accumulator, Folder, Options) when
    is_tuple(Iterator0) andalso is_function(Folder, 2)
->
    case next(Iterator0, Options) of
        {_Key, Value, Iterator1} when is_tuple(Iterator1) ->
            fold(Iterator1, Folder(Accumulator, Value), Folder, Options);
        none ->
            Accumulator
    end.

%% @doc Returns a new {@link t(). iterator} with the results of applying
%% `Mapper' to each element of `Iterator'.
%%
%% `Mapper's with arity 1 are called with the value.
%% `Mapper's with arity 2 are called with the key and value.
%%
%% The results are returned with the same ordering guarantee, or not, as the
%% underlying iterator.
-spec map(t(KeyIn, ValueOut), mapper(KeyIn, ValueIn, KeyOut, ValueOut)) ->
    t(KeyOut, ValueOut)
when
    KeyIn :: term(),
    ValueIn :: term(),
    KeyOut :: term(),
    ValueOut :: term().
map(none, Mapper) when ?is_callback(Mapper) ->
    #neo_stream{type = map, function = Mapper, source = none};
map(#neo_stream{type = map, function = InnerMapper} = Stream, Mapper) when
    ?is_callback(Mapper)
->
    if
        is_function(InnerMapper, 2) andalso is_function(Mapper, 2) ->
            Stream#neo_stream{
                function = fun(KeyIn, ValueIn) ->
                    {KeyOut, ValueOut} = InnerMapper(KeyIn, ValueIn),
                    Mapper(KeyOut, ValueOut)
                end
            };
        is_function(InnerMapper, 2) andalso is_function(Mapper, 1) ->
            Stream#neo_stream{
                function = fun(KeyIn, ValueIn) ->
                    {KeyOut, ValueOut} = InnerMapper(KeyIn, ValueIn),
                    {KeyOut, Mapper(ValueOut)}
                end
            };
        is_function(InnerMapper, 1) andalso is_function(Mapper, 2) ->
            Stream#neo_stream{
                function = fun(KeyIn, ValueIn) ->
                    Mapper(KeyIn, InnerMapper(ValueIn))
                end
            };
        is_function(InnerMapper, 1) andalso is_function(Mapper, 1) ->
            Stream#neo_stream{
                function = fun(ValueIn) ->
                    Mapper(InnerMapper(ValueIn))
                end
            }
    end;
map(#neo_stream{type = filter, function = Filter} = Stream, Mapper) when
    ?is_callback(Mapper)
->
    if
        is_function(Filter, 2) andalso is_function(Mapper, 2) ->
            Stream#neo_stream{
                type = filtermap,
                function = fun(KeyIn, ValueIn) ->
                    case Filter(KeyIn, ValueIn) of
                        true ->
                            {KeyOut, ValueOut} = Mapper(KeyIn, ValueIn),
                            {true, KeyOut, ValueOut};
                        false ->
                            false
                    end
                end
            };
        is_function(Filter, 2) andalso is_function(Mapper, 1) ->
            Stream#neo_stream{
                type = filtermap,
                function = fun(KeyIn, ValueIn) ->
                    Filter(KeyIn, ValueIn) andalso {true, Mapper(ValueIn)}
                end
            };
        is_function(Filter, 1) andalso is_function(Mapper, 2) ->
            Stream#neo_stream{
                type = filtermap,
                function = fun(KeyIn, ValueIn) ->
                    case Filter(ValueIn) of
                        true ->
                            {KeyOut, ValueOut} = Mapper(KeyIn, ValueIn),
                            {true, KeyOut, ValueOut};
                        false ->
                            false
                    end
                end
            };
        is_function(Filter, 1) andalso is_function(Mapper, 1) ->
            Stream#neo_stream{
                type = filtermap,
                function = fun(ValueIn) ->
                    Filter(ValueIn) andalso {true, Mapper(ValueIn)}
                end
            }
    end;
map(#neo_stream{type = filtermap, function = FilterMapper} = Stream, Mapper) when
    ?is_callback(Mapper)
->
    if
        is_function(FilterMapper, 2) andalso is_function(Mapper, 2) ->
            Stream#neo_stream{
                function = fun(KeyIn, ValueIn) ->
                    case FilterMapper(KeyIn, ValueIn) of
                        {true, ValueOut} ->
                            erlang:insert_element(1, Mapper(KeyIn, ValueOut), true);
                        {true, KeyOut, ValueOut} ->
                            erlang:insert_element(1, Mapper(KeyOut, ValueOut), true);
                        true ->
                            erlang:insert_element(1, Mapper(KeyIn, ValueIn), true);
                        false ->
                            false
                    end
                end
            };
        is_function(FilterMapper, 2) andalso is_function(Mapper, 1) ->
            Stream#neo_stream{
                function = fun(KeyIn, ValueIn) ->
                    case FilterMapper(KeyIn, ValueIn) of
                        {true, ValueOut} ->
                            {true, Mapper(ValueOut)};
                        {true, KeyOut, ValueOut} ->
                            {true, KeyOut, Mapper(ValueOut)};
                        true ->
                            {true, Mapper(ValueIn)};
                        false ->
                            false
                    end
                end
            };
        is_function(FilterMapper, 1) andalso is_function(Mapper, 2) ->
            Stream#neo_stream{
                function = fun(KeyIn, ValueIn) ->
                    case FilterMapper(ValueIn) of
                        {true, ValueOut} ->
                            erlang:insert_element(1, Mapper(KeyIn, ValueOut), true);
                        true ->
                            erlang:insert_element(1, Mapper(KeyIn, ValueIn), true);
                        false ->
                            false
                    end
                end
            };
        is_function(FilterMapper, 1) andalso is_function(Mapper, 1) ->
            Stream#neo_stream{
                function = fun(ValueIn) ->
                    case FilterMapper(ValueIn) of
                        {true, ValueOut} ->
                            {true, Mapper(ValueOut)};
                        true ->
                            {true, Mapper(ValueIn)};
                        false ->
                            false
                    end
                end
            }
    end;
map(Iterator, Mapper) when ?is_callback(Mapper) ->
    #neo_stream{
        type = map,
        source = Iterator,
        function = Mapper
    }.

%% @private
-spec map_next(Stream) -> {KeyOut, ValueOut, Stream} | none when
    Stream :: neo_stream(KeyIn, ValueIn, KeyOut, ValueOut),
    KeyIn :: term(),
    ValueIn :: term(),
    KeyOut :: term(),
    ValueOut :: term().
map_next(#neo_stream{type = map, source = none}) ->
    none;
map_next(#neo_stream{type = map, source = Iterator0, function = Mapper} = Stream) when
    is_function(Mapper, 2)
->
    case next(Iterator0) of
        {KeyIn, ValueIn, Iterator1} ->
            {KeyOut, ValueOut} = Mapper(KeyIn, ValueIn),
            {KeyOut, ValueOut, Stream#neo_stream{source = Iterator1}};
        none ->
            none
    end;
map_next(#neo_stream{type = map, source = Iterator0, function = Mapper} = Stream) when
    is_function(Mapper, 1)
->
    case next(Iterator0) of
        {KeyIn, ValueIn, Iterator1} ->
            ValueOut = Mapper(ValueIn),
            {KeyIn, ValueOut, Stream#neo_stream{source = Iterator1}};
        none ->
            none
    end.

%% @private
-spec map_next_parallell(Stream) -> {KeyOut, ValueOut, Stream} | none when
    Stream :: neo_stream_parallell(KeyIn, ValueIn, KeyOut, ValueOut),
    KeyIn :: term(),
    ValueIn :: term(),
    KeyOut :: term(),
    ValueOut :: term().
map_next_parallell(#neo_stream_parallell{
    source = #neo_stream{type = map, source = none}, in_flight = 0
}) ->
    %% Done
    none;
map_next_parallell(
    #neo_stream_parallell{
        source = #neo_stream{type = map, source = none},
        ref = Ref,
        in_flight = InFlight
    } = State
) when ?is_pos_integer(InFlight) ->
    %% Draining phase
    receive
        {Ref, KeyOut, ValueOut} ->
            {KeyOut, ValueOut, State#neo_stream_parallell{in_flight = InFlight - 1}}
    end;
map_next_parallell(
    #neo_stream_parallell{
        source = #neo_stream{type = map, source = Iterator0} = Stream,
        limit = Limit,
        in_flight = InFlight
    } = State0
) when ?is_non_neg_integer(Limit) ->
    %% Spawning phase
    State1 =
        case next(Iterator0) of
            {KeyIn, ValueIn, Iterator1} ->
                spawn_worker(State0, fun map_worker/5, KeyIn, ValueIn),
                State0#neo_stream_parallell{
                    source = Stream#neo_stream{source = Iterator1},
                    limit = Limit - 1,
                    in_flight = InFlight + 1
                };
            none ->
                State0#neo_stream_parallell{
                    source = Stream#neo_stream{source = none},
                    limit = Limit - 1
                }
        end,
    map_next_parallell(State1);
map_next_parallell(
    #neo_stream_parallell{
        source = #neo_stream{type = map, source = Iterator0} = Stream,
        ref = Ref,
        limit = 0,
        in_flight = InFlight
    } = State
) ->
    %% Processing (drain one, spawn one) phase
    receive
        {Ref, KeyOut, ValueOut} ->
            case next(Iterator0) of
                {KeyIn, ValueIn, Iterator1} ->
                    spawn_worker(State, fun map_worker/5, KeyIn, ValueIn),
                    {KeyOut, ValueOut, State#neo_stream_parallell{
                        source = Stream#neo_stream{source = Iterator1}
                    }};
                none ->
                    {KeyOut, ValueOut, State#neo_stream_parallell{
                        source = Stream#neo_stream{source = none},
                        in_flight = InFlight - 1
                    }}
            end
    end.

%% @private
map_worker(Ref, Caller, Mapper, KeyIn, ValueIn) when is_function(Mapper, 2) ->
    {KeyOut, ValueOut} = Mapper(KeyIn, ValueIn),
    Caller ! {Ref, KeyOut, ValueOut};
map_worker(Ref, Caller, Mapper, Key, ValueIn) when is_function(Mapper, 1) ->
    Caller ! {Ref, Key, Mapper(ValueIn)}.

%% @doc Returns a new {@link t(). iterator} by mapping the given `Mapper' over
%% the given `Iterator', then {@link concat/1. concatenating} the results.
%%
%% @see map/2
%% @see concat/1
-spec flatmap(t(KeyIn, ValueIn), mapper(KeyIn, ValueIn, _, t(KeyOut, ValueOut))) ->
    t(KeyOut, ValueOut).
flatmap(Iterator, Mapper) when ?is_callback(Mapper) ->
    concat(map(Iterator, Mapper)).

filter(#neo_stream{type = filter, function = InnerFilter} = Stream, Filter) when
    ?is_callback(Filter)
->
    if
        is_function(InnerFilter, 2) andalso is_function(Filter, 2) ->
            Stream#neo_stream{
                function = fun(KeyIn, ValueIn) ->
                    InnerFilter(KeyIn, ValueIn) andalso Filter(KeyIn, ValueIn)
                end
            };
        is_function(InnerFilter, 2) andalso is_function(Filter, 1) ->
            Stream#neo_stream{
                function = fun(KeyIn, ValueIn) ->
                    InnerFilter(KeyIn, ValueIn) andalso Filter(ValueIn)
                end
            };
        is_function(InnerFilter, 1) andalso is_function(Filter, 2) ->
            Stream#neo_stream{
                function = fun(KeyIn, ValueIn) ->
                    InnerFilter(ValueIn) andalso Filter(KeyIn, ValueIn)
                end
            };
        is_function(InnerFilter, 1) andalso is_function(Filter, 1) ->
            Stream#neo_stream{
                function = fun(ValueIn) ->
                    InnerFilter(ValueIn) andalso Filter(ValueIn)
                end
            }
    end;
filter(#neo_stream{type = map, function = Mapper} = Stream, Filter) when
    ?is_callback(Filter)
->
    if
        is_function(Mapper, 2) andalso is_function(Filter, 2) ->
            Stream#neo_stream{
                type = filtermap,
                function = fun(KeyIn, ValueIn) ->
                    {KeyOut, ValueOut} = Mapper(KeyIn, ValueIn),
                    case Filter(KeyOut, ValueOut) of
                        true ->
                            {true, KeyOut, ValueOut};
                        false ->
                            false
                    end
                end
            };
        is_function(Mapper, 2) andalso is_function(Filter, 1) ->
            Stream#neo_stream{
                type = filtermap,
                function = fun(KeyIn, ValueIn) ->
                    {KeyOut, ValueOut} = Mapper(KeyIn, ValueIn),
                    case Filter(ValueOut) of
                        true ->
                            {true, KeyOut, ValueOut};
                        false ->
                            false
                    end
                end
            };
        is_function(Mapper, 1) andalso is_function(Filter, 2) ->
            Stream#neo_stream{
                type = filtermap,
                function = fun(KeyIn, ValueIn) ->
                    ValueOut = Mapper(ValueIn),
                    case Filter(KeyIn, ValueOut) of
                        true ->
                            {true, KeyIn, ValueOut};
                        false ->
                            false
                    end
                end
            };
        is_function(Mapper, 1) andalso is_function(Filter, 1) ->
            Stream#neo_stream{
                type = filtermap,
                function = fun(ValueIn) ->
                    ValueOut = Mapper(ValueIn),
                    case Filter(ValueOut) of
                        true ->
                            {true, ValueOut};
                        false ->
                            false
                    end
                end
            }
    end;
filter(#neo_stream{type = filtermap, function = FilterMapper} = Stream, Filter) when
    ?is_callback(Filter)
->
    if
        is_function(FilterMapper, 2) andalso is_function(Filter, 2) ->
            Stream#neo_stream{
                function = fun(KeyIn, ValueIn) ->
                    case FilterMapper(KeyIn, ValueIn) of
                        {true, ValueOut} ->
                            case Filter(KeyIn, ValueOut) of
                                true ->
                                    {true, KeyIn, ValueOut};
                                false ->
                                    false
                            end;
                        {true, KeyOut, ValueOut} ->
                            case Filter(KeyOut, ValueOut) of
                                true ->
                                    {true, KeyOut, ValueOut};
                                false ->
                                    false
                            end;
                        true ->
                            Filter(KeyIn, ValueIn);
                        false ->
                            false
                    end
                end
            };
        is_function(FilterMapper, 2) andalso is_function(Filter, 1) ->
            Stream#neo_stream{
                function = fun(KeyIn, ValueIn) ->
                    case FilterMapper(KeyIn, ValueIn) of
                        {true, ValueOut} ->
                            case Filter(ValueOut) of
                                true ->
                                    {true, KeyIn, ValueOut};
                                false ->
                                    false
                            end;
                        {true, KeyOut, ValueOut} ->
                            case Filter(ValueOut) of
                                true ->
                                    {true, KeyOut, ValueOut};
                                false ->
                                    false
                            end;
                        true ->
                            Filter(ValueIn);
                        false ->
                            false
                    end
                end
            };
        is_function(FilterMapper, 1) andalso is_function(Filter, 2) ->
            Stream#neo_stream{
                function = fun(KeyIn, ValueIn) ->
                    case FilterMapper(ValueIn) of
                        {true, ValueOut} ->
                            case Filter(KeyIn, ValueOut) of
                                true ->
                                    {true, KeyIn, ValueOut};
                                false ->
                                    false
                            end;
                        true ->
                            Filter(KeyIn, ValueIn);
                        false ->
                            false
                    end
                end
            };
        is_function(FilterMapper, 1) andalso is_function(Filter, 1) ->
            Stream#neo_stream{
                function = fun(ValueIn) ->
                    case FilterMapper(ValueIn) of
                        {true, ValueOut} ->
                            case Filter(ValueOut) of
                                true ->
                                    {true, ValueOut};
                                false ->
                                    false
                            end;
                        true ->
                            Filter(ValueIn);
                        false ->
                            false
                    end
                end
            }
    end;
filter(Iterator, Filter) when ?is_callback(Filter) ->
    #neo_stream{type = filter, source = Iterator, function = Filter}.

%% @private
-spec filter_next(Stream) -> {Key, Value, Stream} | none when
    Stream :: neo_stream(Key, Value, Key, Value),
    Key :: term(),
    Value :: term().
filter_next(#neo_stream{type = filter, source = none}) ->
    none;
filter_next(
    #neo_stream{type = filter, source = Iterator0, function = Filter} =
        Stream
) when ?is_callback(Filter) ->
    case next(Iterator0) of
        {Key, Value, Iterator1} ->
            case ?call_callback(Filter, Key, Value) of
                true ->
                    {Key, Value, Stream#neo_stream{source = Iterator1}};
                false ->
                    filter_next(Stream#neo_stream{source = Iterator1})
            end;
        none ->
            none
    end.

%% @private
%% The return value of the `filter' function is a subset of the return value of
%% a `filtermap' function, so we can use the latters implementation.
%%
%% When assertions are enabled we wrap the `filter' function to ensure it is not
%% a `filtermap' function in disguise, i.e. verify that the return value is a
%% boolean.
-spec filter_next_parallell(Stream) -> {Key, Value, Stream} | none when
    Stream :: neo_stream_parallell(Key, Value, Key, Value),
    Key :: term(),
    Value :: term().
-ifdef(NOASSERT).
filter_next_parallell(
    #neo_stream_parallell{source = #neo_stream{type = filter} = Source} = Stream
) ->
    filtermap_next_parallell(Stream#neo_stream_parallell{
        source = Source#neo_stream{type = filtermap}
    }).
-else.
filter_next_parallell(
    #neo_stream_parallell{
        source = #neo_stream{type = filter, function = Filter} = Source
    } = Stream
) when is_function(Filter, 2) ->
    filtermap_next_parallell(Stream#neo_stream_parallell{
        source = Source#neo_stream{
            type = filtermap,
            function = fun(KeyIn, ValueIn) ->
                Result = Filter(KeyIn, ValueIn),
                ?assertMatch(_ when is_boolean(Result), Result),
                Result
            end
        }
    });
filter_next_parallell(
    #neo_stream_parallell{
        source = #neo_stream{type = filter, function = Filter} = Source
    } = Stream
) when is_function(Filter, 1) ->
    filtermap_next_parallell(Stream#neo_stream_parallell{
        source = Source#neo_stream{
            type = filtermap,
            function = fun(ValueIn) ->
                Result = Filter(ValueIn),
                ?assertMatch(_ when is_boolean(Result), Result),
                Result
            end
        }
    }).
-endif.

filtermap(#neo_stream{type = filter, function = Filter} = Stream, FilterMapper) when
    ?is_callback(FilterMapper)
->
    if
        is_function(Filter, 2) andalso is_function(FilterMapper, 2) ->
            Stream#neo_stream{
                type = filtermap,
                function = fun(KeyIn, ValueIn) ->
                    Filter(KeyIn, ValueIn) andalso FilterMapper(KeyIn, ValueIn)
                end
            };
        is_function(Filter, 2) andalso is_function(FilterMapper, 1) ->
            Stream#neo_stream{
                type = filtermap,
                function = fun(KeyIn, ValueIn) ->
                    Filter(KeyIn, ValueIn) andalso FilterMapper(ValueIn)
                end
            };
        is_function(Filter, 1) andalso is_function(FilterMapper, 2) ->
            Stream#neo_stream{
                type = filtermap,
                function = fun(KeyIn, ValueIn) ->
                    Filter(ValueIn) andalso FilterMapper(KeyIn, ValueIn)
                end
            };
        is_function(Filter, 1) andalso is_function(FilterMapper, 1) ->
            Stream#neo_stream{
                type = filtermap,
                function = fun(ValueIn) ->
                    Filter(ValueIn) andalso FilterMapper(ValueIn)
                end
            }
    end;
filtermap(#neo_stream{type = map, function = Mapper} = Stream, FilterMapper) when
    ?is_callback(FilterMapper)
->
    if
        is_function(Mapper, 2) andalso is_function(FilterMapper, 2) ->
            Stream#neo_stream{
                type = filtermap,
                function = fun(KeyIn, ValueIn) ->
                    {KeyOut, ValueOut} = Mapper(KeyIn, ValueIn),
                    FilterMapper(KeyOut, ValueOut)
                end
            };
        is_function(Mapper, 2) andalso is_function(FilterMapper, 1) ->
            Stream#neo_stream{
                type = filtermap,
                function = fun(KeyIn, ValueIn) ->
                    {KeyOut, ValueOut} = Mapper(KeyIn, ValueIn),
                    case FilterMapper(ValueOut) of
                        {true, FinalValue} ->
                            {true, KeyOut, FinalValue};
                        true ->
                            {true, KeyOut, ValueOut};
                        false ->
                            false
                    end
                end
            };
        is_function(Mapper, 1) andalso is_function(FilterMapper, 2) ->
            Stream#neo_stream{
                type = filtermap,
                function = fun(KeyIn, ValueIn) ->
                    FilterMapper(KeyIn, Mapper(ValueIn))
                end
            };
        is_function(Mapper, 1) andalso is_function(FilterMapper, 1) ->
            Stream#neo_stream{
                type = filtermap,
                function = fun(ValueIn) ->
                    FilterMapper(Mapper(ValueIn))
                end
            }
    end;
filtermap(
    #neo_stream{type = filtermap, function = InnerFilterMapper} = Stream, FilterMapper
) when
    ?is_callback(FilterMapper)
->
    if
        is_function(InnerFilterMapper, 2) andalso is_function(FilterMapper, 2) ->
            Stream#neo_stream{
                type = filtermap,
                function = fun(KeyIn, ValueIn) ->
                    case InnerFilterMapper(KeyIn, ValueIn) of
                        {true, ValueOut} ->
                            FilterMapper(KeyIn, ValueOut);
                        {true, KeyOut, ValueOut} ->
                            FilterMapper(KeyOut, ValueOut);
                        true ->
                            FilterMapper(KeyIn, ValueIn);
                        false ->
                            false
                    end
                end
            };
        is_function(InnerFilterMapper, 2) andalso is_function(FilterMapper, 1) ->
            Stream#neo_stream{
                type = filtermap,
                function = fun(KeyIn, ValueIn) ->
                    case InnerFilterMapper(KeyIn, ValueIn) of
                        {true, ValueOut} ->
                            FilterMapper(ValueOut);
                        {true, KeyOut, ValueOut} ->
                            case FilterMapper(ValueOut) of
                                {true, FinalValue} ->
                                    {true, KeyOut, FinalValue};
                                true ->
                                    {true, KeyOut, ValueOut};
                                false ->
                                    false
                            end;
                        true ->
                            FilterMapper(ValueIn);
                        false ->
                            false
                    end
                end
            };
        is_function(InnerFilterMapper, 1) andalso is_function(FilterMapper, 2) ->
            Stream#neo_stream{
                type = filtermap,
                function = fun(KeyIn, ValueIn) ->
                    case InnerFilterMapper(ValueIn) of
                        {true, ValueOut} ->
                            FilterMapper(KeyIn, ValueOut);
                        true ->
                            FilterMapper(KeyIn, ValueIn);
                        false ->
                            false
                    end
                end
            };
        is_function(InnerFilterMapper, 1) andalso is_function(FilterMapper, 1) ->
            Stream#neo_stream{
                type = filtermap,
                function = fun(ValueIn) ->
                    case InnerFilterMapper(ValueIn) of
                        {true, ValueOut} ->
                            FilterMapper(ValueOut);
                        true ->
                            FilterMapper(ValueIn);
                        false ->
                            false
                    end
                end
            }
    end;
filtermap(Iterator, FilterMapper) when ?is_callback(FilterMapper) ->
    #neo_stream{type = filtermap, source = Iterator, function = FilterMapper}.

%% @private
-spec filtermap_next_parallell(Stream) -> {KeyOut, ValueOut, Stream} | none when
    Stream :: neo_stream_parallell(KeyIn, ValueIn, KeyOut, ValueOut),
    KeyIn :: term(),
    ValueIn :: term(),
    KeyOut :: term(),
    ValueOut :: term().
filtermap_next_parallell(#neo_stream_parallell{
    source = #neo_stream{type = filtermap, source = none}, in_flight = 0
}) ->
    %% Done
    none;
filtermap_next_parallell(
    #neo_stream_parallell{
        source = #neo_stream{type = filtermap, source = none},
        ref = Ref,
        in_flight = InFlight
    } = State
) when ?is_non_neg_integer(InFlight) ->
    %% Draining phase
    receive
        {Ref, KeyOut, ValueOut} ->
            {KeyOut, ValueOut, State#neo_stream_parallell{
                in_flight = InFlight - 1
            }};
        Ref ->
            filtermap_next_parallell(State#neo_stream_parallell{
                in_flight = InFlight - 1
            })
    end;
filtermap_next_parallell(
    #neo_stream_parallell{
        source = #neo_stream{type = filtermap, source = Iterator0} = Stream,
        limit = Limit,
        in_flight = InFlight
    } = State0
) when ?is_non_neg_integer(Limit) ->
    %% Spawning phase
    State1 =
        case next(Iterator0) of
            {KeyIn, ValueIn, Iterator1} ->
                spawn_worker(State0, fun filtermap_worker/5, KeyIn, ValueIn),
                State0#neo_stream_parallell{
                    source = Stream#neo_stream{source = Iterator1},
                    limit = Limit - 1,
                    in_flight = InFlight + 1
                };
            none ->
                State0#neo_stream_parallell{
                    source = Stream#neo_stream{source = none},
                    limit = Limit - 1
                }
        end,
    filtermap_next_parallell(State1);
filtermap_next_parallell(
    #neo_stream_parallell{
        source = #neo_stream{type = filtermap, source = Iterator0} = Stream,
        ref = Ref,
        limit = 0,
        in_flight = InFlight
    } = State
) ->
    %% Processing (drain one, spawn one) phase
    receive
        {Ref, KeyOut, ValueOut} ->
            case next(Iterator0) of
                {KeyIn, ValueIn, Iterator1} ->
                    spawn_worker(State, fun filtermap_worker/5, KeyIn, ValueIn),
                    {KeyOut, ValueOut, State#neo_stream_parallell{
                        source = Stream#neo_stream{source = Iterator1}
                    }};
                none ->
                    {KeyOut, ValueOut, State#neo_stream_parallell{
                        source = Stream#neo_stream{source = none},
                        in_flight = InFlight - 1
                    }}
            end;
        Ref ->
            case next(Iterator0) of
                {KeyIn, ValueIn, Iterator1} ->
                    spawn_worker(State, fun filtermap_worker/5, KeyIn, ValueIn),
                    filtermap_next_parallell(State#neo_stream_parallell{
                        source = Stream#neo_stream{source = Iterator1}
                    });
                none ->
                    filtermap_next_parallell(State#neo_stream_parallell{
                        source = Stream#neo_stream{source = none},
                        in_flight = InFlight - 1
                    })
            end
    end.

%% @private
filtermap_worker(Ref, Caller, FilterMapper, KeyIn, ValueIn) when
    is_function(FilterMapper, 2)
->
    case FilterMapper(KeyIn, ValueIn) of
        {true, ValueOut} ->
            Caller ! {Ref, KeyIn, ValueOut};
        {true, KeyOut, ValueOut} ->
            Caller ! {Ref, KeyOut, ValueOut};
        true ->
            Caller ! {Ref, KeyIn, ValueIn};
        false ->
            Caller ! Ref
    end;
filtermap_worker(Ref, Caller, FilterMapper, KeyIn, ValueIn) when
    is_function(FilterMapper, 1)
->
    case FilterMapper(ValueIn) of
        {true, ValueOut} ->
            Caller ! {Ref, KeyIn, ValueOut};
        true ->
            Caller ! {Ref, KeyIn, ValueIn};
        false ->
            Caller ! Ref
    end.

%% @private
-spec filtermap_next(Stream) -> {KeyOut, ValueOut, Stream} | none when
    Stream :: neo_stream(KeyIn, ValueIn, KeyOut, ValueOut),
    KeyIn :: term(),
    ValueIn :: term(),
    KeyOut :: term(),
    ValueOut :: term().
filtermap_next(#neo_stream{type = filtermap, source = none}) ->
    none;
filtermap_next(
    #neo_stream{type = filtermap, source = Iterator0, function = FilterMapper} = Stream
) ->
    case next(Iterator0) of
        {KeyIn, ValueIn, Iterator1} ->
            case ?call_callback(FilterMapper, KeyIn, ValueIn) of
                {true, ValueOut} ->
                    {KeyIn, ValueOut, Stream#neo_stream{source = Iterator1}};
                {true, KeyOut, ValueOut} ->
                    {KeyOut, ValueOut, Stream#neo_stream{source = Iterator1}};
                true ->
                    {KeyIn, ValueIn, Stream#neo_stream{source = Iterator1}};
                false ->
                    filtermap_next(Stream#neo_stream{source = Iterator1})
            end;
        none ->
            none
    end.

%% @doc Returns a new {@link t(). iterator} that calls the given `Callback' with
%% element of the given `Iterator'.
-spec foreach(Iterator, Callback) -> t(Key, Value) when
    Iterator :: iterator(),
    Callback :: foreach_fun(Key, Value).
foreach(Iterator, Callback) when ?is_callback(Callback) ->
    #neo_stream{
        type = foreach,
        source = Iterator,
        function = Callback
    }.

%% @private
-spec foreach_next(Stream) -> {'_', ok, Stream} | none when
    Stream :: neo_stream(Key, Value, '_', ok),
    Key :: term(),
    Value :: term().
foreach_next(#neo_stream{type = foreach, source = none}) ->
    none;
foreach_next(
    #neo_stream{type = foreach, source = Iterator0, function = Callback} = Stream
) ->
    case next(Iterator0) of
        {Key, Value, Iterator1} ->
            ?call_callback(Callback, Key, Value),
            {'_', ok, Stream#neo_stream{source = Iterator1}};
        none ->
            none
    end.

%% @private
foreach_next_parallell(#neo_stream_parallell{
    source = #neo_stream{type = foreach, source = none}, in_flight = 0
}) ->
    %% Done
    none;
foreach_next_parallell(
    #neo_stream_parallell{
        source = #neo_stream{type = foreach, source = none},
        ref = Ref,
        in_flight = InFlight
    } = State
) when ?is_non_neg_integer(InFlight) ->
    %% Draining phase
    receive
        Ref ->
            {'_', ok, State#neo_stream_parallell{in_flight = InFlight - 1}}
    end;
foreach_next_parallell(
    #neo_stream_parallell{
        source = #neo_stream{type = foreach, source = Iterator0} = Stream,
        limit = Limit,
        in_flight = InFlight
    } = State0
) when ?is_non_neg_integer(Limit) ->
    %% Spawning phase
    State1 =
        case next(Iterator0) of
            {Key, Value, Iterator} ->
                spawn_worker(State0, fun foreach_worker/5, Key, Value),
                State0#neo_stream_parallell{
                    source = Stream#neo_stream{source = Iterator},
                    limit = Limit - 1,
                    in_flight = InFlight + 1
                };
            none ->
                State0#neo_stream_parallell{
                    source = Stream#neo_stream{source = none},
                    limit = Limit - 1
                }
        end,
    foreach_next_parallell(State1);
foreach_next_parallell(
    #neo_stream_parallell{
        source = #neo_stream{type = foreach, source = Iterator0} = Stream,
        ref = Ref,
        limit = 0,
        in_flight = InFlight
    } = State
) ->
    %% Processing (drain one, spawn one) phase
    receive
        Ref ->
            case next(Iterator0) of
                {Key, Value, Iterator1} ->
                    spawn_worker(State, fun foreach_worker/5, Key, Value),
                    {'_', ok, State#neo_stream_parallell{
                        source = Stream#neo_stream{source = Iterator1}
                    }};
                none ->
                    {'_', ok, State#neo_stream_parallell{
                        source = Stream#neo_stream{source = none},
                        in_flight = InFlight - 1
                    }}
            end
    end.

%% @private
foreach_worker(Ref, Caller, Callback, Key, Value) ->
    ?call_callback(Callback, Key, Value),
    Caller ! Ref.

%% @doc Special variant of `neo_collection:set/3' that handles too short lists or tuples.
%%
%% The given `Default' value is used to fill the gaps in the list or tuple.
-spec set(neo_collection:t(Key, Value), Key, Value, Default :: term()) ->
    neo_collection:t(Key, Value).
set(List, Index, Value, Default) when
    is_list(List) andalso is_integer(Index) andalso length(List) < Index
->
    Padding = lists:duplicate(Index - length(List) - 1, Default),
    List ++ Padding ++ [Value];
set(Tuple, Index, Value, Default) when
    is_tuple(Tuple) andalso is_integer(Index) andalso tuple_size(Tuple) < Index
->
    case neo_reflect:implementation_for(Tuple, [neo_collection]) of
        neo_tuples -> list_to_tuple(set(tuple_to_list(Tuple), Index, Value, Default));
        _ -> neo_collection:set(Tuple, Index, Value)
    end;
set(Collection, Key, Value, _Default) ->
    neo_collection:set(Collection, Key, Value).

%%%_* Private ----------------------------------------------------------------
-spec implementation_for(neo_collection:t()) -> boolean().
implementation_for(Collection) ->
    neo_reflect:implementation_for(Collection, [?MODULE, neo_collection]).

-spec spawn_worker(Stream, Worker, Key, Value) -> pid() when
    Stream :: #neo_stream_parallell{},
    Ref :: reference(),
    Caller :: pid(),
    Callback :: function(),
    Worker :: fun((Ref, Caller, Callback, Key, Value) -> any()).
spawn_worker(
    #neo_stream_parallell{
        ref = Ref, caller = Caller, source = #neo_stream{function = Callback}
    },
    Worker,
    Key,
    Value
) when is_function(Worker, 5) ->
    spawn_link(erlang, apply, [Worker, [Ref, Caller, Callback, Key, Value]]).

%%%_* Tests ==================================================================
-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").

-endif.
