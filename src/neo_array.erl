%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% @doc Implementation of {@link neo_collection} for {@link array}.
%%%
%%% Fixed arrays raise an error for indices outside its bounds, extendible
%%% ones returns a default value. The functions in this module try to respect
%%% that.
%%% @end
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%%%_* Module declaration =====================================================
-module(neo_array).

%%%_* Behaviours =============================================================
-behaviour(neo_collection).

%%%_* Exports ================================================================
%%%_ * API -------------------------------------------------------------------
%%%_ * Callbacks -------------------------------------------------------------
-export([
    delete/2,
    from_list/1,
    get/2,
    has/2,
    keys/1,
    new/0,
    set/3,
    size/1,
    to_list/1
]).

%%%_* Types ------------------------------------------------------------------
-export_type([
    t/0,
    t/1
]).

%%%_* Includes ===============================================================

%%%_* Macros =================================================================
-define(is_non_negative_integer(Value), (is_integer(Value) andalso 0 =< Value)).

-define(is_valid_index(Index, Size),
    (?is_non_negative_integer(Index) andalso Index < Size)
).

%%%_* Types ==================================================================
-type t() :: array:array().

-type t(Element) :: array:array(Element).

%%%_* Code ===================================================================
%%%_ * API -------------------------------------------------------------------

%%%_ * Callbacks -------------------------------------------------------------
new() ->
    array:new([{default, make_ref()}]).

from_list(List) when is_list(List) ->
    case is_integer_orddict(List) of
        true -> array:from_orddict(List);
        false -> array:from_list(List)
    end.

%% @private
is_integer_orddict([]) ->
    true;
is_integer_orddict([{Index0, _}, {Index1, Value1} | Tail]) when
    0 =< Index0 andalso Index0 =< Index1 andalso is_integer(Index1)
->
    case Tail of
        [] -> true;
        _ -> is_integer_orddict([{Index1, Value1} | Tail])
    end;
is_integer_orddict(_) ->
    false.

to_list(List) ->
    array:sparse_to_orddict(List).

-compile({no_auto_import, [size/1]}).
size(Array) ->
    array:sparse_size(Array).

keys(Array) ->
    Default = array:default(Array),
    array:foldr(
        fun(Index, Element, Keys) ->
            case Default of
                Element -> Keys;
                _ -> [Index | Keys]
            end
        end,
        [],
        Array
    ).

has(Array, Index) when ?is_non_negative_integer(Index) ->
    case ?is_valid_index(Index, array:size(Array)) of
        true -> array:get(Index, Array) =/= array:default(Array);
        false -> false
    end.

get(Array, Index) when ?is_non_negative_integer(Index) ->
    %% Default is returned for missing indices
    case {array:get(Index, Array), array:default(Array)} of
        {Default, Default} -> error({badkey, Index}, [Array, Index]);
        {Element, _} -> Element
    end.

set(Array, Index, Element) when ?is_non_negative_integer(Index) ->
    array:set(Index, Element, Array).

delete(Array, Index) when ?is_non_negative_integer(Index) ->
    case has(Array, Index) of
        true -> array:reset(Index, Array);
        false -> Array
    end.

%%%_* Private ----------------------------------------------------------------

%%%_* Tests ==================================================================
-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").

from_list_test_() ->
    maps:to_list(#{
        "integer keyed orddict" => fun() ->
            Array0 = array:new(),
            Array1 = array:set(0, first, Array0),
            Array2 = array:set(1, <<"second">>, Array1),
            ?assertEqual(Array2, from_list([{0, first}, {1, <<"second">>}]))
        end,
        "plain list" => fun() ->
            Array0 = array:new(),
            Array1 = array:set(0, {0, first}, Array0),
            Array2 = array:set(1, {1, <<"second">>}, Array1),
            Array3 = array:set(2, <<"but now a binary">>, Array2),
            ?assertEqual(
                Array3,
                from_list([{0, first}, {1, <<"second">>}, <<"but now a binary">>])
            )
        end
    }).

-endif.
