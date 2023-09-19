%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% @doc Implementation of {@link neo_collection} for {@link dict}.
%%% @end
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%%%_* Module declaration =====================================================
-module(neo_dict).

%%%_* Behaviours =============================================================
-behaviour(neo_collection).

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
    to_list/1
]).

-export([
    filter/2,
    fold/3,
    map/2,
    merge_with/3
]).

%%%_* Types ------------------------------------------------------------------
-export_type([
    t/0,
    t/2
]).

%%%_* Includes ===============================================================

%%%_* Macros =================================================================

%%%_* Types ==================================================================
-type t() :: dict:dict().
%% Represents a generic {@link dict}.

-type t(Key, Value) :: dict:dict(Key, Value).
%% Represents a {@link dict} with the `Key's mapping to `Value's.

%%%_* Code ===================================================================
%%%_ * API -------------------------------------------------------------------

%%%_ * Callbacks -------------------------------------------------------------
%% @doc Returns an empty {@link t(). dict}.
-compile({inline, [new/0]}).
-spec new() -> t().
new() ->
    dict:new().

%% @doc Returns a {@link t(). dict} from the given list of `Key'-`Value'
%% tuples.
-compile({inline, [from_list/1]}).
-spec from_list([{Key, Value}]) -> t(Key, Value).
from_list(List) when is_list(List) ->
    dict:from_list(List).

%% @doc Returns a list of `Key'-`Value' tuples from the given
%% {@link t(). dict}.
-compile({inline, [to_list/1]}).
-spec to_list(t(Key, Value)) -> [{Key, Value}].
to_list(Dict) ->
    dict:to_list(Dict).

%% @doc Returns the size of the given {@link t(). dict}.
-compile({inline, [size/1]}).
-spec size(t()) -> non_neg_integer().
size(Dict) ->
    dict:size(Dict).

%% @doc Returns the keys in the given {@link t(). dict}.
-spec keys(t(Key, _Value)) -> [Key].
-compile({inline, [keys/1]}).
keys(Dict) ->
    dict:fetch_keys(Dict).

%% @doc Returns `true' if `Key' is in the given {@link t(). dict}.
-compile({inline, [has/2]}).
-spec has(t(Key, _Value), Key) -> boolean().
has(Dict, Key) ->
    dict:is_key(Key, Dict).

%% @doc Returns the `Value' associated with the given `Key' in the given
%% {@link t(). dict}.
-compile({inline, [get/2]}).
-spec get(t(Key, Value), Key) -> Value.
get(Dict, Key) ->
    dict:fetch(Key, Dict).

%% @doc Returns the `Value' associated with the given `Key' in the given
%% {@link t(). dict}, or `{error, notfound}' if it is missing.
-compile({inline, [fetch/2]}).
-spec fetch(t(Key, Value), Key) -> {ok, Value} | {error, notfound}.
fetch(Dict, Key) ->
    case dict:find(Key, Dict) of
        {ok, Value} -> {ok, Value};
        error -> {error, notfound}
    end.

%% @doc Returns a {@link t(). dict} with the given `Key' set to the given
%% `Value'.
-compile({inline, [set/3]}).
-spec set(t(Key, Value), Key, Value) -> t(Key, Value).
set(Dict, Key, Value) ->
    dict:store(Key, Value, Dict).

%% @doc Returns a {@link t(). dict} without the given `Key'.
-spec delete(t(Key, Value), Key) -> t(Key, Value).
-compile({inline, [delete/2]}).
delete(Dict, Key) ->
    dict:erase(Key, Dict).

%% @doc Returns the result of folding the given `Folder' over the given
%% {@link t(). dict} with the given `InitialAccumulator'.
-compile({inline, [fold/3]}).
-spec fold(
    t(Key, Value), InitialAccumulator, neo_stream:folder(Accumulator, Key, Value)
) -> Accumulator when
    InitialAccumulator :: Accumulator.
fold(Dict, InitialAccumulator, Folder) when is_function(Folder, 3) ->
    dict:fold(
        fun(Key, Value, Accumulator) ->
            Folder(Accumulator, Key, Value)
        end,
        InitialAccumulator,
        Dict
    ).

%% @doc Returns a new {@link t(). dict} with the same set of keys but where
%% each value is replaced by the result of calling the given `Mapper' of each
%% each `Key'-`Value' pair.
-compile({inline, [map/2]}).
-spec map(t(KeyIn, ValueIn), neo_stream:mapper(KeyIn, ValueIn, KeyOut, ValueOut)) ->
    t(KeyOut, ValueOut).
map(Dict, Mapper) when is_function(Mapper, 2) ->
    dict:map(Mapper, Dict);
map(Dict, Mapper) when is_function(Mapper, 1) ->
    dict:map(
        fun(_Key, ValueIn) ->
            Mapper(ValueIn)
        end,
        Dict
    ).

%% @doc Returns a new {@link t(). dict} with the `Key'-`Value' pairs for which the given `Filter' returns `true'.
-compile({inline, [filter/2]}).
-spec filter(t(Key, Value), neo_stream:filter(Key, Value)) -> t(Key, Value).
filter(Dict, Filter) when is_function(Filter, 2) ->
    dict:filter(Filter, Dict);
filter(Dict, Filter) when is_function(Filter, 1) ->
    dict:filter(
        fun(_Key, Value) ->
            Filter(Value)
        end,
        Dict
    ).

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
merge_with(DictA, DictB, Combiner) ->
    dict:merge(Combiner, DictA, DictB).

%%%_* Private ----------------------------------------------------------------

%%%_* Tests ==================================================================
-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif.
