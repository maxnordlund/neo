%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% @doc Implementation of {@link neo_collection} for Erlang's builtin
%%% {@link lists}.
%%%
%%% This abstracts over {@link orddict. `orddict's}, {@link proplists}, and
%%% plain lists. To be able to differentiate them, `orddict's may not use
%%% integer as keys, as these are interpreted as indices into a plain list.
%%%
%%% If compiled assertions enabled (without `NOASSERT'), then these functions
%%% all exhaustive validation to ensure only {@link orddict. `orddict's} are
%%% passed.
%%% @end
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%%%_* Module declaration =====================================================
-module(neo_lists).

%%%_* Behaviours =============================================================
-behaviour(neo_collection).
-behaviour(neo_stream).

%%%_* Exports ================================================================
%%%_ * API -------------------------------------------------------------------
-export([
    typeof/1,
    typeof/2,
    iterator/2
]).

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
    iterator/1,
    next/1
]).

%%%_* Types ------------------------------------------------------------------
-export_type([
    index/0,
    iterator/1,
    iterator/2,
    key/0,
    t/0,
    t/1,
    t/2
]).

%%%_* Includes ===============================================================
-include("internal.hrl").
-include("assertions.hrl").

%%%_* Macros =================================================================
-define(is_valid_index(Index, Size), (0 < Index andalso Index =< Size)).

%%%_* Types ==================================================================
-type t() :: list().

-type t(Element) :: list(Element).

-type t(Key, Value) :: orddict:orddict(Key, Value) | proplists:proplist().

-type index() :: pos_integer().

-type key() :: atom() | binary().

-record(neo_lists, {
    type :: plain | two_tuples,
    current_index = 1 :: non_neg_integer(),
    source :: t()
}).

-opaque iterator(Element) ::
    #neo_lists{
        type :: plain,
        source :: t(Element)
    }.

-opaque iterator(Key, Value) ::
    #neo_lists{
        type :: two_tuples,
        source :: t(Key, Value)
    }.

%%%_* Code ===================================================================
%%%_ * API -------------------------------------------------------------------
%% @doc Returns the type of the given `list'.
%%
%% <ul>
%% <li>An `orddict' is a sorted list of two-tuples, where the first elements
%%     of each tuple form a set (they are unique amongst themselves)</li>
%% <li>A {@link proplists. proplist} is an unsorted mixed list of atoms and
%%     two-tuples</li>
%% <li>Otherwise it's a `plain' list</li>
%% </ul>
%%
%% This means an empty list is counted as a `plain' list, even though it can
%% be considered any one of them.
%%
%% When compiled with assertions disabled, this is checked using just the
%% first couple of elements. Otherwise an exhaustive check is performed.
%% Therefore it is recommended that you compile with `NOASSERT' in production,
%% but it's useful to keep assertions on when testing.
-spec typeof(list()) -> orddict | proplist | plain.
typeof([]) ->
    plain;
typeof(List) when is_list(List) ->
    case typeof(orddict, List) of
        two_tuples -> plain;
        Type -> Type
    end.

%%%_ * Callbacks -------------------------------------------------------------
%% @doc Returns an empty list.
-compile({inline, [new/0]}).
-spec new() -> t().
new() ->
    [].

%% @doc Returns a normalized version of the given list.
%%
%% If the list only contain two-tuples where the first element of every tuple
%% is a non-integer, it is {@link orddict:from_list/1. transformed} to an
%% orddict.
%% If the list only contain either atoms or two-tuples where the first element
%% of every tuple is an atom, it is transformed to an orddict.
%% Otherwise the list is returned as is.
%%
%% @see orddict:from_list/1
%% @see proplists:unfold/1
from_list([]) ->
    [];
from_list(List) when is_list(List) ->
    case typeof(two_tuples, List) of
        %% orddict can never be returned when starting from two_tuple
        two_tuples -> orddict:from_list(List);
        proplist -> lists:ukeysort(1, proplists:unfold(List));
        plain -> List
    end.

%% @doc Returns the given list as is, since it's already a list.
-spec to_list(t()) -> t().
to_list(List) when is_list(List) ->
    List.

%% @doc Returns the {@link erlang:length/1. length} of the given list.
-compile({inline, [size/1]}).
-spec size(t()) -> non_neg_integer().
size(List) when is_list(List) ->
    length(List).

%% @doc Returns a list of indices or keys for the given list.
%%
%% @see typeof/1
-dialyzer({nowarn_function, keys/1}).
-spec keys
    (t(_Element)) -> [index()];
    (t(Key, _Value)) -> [Key] when
        Key :: key().
