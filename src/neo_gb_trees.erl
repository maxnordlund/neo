%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% @doc Implementation of {@link neo_collection} for {@link gb_trees}.
%%% @end
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%%%_* Module declaration =====================================================
-module(neo_gb_trees).

%%%_* Behaviours =============================================================
-behaviour(neo_collection).
-behaviour(neo_stream).

%%%_* Exports ================================================================
%%%_ * API -------------------------------------------------------------------
%%%_ * Callbacks -------------------------------------------------------------
-export([
    delete/2,
    fetch/2,
    get/2,
    has/2,
    keys/1,
    map/2,
    new/0,
    set/3,
    size/1,
    to_list/1,
    values/1
]).

-export([
    iterator/1,
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
-type t() :: gb_trees:tree().

-type t(Key, Value) :: gb_trees:tree(Key, Value).

-record(neo_gb_trees, {
    iterator :: gb_trees:iter()
}).

-opaque iterator(Key, Value) :: #neo_gb_trees{
    iterator :: gb_trees:iter(Key, Value)
}.

%%%_* Code ===================================================================
%%%_ * API -------------------------------------------------------------------

%%%_ * Callbacks -------------------------------------------------------------
%% @doc Returns an empty {@link gb_trees. tree}.
-compile({inline, [new/0]}).
-spec new() -> t().
new() ->
    gb_trees:empty().

%% @doc Returns a list of `Key'-`Value' tuples from the given
%% {@link t(). tree}.
-compile({inline, [to_list/1]}).
-spec to_list(t(Key, Value)) -> [{Key, Value}].
to_list(Tree) ->
    gb_trees:to_list(Tree).

%% @doc Returns the size of the given {@link t(). tree}.
-compile({inline, [size/1]}).
-spec size(t()) -> non_neg_integer().
size(Tree) ->
    gb_trees:size(Tree).

%% @doc Returns the keys in the given {@link t(). tree}.
-compile({inline, [keys/1]}).
-spec keys(t(Key, _Value)) -> [Key].
keys(Tree) ->
    gb_trees:keys(Tree).

%% @doc Returns the values in the given {@link t(). tree}.
-compile({inline, [values/1]}).
-spec values(t(Key, _Value)) -> [Key].
values(Tree) ->
    gb_trees:values(Tree).

%% @doc Returns `true' if `Key' is in the given {@link t(). tree}.
-compile({inline, [has/2]}).
-spec has(t(Key, _Value), Key) -> boolean().
has(Tree, Key) ->
    gb_trees:is_defined(Key, Tree).

%% @doc Returns the `Value' associated with the given `Key' in the given
%% {@link t(). tree}.
-compile({inline, [get/2]}).
-spec get(t(Key, Value), Key) -> Value.
get(Tree, Key) ->
    case has(Tree, Key) of
        true -> gb_trees:get(Key, Tree);
        false -> error({badkey, Key}, [Tree, Key])
    end.

%% @doc Returns the `Value' associated with the given `Key' in the given
%% {@link t(). tree}, or `{error, notfound}' if it is missing.
-compile({inline, [fetch/2]}).
-spec fetch(t(Key, Value), Key) -> {ok, Value} | {error, notfound}.
fetch(Tree, Key) ->
    case gb_trees:lookup(Key, Tree) of
        {value, Value} -> {ok, Value};
        none -> {error, notfound}
    end.

%% @doc Returns a {@link t(). tree} with the given `Key' set to the given
%% `Value'.
-compile({inline, [set/3]}).
-spec set(t(Key, Value), Key, Value) -> t(Key, Value).
set(Tree, Key, Value) ->
    gb_trees:enter(Key, Value, Tree).

%% @doc Returns the a {@link gb_trees. tree} without the given `Key'.
-compile({inline, [delete/2]}).
-spec delete(t(Key, Value), Key) -> Value.
delete(Tree, Key) ->
    gb_trees:delete_any(Key, Tree).

%% @doc Returns an iterator for this {@link t(). tree}.
-compile({inline, [iterator/1]}).
-spec iterator(t(Key, Value)) -> iterator(Key, Value).
iterator(Tree) ->
    #neo_gb_trees{
        iterator = gb_trees:iterator(Tree)
    }.

%% @doc Returns the next `Key'-`Value' pair and new iterator for the given
%% {@link gb_trees:iter()}. iterator}, or `none' if there's no more pairs.
-spec next(iterator(Key, Value)) -> {Key, Value, iterator(Key, Value)} | none.
-compile({inline, [next/1]}).
next(#neo_gb_trees{iterator = GeneralBalancedTreeIterator0} = Iterator) ->
    case gb_trees:next(GeneralBalancedTreeIterator0) of
        {Key, Value, GeneralBalancedTreeIterator1} ->
            {Key, Value, Iterator#neo_gb_trees{
                iterator = GeneralBalancedTreeIterator1
            }};
        none ->
            none
    end.

%% @doc Returns a new {@link t(). tree} with the same set of keys but where
%% each value is replaced by the result of calling the given `Mapper' of each
%% each `Key'-`Value' pair.
-spec map(t(KeyIn, ValueIn), neo_stream:mapper(KeyIn, ValueIn, KeyOut, ValueOut)) ->
    t(KeyOut, ValueOut).
-compile({inline, [map/2]}).
map(Tree, Mapper) when is_function(Mapper, 2) ->
    gb_trees:map(Mapper, Tree);
map(Tree, Mapper) when is_function(Mapper, 1) ->
    gb_trees:map(
        fun(_Key, ValueIn) ->
            Mapper(ValueIn)
        end,
        Tree
    ).

%%%_* Private ----------------------------------------------------------------

%%%_* Tests ==================================================================
-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").

-endif.
