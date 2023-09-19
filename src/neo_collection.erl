%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% @doc A behaviour for container data types.
%%% @end
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%%%_* Module declaration =====================================================
-module(neo_collection).

%%%_* Behaviours =============================================================
-behaviour(neo_stream).

%%%_* Exports ================================================================
%%%_ * Callbacks -------------------------------------------------------------
-export([
    iterator/1,
    next/1
]).

%%%_ * API -------------------------------------------------------------------
-export([
    delete/2,
    fetch/2,
    get/2,
    get/3,
    has/2,
    keys/1,
    merge/2,
    merge_with/3,
    new/1,
    set/3,
    size/1,
    to/2,
    values/1
]).

%%%_* Types ------------------------------------------------------------------
-export_type([
    combiner/4,
    t/0,
    t/2,
    type/0
]).

%%%_* Callbacks ==============================================================
%% This function is called to create a new empty {@link t(). collection}.
-callback new() -> t().

%% This function is called to retrive the size of the given
%% {@link t(). collection}.
-callback size(t()) -> non_neg_integer().

%% This function is called to produce a list of the keys in the given
%% {@link t(). collection}.
-callback keys(t(Key, _Value)) -> [Key].

%% This function is called to produce a list of the values in the given
%% {@link t(). collection}.
-callback values(t(_Key, Value)) -> [Value].

%% This function is called to check if the given `Key' is in the given
%% {@link t(). collection}.
-callback has(t(Key, _Value), Key) -> boolean().

%% This function is called to get the `Value' associated with the given `Key'
%% in the given {@link t(). collection}.
%%
%% Should raise an error if the `Key' is missing.
-callback get(t(Key, Value), Key) -> Value.

%% This function is called to get the `Value' associated with the given `Key'
%% in the given {@link t(). collection}, or `{error, notfound}' if the `Key'
%% is missing.
-callback fetch(t(Key, Value), Key) -> {ok, Value} | {error, notfound}.

%% This function is called to set the given `Key' to the given `Value' in the
%% given {@link t(). collection}.
-callback set(t(Key, Value), Key, Value) -> t(Key, Value).

%% This function is called to remove the given `Key' from the given
%% {@link t(). collection}.
-callback delete(t(Key, Value), Key) -> t(Key, Value).

-callback merge(t(KeyA, ValueA), t(KeyB, ValueB)) -> t(KeyOut, ValueOut) when
    KeyOut :: KeyA | KeyB,
    ValueOut :: ValueA | ValueB.

%% This function is called to merge to {@link t(). collections} using a
%% {@link combiner()} function.
-callback merge_with(
    t(KeyA, ValueA),
    t(KeyB, ValueB),
    neo_collection:combiner(KeyIn, ValueA, ValueB, ValueOut)
) -> t(KeyOut, ValueOut) when
    %% Key is really the _intersection_ of KeyA and KeyB, but Erlang doesn't
    %% support intersection types.
    KeyIn :: KeyA | KeyB,
    KeyOut :: KeyA | KeyB.

%% @see maps:from_list/1
-callback from_list(list()) -> t().

%% @see maps:to_list/1
-callback to_list(t()) -> list().

%%%_ * Optional callbacks ----------------------------------------------------
-optional_callbacks([
    fetch/2,
    from_list/1,
    merge/2,
    merge_with/3,
    to_list/1,
    values/1
]).

%%%_* Includes ===============================================================
-include("internal.hrl").

%%%_* Macros =================================================================

%%%_* Types ==================================================================
-type t() :: t(Key :: term(), Value :: term()).
%% Represents a generic collection.

-type t(_Key, _Value) :: term().
%% Represents a collection; a mapping from `Key's to `Value's.

-type type() :: atom().
%% Represents a type of {@link t(). collection}.
%%
%% It is in singular, so `map' and not `maps'.

-type combiner(Key, ValueA, ValueB, ValueOut) ::
    fun((Key, ValueA, ValueB) -> ValueOut).
%% A combining function, just like the first parameter of
%% {@link maps:merge_with/3}.

-record(neo_collection, {
    keys :: [term()],
    collection :: neo_collection:t()
}).

%%%_* Code ===================================================================
%%%_ * API -------------------------------------------------------------------
%% @doc Returns a new empty {@link t(). collection} of the given {@link type()}.
-spec new(type() | list() | map() | tuple()) -> t().
new(lists) ->
    neo_lists:new();
new(gb_trees) ->
    neo_gb_trees:new();
new(Collection) ->
    case is_atom(Collection) andalso neo_reflect:is_exported(Collection, new, 0) of
        true ->
            Collection:new();
        false ->
            Module = implementation_for(Collection),
            Module:new()
    end.

%% @doc Returns the given {@link t(). collection} as the given type.
-spec to(Source, type() | Destination) -> Destination when
    Source :: t(Key, Value),
    Destination :: t(Key, Value).