keys(List) when is_list(List) ->
    case typeof(List) of
        orddict ->
            ?assertIsOrddict(List, [List]),
            orddict:fetch_keys(List);
        proplist ->
            proplists:get_keys(List);
        plain ->
            lists:seq(1, length(List))
    end.

values(List) when is_list(List) ->
    case typeof(List) of
        orddict ->
            ?assertIsOrddict(List, [List]),
            get_values(List);
        proplist ->
            get_values(proplists:unfold(List));
        plain ->
            List
    end.

%% @doc Returns `true' if `Index' or `Key' is in the given list.
%%
%% If given an `atom' key, the given list is treated as a
%% {@link proplists:proplist(). proplist}, otherwise it is treated as an
%% {@link orddict:orddict(). orddict}.
-spec has
    (t(), index()) -> boolean();
    (t(Key, _Value), Key) -> boolean() when
        Key :: key().
has(List, Index) when is_list(List) andalso is_integer(Index) ->
    ?is_valid_index(Index, length(List));
has(Proplist, Key) when is_list(Proplist) andalso is_atom(Key) ->
    proplists:is_defined(Key, Proplist);
has(Orddict, Key) when is_list(Orddict) ->
    ?assertIsOrddict(Orddict, [Orddict, Key]),
    orddict:is_key(Key, Orddict).

%% @doc Returns the `Element' at the given `Index' or the `Value' at the given
%% `Key' in the given list.
%%
%% If given an `atom' key, the given list is treated as a
%% {@link proplists:proplist(). proplist}, otherwise it is treated as an
%% {@link orddict:orddict(). orddict}.
-spec get
    (t(Element), index()) -> Element;
    (t(Key, Value), Key) -> Value when
        Key :: key().
get(List, Index) when is_list(List) andalso ?is_valid_index(Index, length(List)) ->
    lists:nth(Index, List);
get(List, Index) when is_list(List) andalso is_integer(Index) ->
    error({badkey, Index}, [List, Index]);
get(Proplist, Key) when is_list(Proplist) andalso is_atom(Key) ->
    %% Use the list itself as a sentinel as Erlang does not allow cyclic
    %% structures
    case proplists:get_value(Key, Proplist, Proplist) of
        Proplist -> error({badkey, Key}, [Proplist, Key]);
        Value -> Value
    end;
get(Orddict, Key) when is_list(Orddict) ->
    ?assertIsOrddict(Orddict, [Orddict, Key]),
    orddict:fetch(Key, Orddict).

-spec fetch
    (t(Element), index()) -> {ok, Element} | {error, notfound};
    (t(Key, Value), Key) -> {ok, Value} | {error, notfound} when
        Key :: key().
fetch(List, Index) when is_list(List) andalso ?is_valid_index(Index, length(List)) ->
    {ok, lists:nth(Index, List)};
fetch(List, Index) when is_list(List) andalso is_integer(Index) ->
    {error, notfound};
fetch(Proplist, Key) when is_list(Proplist) andalso is_atom(Key) ->
    %% Use the list itself as a sentinel as Erlang does not allow cyclic
    %% structures
    case proplists:get_value(Key, Proplist, Proplist) of
        Proplist -> {error, notfound};
        Value -> {ok, Value}
    end;
fetch(Orddict, Key) when is_list(Orddict) ->
    ?assertIsOrddict(Orddict, [Orddict, Key]),
    case orddict:find(Key, Orddict) of
        {ok, Value} -> {ok, Value};
        error -> {error, notfound}
    end.

%% @doc Returns a list with the given `Element' inserted at the given `Index'
%% or the given `Key' set to the given `Value'.
%%
%% If there's already an element at the index or key, it is replace.
%% If given `0' as the index, the `Element' is prepended.
%% If given `length(List) + 1' as the index, the `Element' is appended.
%%
%% It fails with `badkey' if the index is out of bounds.
-spec set
    (t(Element), 0 | index(), Element) -> t(Element);
    (t(Key, Value), Key, Value) -> t(Key, Value) when
        Key :: key().
set(List, 0, Element) when is_list(List) ->
    [Element | List];
set(List, Index, Element) when
    is_list(List) andalso ?is_valid_index(Index, length(List))
->
    {Init, [_ExistingElement | Tail]} = lists:split(Index - 1, List),
    Init ++ [Element | Tail];
set(List, Index, Element) when is_list(List) andalso Index =:= (length(List) + 1) ->
    List ++ [Element];
set(List, Index, Element) when is_list(List) andalso is_integer(Index) ->
    error({badkey, Index}, [List, Index, Element]);
set(OrddictOrProplist, Key, Value) when is_atom(Key) ->
    set_orddict_or_proplist(OrddictOrProplist, Key, Value, []);
set(Orddict, Key, Value) ->
    ?assertIsOrddict(Orddict, [Orddict, Key, Value]),
    orddict:store(Key, Value, Orddict).

%% @doc Returns a list without the element at `Index', or without the `Key'.
%%
%% If given an `atom' key, the given list is treated as a
%% {@link proplists:proplist(). proplist}, otherwise it is treated as an
%% {@link orddict:orddict(). orddict}.
%%
%% It fails with `badkey' if the index is out of bounds.
-spec delete
    (t(Element), index()) -> t(Element);
    (t(Key, Value), Key) -> t(Key, Value) when
        Key :: key().
