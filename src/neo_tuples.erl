%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% @doc Implementation of {@link neo_collection} for `tuple's.
%%% @end
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%%%_* Module declaration =====================================================
-module(neo_tuples).

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
    to_list/1
]).

-export([
    iterator/1,
    next/1
]).

%%%_* Types ------------------------------------------------------------------
-export_type([
    iterator/0,
    t/0
]).

%%%_* Includes ===============================================================
-include("internal.hrl").

%%%_* Macros =================================================================
-define(is_valid_index(Index, Size), (0 < Index andalso Index =< Size)).

%%%_* Types ==================================================================
-type t() :: tuple().

-record(neo_tuples, {
    current_index = 1 :: non_neg_integer(),
    source :: t()
}).

-opaque iterator() :: #neo_tuples{}.

%%%_* Code ===================================================================
%%%_ * API -------------------------------------------------------------------

%%%_ * Callbacks -------------------------------------------------------------
%% @doc Returns an empty tuple.
-spec new() -> t().
new() ->
    {}.

%% @doc Returns a tuple whose elements correspond it the elements from the
%% given list.
%%
%% @see erlang:list_to_tuple/1
-compile({inline, [from_list/1]}).
-spec from_list(list()) -> t().
from_list(List) when is_list(List) ->
    list_to_tuple(List).

%% @doc Returns the given tuple as a list.
%%
%% @see erlang:tuple_to_list/1
-compile({inline, [to_list/1]}).
-spec to_list(t()) -> list().
to_list(Tuple) when is_tuple(Tuple) ->
    tuple_to_list(Tuple).

size(Tuple) when is_tuple(Tuple) ->
    tuple_size(Tuple).

keys(Tuple) when is_tuple(Tuple) ->
    lists:seq(1, tuple_size(Tuple)).

has(Tuple, Index) when is_tuple(Tuple) andalso is_integer(Index) ->
    ?is_valid_index(Index, tuple_size(Tuple));
has(Tuple, Term) when is_tuple(Tuple) ->
    error({badkey, Term}, [Tuple, Term]).

get(Tuple, Index) when
    is_tuple(Tuple) andalso ?is_valid_index(Index, tuple_size(Tuple))
->
    element(Index, Tuple);
get(Tuple, Index) when is_tuple(Tuple) andalso is_integer(Index) ->
    error({badkey, Index}, [Tuple, Index]).

fetch(Tuple, Index) when
    is_tuple(Tuple) andalso ?is_valid_index(Index, tuple_size(Tuple))
->
    {ok, element(Index, Tuple)};
fetch(Tuple, Index) when is_tuple(Tuple) andalso is_integer(Index) ->
    {error, notfound}.

set(Tuple, 0, Element) when is_tuple(Tuple) ->
    erlang:insert_element(1, Tuple, Element);
set(Tuple, Index, Element) when
    is_tuple(Tuple) andalso ?is_valid_index(Index, tuple_size(Tuple))
->
    setelement(Index, Tuple, Element);
set(Tuple, Index, Element) when
    is_tuple(Tuple) andalso Index =:= (tuple_size(Tuple) + 1)
->
    erlang:insert_element(Index, Tuple, Element);
set(Tuple, Index, Element) when is_tuple(Tuple) andalso is_integer(Index) ->
    error({badkey, Index}, [Tuple, Index, Element]).

delete(Tuple, Index) when
    is_tuple(Tuple) andalso ?is_valid_index(Index, tuple_size(Tuple))
->
    erlang:delete_element(Index, Tuple);
delete(Tuple, Index) when is_tuple(Tuple) andalso is_integer(Index) ->
    Tuple.

iterator(Tuple) when is_tuple(Tuple) ->
    #neo_tuples{source = Tuple}.

next(#neo_tuples{current_index = CurrentIndex, source = Tuple} = Iterator) when
    CurrentIndex =< tuple_size(Tuple)
->
    {CurrentIndex, element(CurrentIndex, Tuple), Iterator#neo_tuples{
        current_index = CurrentIndex + 1
    }};
next(#neo_tuples{current_index = CurrentIndex, source = Tuple}) when
    is_integer(CurrentIndex) andalso is_tuple(Tuple)
->
    none.

%%%_* Private ----------------------------------------------------------------

%%%_* Tests ==================================================================
-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").

has_test_() ->
    [
        ?_assert(has({1, 2, 3}, 1)),
        ?_assert(has({1, 2, 3}, 3)),
        ?_assertNot(has({1, 2, 3}, 10)),
        ?_assertError({badkey, key}, has({1, 2, 3}, key))
    ].

set_test_() ->
    maps:to_list(#{
        "zero prepends" => fun() ->
            ?assertEqual({a, 1, 2, 3}, set({1, 2, 3}, 0, a))
        end,
        "size + 1 appends" => fun() ->
            ?assertEqual({1, 2, 3, a}, set({1, 2, 3}, 4, a))
        end,
        "index out of bounds errors" => fun() ->
            ?assertError({badkey, 10}, set({1, 2, 3}, 10, a))
        end
    }).

-endif.