to(Collection0, Type) ->
    InitialAccumulator = new(Type),
    case {implementation_for(InitialAccumulator), implementation_for(Collection0)} of
        {Module, Module} ->
            Collection0;
        {ToModule, _FromModule} when is_list(Collection0) ->
            Collection1 =
                case neo_lists:typeof(Collection0) of
                    orddict -> Collection0;
                    proplist -> proplists:unfold(Collection0);
                    plain -> lists:enumerate(Collection0)
                end,
            case neo_reflect:is_exported(ToModule, from_list, 1) of
                true -> ToModule:from_list(Collection1);
                false -> to(Collection1, Type, fun id/1)
            end;
        {_ToModule, FromModule} when is_list(InitialAccumulator) ->
            case neo_reflect:is_exported(FromModule, to_list, 1) of
                true ->
                    FromModule:to_list(Collection0);
                false ->
                    Iterator = neo_stream:from(Collection0),
                    neo_stream:fold(Iterator, InitialAccumulator, fun list_set/3)
            end;
        _ ->
            to(Collection0, Type, fun id/1)
    end.

%% @private
%% @doc
%% Because the order is undefined we can't use the given index or we've get
%% `badkey' when it's out of bounds. The solution is simple, just ignore
%% the index and prepend each result as they come in.
%%
%% For orddict/proplists it's much easier, just use good ol' set
list_set(List, Index, Value) when is_integer(Index) ->
    [Value | List];
list_set(List, Key, Value) ->
    neo_lists:set(List, Key, Value).

%% @private
id(Value) ->
    Value.

%% @doc Returns {@link t(). collection} of the given type with the result of
%% mapping `Mapper' over the given `Collection'.
%%
%% This allows for transforming both the representation of a collection and
%% it's elements in one go. Equivalent to
%% `neo_collection:to(neo_stream:map(Collection, Mapper), Type)'.
-spec to(
    t(KeyIn, ValueIn),
    type() | t(KeyOut, ValueOut),
    Mapper :: neo_stream:mapper(KeyIn, ValueIn, KeyOut, ValueOut)
) -> t(KeyOut, ValueOut) when
    KeyIn :: KeyOut,
    ValueIn :: ValueOut.
to(Collection, Type, Mapper) ->
    InitialAccumulator = new(Type),
    Iterator0 = neo_stream:from(Collection),
    Iterator1 = neo_stream:map(Iterator0, Mapper),
    if
        is_list(InitialAccumulator) ->
            neo_stream:fold(Iterator1, InitialAccumulator, fun list_set/3);
        true ->
            neo_stream:fold(Iterator1, InitialAccumulator, fun set/3)
    end.

%% @doc Returns the number of key-value pairs in the given
%% {@link t(). collection}.
-compile({no_auto_import, [size/1]}).
-spec size(t()) -> non_neg_integer().
size(Collection) ->
    Module = implementation_for(Collection),
    Module:size(Collection).

%% @doc Returns a list of the keys in the given {@link t(). collection}.
-spec keys(t(Key, _Value)) -> [Key].
keys(Collection) ->
    Module = implementation_for(Collection),
    Module:keys(Collection).

%% @doc Returns a list of the values in the given {@link t(). collection}.
-spec values(t(_Key, Value)) -> [Value].
values(Collection) ->
    Module = implementation_for(Collection),
    case neo_reflect:is_exported(Module, values, 1) of
        true -> Module:values(Collection);
        false -> [get(Collection, Key) || Key <- keys(Collection)]
    end.

%% @doc Returns `true' if the given {@link t(). collection} has the given
%% `Key', false otherwise
-spec has(t(Key, _Value), Key) -> boolean().
has(Collection, Key) ->
    Module = implementation_for(Collection),
    Module:has(Collection, Key).

%% @doc Returns the value associated with the given `Key' in the given
%% {@link t(). collection}.
%%
%% Fails with `{badkey, Key}' if the collection does not contain `Key'.
-spec get(t(Key, Value), Key) -> Value.
get(Collection, Key) ->
    Module = implementation_for(Collection),
    Module:get(Collection, Key).

%% @doc Returns the value associated with the given `Key' in the given
%% {@link t(). collection}, or `Default' if the collection does not contain
%% `Key'.
-spec get(t(Key, Value), Key, Default) -> Value | Default.
get(Collection, Key, Default) ->
    Module = implementation_for(Collection),
    case has(Collection, Key) of
        true -> Module:get(Collection, Key);
        false -> Default
    end.

%% @doc Returns the value associated with the given `Key' in the given
%% {@link t(). collection}, or `{error, notfound}' if the collection does not
%% contain `Key'.
-spec fetch(t(Key, Value), Key) -> {ok, Value} | {error, notfound}.
fetch(Collection, Key) ->
    Module = implementation_for(Collection),
    case neo_reflect:is_exported(Module, fetch, 2) of
        true ->
            Module:fetch(Collection, Key);
        false ->
            case has(Collection, Key) of
                true -> {ok, get(Collection, Key)};
                false -> {error, notfound}
            end
    end.