delete(List, Index) when is_list(List) andalso ?is_valid_index(Index, length(List)) ->
    {Init, [_ | Tail]} = lists:split(Index - 1, List),
    Init ++ Tail;
delete(List, Index) when is_list(List) andalso is_integer(Index) ->
    List;
delete(Proplist, Key) when is_list(Proplist) andalso is_atom(Key) ->
    proplists:delete(Key, Proplist);
delete(Orddict, Key) when is_list(Orddict) ->
    ?assertIsOrddict(Orddict, [Orddict, Key]),
    orddict:erase(Key, Orddict).

%% @doc Returns an iterator for this list.
-dialyzer({nowarn_function, iterator/1}).
-spec iterator
    (t(Element)) -> iterator(Element);
    (t(Key, Value)) -> iterator(Key, Value) when
        Key :: key().
iterator(List) ->
    iterator(List, typeof(List)).

%% @doc Return an iterator for the given list and type.
%%
%% This does not do any type inference, and is is useful if you just want an
%% easy iterator for some stuff you already have in a list.
-spec iterator
    (t(Element), plain) -> iterator(Element);
    (t(Key, Value), orddict | proplist) -> iterator(Key, Value) when
        Key :: key().
iterator(List, orddict) ->
    ?assertIsOrddict(List, [List]),
    #neo_lists{
        type = two_tuples,
        source = List
    };
iterator(List, proplist) ->
    #neo_lists{
        type = two_tuples,
        source = proplists:unfold(List)
    };
iterator(List, plain) ->
    #neo_lists{
        type = plain,
        source = List
    }.

%% @doc Returns the next element and new iterator for the given list, or `none'
%% if the given list is empty.
-spec next
    (iterator(Element)) -> {index(), Element, iterator(Element)} | none;
    (iterator(Key, Value)) -> {Key, Value, iterator(Key, Value)} | none.
next(#neo_lists{source = []}) ->
    none;
next(#neo_lists{type = two_tuples, source = [{Key, Value} | Tail]} = Iterator) ->
    {Key, Value, Iterator#neo_lists{
        source = Tail
    }};
next(
    #neo_lists{type = plain, current_index = LastIndex, source = [Last]} = Iterator
) when
    is_integer(LastIndex)
->
    {LastIndex, Last, Iterator#neo_lists{source = []}};
next(
    #neo_lists{type = plain, current_index = CurrentIndex, source = [Element | Tail]} =
        Iterator
) when
    is_integer(CurrentIndex)
->
    {CurrentIndex, Element, Iterator#neo_lists{
        current_index = CurrentIndex + 1,
        source = Tail
    }}.

%%%_* Private ----------------------------------------------------------------
%% @private
%% @doc Returns the type of the given `List'.
%%
%% Must handle improper lists.
%%
%% With assertions on, it checks all elements of the list. Otherwise it only
%% checks the first 32 elements.
%%
%% Why 32? It is the size bultin maps change representation, so it seems
%% fitting use as the sample size.
-spec typeof(CurrentGuess, list()) -> FinalGuess when
    CurrentGuess :: FinalGuess,
    FinalGuess :: orddict | proplist | two_tuples | plain.
-ifndef(NOASSERT).
typeof(CurrentGuess, List) ->
    %% The -1 is a hack to trick `typeof/3' to not stop at 32 elements.
    typeof(CurrentGuess, List, -1).
-else.
typeof(CurrentGuess, List) ->
    typeof(CurrentGuess, List, 32).
-endif.

-spec typeof(CurrentGuess, list(), SampleLength) -> FinalGuess when
    CurrentGuess :: FinalGuess,
    SampleLength :: integer(),
    FinalGuess :: orddict | proplist | two_tuples | plain.
typeof(CurrentGuess, [], _) ->
    CurrentGuess;
typeof(CurrentGuess, _, 0) ->
    CurrentGuess;
typeof(CurrentGuess, [{Key, _Value}], _) when
    ?oneof(CurrentGuess, orddict, two_tuples) andalso not is_integer(Key)
->
    CurrentGuess;
typeof(orddict, [{Key0, _Value0}, {Key1, Value1} | Tail], SampleLength) when
    not is_integer(Key0) andalso not is_integer(Key1) andalso Key0 =< Key1
->
    typeof(orddict, [{Key1, Value1} | Tail], SampleLength - 1);
typeof(
    CurrentGuess, [{Key0, _Value0}, {Key1, Value1} | Tail], SampleLength
) when
    ?oneof(CurrentGuess, orddict, two_tuples) andalso
        not is_integer(Key0) andalso not is_integer(Key1)
->
    typeof(two_tuples, [{Key1, Value1} | Tail], SampleLength - 1);
typeof(_, [Atom | Tail], SampleLength) when is_atom(Atom) ->
    typeof(proplist, Tail, SampleLength - -1);
typeof(_, [{Key, _Value} | Tail], SampleLength) when is_atom(Key) ->
    typeof(proplist, Tail, SampleLength - 1);
typeof(_, _, _) ->
    plain.

get_values(TwoTuples) ->
    [Value || {_Key, Value} <- TwoTuples].

set_orddict_or_proplist([], Key, NewValue, Result) ->
    lists:reverse([{Key, NewValue} | Result]);
set_orddict_or_proplist([{CurrentKey, CurrentValue} | Tail], Key, NewValue, Result) when
    CurrentKey < Key
->
    set_orddict_or_proplist(Tail, Key, NewValue, [
        {CurrentKey, CurrentValue} | Result
    ]);
set_orddict_or_proplist([{Key, _CurrentValue} | Tail], Key, NewValue, Result) ->
    lists:reverse([{Key, NewValue} | Result], Tail);
set_orddict_or_proplist(
    [{CurrentKey, _CurrentValue} | _] = Tail, Key, NewValue, Result
) when Key < CurrentKey ->
    lists:reverse([{Key, NewValue} | Result], Tail);
set_orddict_or_proplist([Property | Tail], Property, NewValue, Result) ->
    lists:reverse([{Property, NewValue} | Result], Tail);
set_orddict_or_proplist([CurrentProperty | Tail], Property, NewValue, Result) when
    is_atom(CurrentProperty) andalso Property < CurrentProperty
->
    lists:reverse([CurrentProperty, {Property, NewValue} | Result], Tail);
set_orddict_or_proplist([AtomOrTuple | Tail], Key, NewValue, Result) when
    is_atom(AtomOrTuple) orelse tuple_size(AtomOrTuple) =:= 2
->
    set_orddict_or_proplist(Tail, Key, NewValue, [AtomOrTuple | Result]).

%%%_* Tests ==================================================================
-ifdef(TEST).
-include("test_helpers.hrl").
-include_lib("eunit/include/eunit.hrl").

typeof_test_() ->
    neo_test_helpers:test_case(#{
        "plain list" => ?_assertEqual(
            plain, typeof([{<<"b">>, 1}, {<<"a">>, 2}, {<<"c">>, 3}])
        ),
        "improper list" => fun() ->
            ?assertNotException(typeof([a, b, c | d]))
        end,
        "two_tuple guess cannot return orddict" => ?_quickcheck(
            neo_proper_types:orddict_type(),
            Orddict,
            typeof(two_tuples, Orddict) =/= orddict
        )
    }).

set_test_() ->
    [
        ?_assertEqual([value], set([], 0, value)),
        ?_assertEqual([value, <<"abc">>], set([<<"abc">>], 0, value)),
        ?_assertError({badkey, 10}, set([a, b, c], 10, value)),
        ?_assertEqual([{flag, true}, stuff], set([stuff], flag, true)),
        ?_assertEqual(
            [{flag, <<"value">>}, stuff],
            set([{flag, <<"current">>}, stuff], flag, <<"value">>)
        )
    ].

from_list_test_() ->
    neo_test_helpers:test_case(#{
        "empty list" => ?_assertEqual([], from_list([])),
        "plain list" => ?_assertEqual([<<"a">>, "b", c], from_list([<<"a">>, "b", c])),
        "proplist" => ?_assertEqual(
            [{flag, true}, {with, <<"value">>}],
            from_list([flag, flag, {with, <<"value">>}])
        ),
        "orddict" => ?_assertEqual(
            [{<<"age">>, 27}, {<<"name">>, <<"Jane Doe">>}],
            from_list([{<<"age">>, 27}, {<<"name">>, <<"Jane Doe">>}])
        )
    }).

to_list_test() ->
    ?quickcheck(proper_types:list(), List, to_list(List) == List).

-endif.