%% @doc Returns a {@link t(). collection} with the given `Key' set to the given
%% `Value'.
-spec set(t(Key, Value), Key, Value) -> t(Key, Value).
set(Collection, Key, Value) ->
    Module = implementation_for(Collection),
    Module:set(Collection, Key, Value).

%% @doc Returns a {@link t(). collection} without the given `Key'.
-spec delete(t(Key, Value), Key) -> t(Key, Value).
delete(Collection, Key) ->
    Module = implementation_for(Collection),
    Module:delete(Collection, Key).

%% @doc Returns `CollectionA' merged with `CollectionB'.
%%
%% That is, {@link set/3. set} each `Key'-`Value' pair in `ColletionB' in
%% `CollectionA'.
%%
%% @see maps:merge/2
-spec merge(t(_Key, _Value), t(_Key, _Value)) -> t(_Key, _Value).
merge(CollectionA, CollectionB) ->
    ModuleA = implementation_for(CollectionA),
    ModuleB = implementation_for(CollectionB),
    case neo_reflect:is_exported(ModuleA, merge, 2) of
        true when ModuleA =:= ModuleB ->
            ModuleA:merge(CollectionA, CollectionB);
        true ->
            ModuleA:merge(CollectionA, to(CollectionB, CollectionA));
        _ ->
            neo_iterable:fold(CollectionB, CollectionA, fun set/3)
    end.

%% @doc Returns `CollectionA' merged with `CollectionB', with conflicts
%% resolved by the given `Combiner'.
%%
%% That is, try to insert each `Key'-`Value' pair in `CollectionB' in
%% `CollectionA'. If the `Key' already exists in `CollectionA', call
%% `Combiner' and use its result as the new `Value'.
%%
%% @see maps:merge_with/3
-spec merge_with(
    t(KeyA, ValueA), t(KeyB, ValueB), combiner(KeyIn, ValueA, ValueB, ValueOut)
) -> t(KeyOut, ValueOut) when
    %% KeyIn is really the _intersection_ of KeyA and KeyB, but Erlang doesn't
    %% support intersection types.
    KeyIn :: KeyA | KeyB,
    KeyOut :: KeyA | KeyB.
merge_with(CollectionA, CollectionB, Combiner) when is_function(Combiner, 3) ->
    ModuleA = implementation_for(CollectionA),
    ModuleB = implementation_for(CollectionB),
    case neo_reflect:is_exported(ModuleA, merge_with, 3) of
        true when ModuleA =:= ModuleB ->
            ModuleA:merge_with(CollectionA, CollectionB, Combiner);
        true ->
            ModuleA:merge_with(CollectionA, to(CollectionB, CollectionA), Combiner);
        false ->
            KeysA = sets:from_list(keys(CollectionA), [{version, 2}]),
            KeysB = sets:from_list(keys(CollectionB), [{version, 2}]),
            Keys = sets:union(KeysA, KeysB),
            sets:fold(
                fun(Key, Collection) ->
                    Value =
                        case
                            {
                                ModuleA:has(CollectionA, Key),
                                ModuleB:has(CollectionB, Key)
                            }
                        of
                            {true, true} ->
                                Combiner(
                                    Key,
                                    ModuleA:get(CollectionA, Key),
                                    ModuleB:get(CollectionB, Key)
                                );
                            {true, false} ->
                                ModuleA:get(CollectionA, Key);
                            {false, true} ->
                                ModuleB:get(CollectionB, Key)
                            %% {false, false} is not allowed, it means `keys' and `has' differ
                            %% Let it crash
                        end,
                    set(Collection, Key, Value)
                end,
                %% Assume updates are cheaper then insertions (which is true
                %% for builtin maps at least)
                case ModuleA:size(CollectionA) < ModuleB:size(CollectionB) of
                    true -> CollectionB;
                    false -> CollectionA
                end,
                Keys
            )
    end.

%%%_ * Callbacks -------------------------------------------------------------
iterator(Collection) ->
    #neo_collection{keys = keys(Collection), collection = Collection}.

next(#neo_collection{keys = []}) ->
    none;
next(#neo_collection{keys = [Key | Keys], collection = Collection} = Iterator) ->
    {Key, neo_collection:get(Collection, Key), Iterator#neo_collection{keys = Keys}}.

%%%_* Private ----------------------------------------------------------------
implementation_for(Collection) ->
    neo_reflect:implementation_for(Collection, [?MODULE]).

%%%_* Tests ==================================================================
-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").

to_test_() ->
    [
        ?_assertEqual(
            #{prop => true, list => 123}, to([prop, {list, 123}], maps)
        ),
        ?_assertEqual(
            #{this => is, an => orddict}, to([{an, orddict}, {this, is}], maps)
        ),
        ?_assertEqual(
            #{1 => <<"some">>, 2 => <<"plain">>, 3 => "list"},
            to([<<"some">>, <<"plain">>, "list"], maps)
        ),
        ?_assertMatch(
            Result when is_list(Result),
            to(neo_maps:new(), [])
        )
    ].

-endif.
