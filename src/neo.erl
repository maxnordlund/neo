%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% @doc Convenience functions for working with (nested) maps, and lists of
%%% (nested) maps.
%%%
%%% Mimics the builtin `lists' and `maps' module, and is meant as a
%%% replacement for `eon'.
%%%
%%% There are two main differences to `lists' `key*' functions. First they
%%% are named using an underscore, `key_find' instead of `lists:keyfind'.
%%%
%%% Secondly they all take Maps as the first argument, and if appropriate
%%% Key as the second argument.
%%% @end
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

-compile({no_auto_import, [{get, 2}]}).

%%%_* Module declaration ======================================================
-module(neo).

%%%_* Exports =================================================================
%%%_ * API --------------------------------------------------------------------

-export([
    deep_filter/2,
    deep_filter_map/2,
    deep_flatten/1,
    deep_fold/3,
    deep_map/2,
    deep_map_keys/2,
    deep_map_values/2,
    dget/2,
    dget/3,
    dget_/2,
    delete/2,
    ddelete/2,
    dset/3,
    fold/3,
    from_list/1,
    get/2,
    get/3,
    get_/2,
    group_by/2,
    group_unique_by/2,
    group_unique_by/3,
    key_delete/3,
    key_find/3,
    key_get/2,
    key_get/3,
    key_map/3,
    key_member/3,
    key_merge/3,
    key_replace/4,
    key_sort/2,
    key_store/4,
    key_take/3,
    key_unique_merge/3,
    key_unique_sort/2,
    map/2,
    map_keys/2,
    map_values/2,
    merge/1,
    merge/2,
    new/0,
    pop/2,
    set/3,
    to_list/1,
    with/2,
    without/2
]).

%%%_ * Types ------------------------------------------------------------------

-export_type([
    collection/0,
    collection/2,
    key/0,
    proplist/0,
    proplist/2
]).

%%%_* Includes ================================================================
-include_lib("stdlib/include/assert.hrl").

%%%_ * Types ==================================================================

-type key() :: atom() | binary().

-type proplist(A, B) :: [{A, B}].

-type proplist() :: proplist(key(), term()).

-type collection(Key, Value) ::
    #{Key := Value | collection(Key, Value)}
    | proplist(Key, Value | collection(Key, Value))
    | [Value | collection(Key, Value)].

-type collection() :: collection(key(), term()).

%%%_* Macros ==================================================================
-define(is_key(Key), (is_atom(Key) orelse is_binary(Key))).

-define(is_ordset(Object),
    (length(Object) =:= 0 orelse
        (tuple_size(hd(Object)) =:= 2 andalso
            ?is_key(element(1, hd(Object)))))
).

%%%_* Code ====================================================================
%%%_ * API --------------------------------------------------------------------

%% @doc Returns a potentially nested map by recursively converting the given
%% potentially nested key-value list.
%%
%% This is effectively a recursive `maps:from_list'.
%% Empty lists are converted to empty maps.
-spec from_list(proplist(A, B)) -> #{A => B}.
from_list([]) ->
    #{};
from_list([{_Key, _Value} | _] = Proplist) ->
    maps:from_list([
        {Key, from_list(Value)}
     || {Key, Value} <- Proplist
    ]);
from_list(List) when is_list(List) ->
    lists:map(fun from_list/1, List);
from_list(Other) ->
    Other.

%% @doc Returns a potentially nested proplist by recursively convert the given
%% potentially nested map.
%%
%% Effectively a recursive `maps:to_list'
-spec to_list
    (#{A => B}) -> proplist(A, B);
    (proplist(A, B)) -> proplist(A, B).
to_list([]) ->
    [];
to_list(Map) when is_map(Map) ->
    [
        {Key, to_list(Value)}
     || {Key, Value} <- maps:to_list(Map)
    ];
to_list(List) when is_list(List) ->
    lists:map(fun to_list/1, List);
to_list(Other) ->
    Other.

%% @doc Creates a new map, for compatibility with {@link eon}.
new() -> #{}.

%% @doc Returns the value associated with `Key' if given a map
%%      returns the value associated with `Key' if given a proplist and
%%          either a binary or atom key, or
%%      returns the `Index'th element if given a list and an integer key.
%%
%% Returns `{error, notfound}' if there is no such value.
-spec get
    (#{Key => Value}, Key) -> {ok, Value} | {error, notfound};
    ([Element], Lookup) -> {ok, Value} | {error, notfound} when
        Element :: {Key, Value} | Value,
        Lookup :: Key | pos_integer(),
        Key :: atom() | binary(),
        Value :: term().
get(Map, Key) when is_map(Map) ->
    case Map of
        #{Key := Value} -> {ok, Value};
        _ -> {error, notfound}
    end;
get(Object, Key) when ?is_ordset(Object) andalso ?is_key(Key) ->
    case lists:keyfind(Key, 1, Object) of
        {Key, Value} -> {ok, Value};
        false -> {error, notfound}
    end;
get(List, Index) when is_list(List) andalso is_integer(Index) ->
    case nth(Index, List) of
        {ok, Value} -> {ok, Value};
        false -> {error, notfound}
    end.

%% @doc Returns the value associated with `Key' if given a map,
%%      returns the value associated with `Key' if given a proplist and
%%          either a binary or atom key, or
%%      returns the `Index'th element if given a list and an integer key.
%%
%% Fails with a `{badkey, Key | Index}' exception if there is no such value.

%% Dialyzer doesn't like this spec, however accurate it may be.
%% -spec get(#{ Key => Value }, Key) -> Value | no_return()
%%        ; ([{ Key, Value }], Key)  -> Value | no_return() when Key :: atom() | binary()
%%        ; ([Value], pos_integer()) -> Value | no_return().
%% Overloaded contract for neo:get/2 has overlapping domains;
%% such contracts are currently unsupported and are simply ignored
%% So go with a simpler (yet accurate) one.
-spec get_
    (#{Key => Value}, Key) -> Value | no_return();
    ([Element], Lookup) -> Value | no_return() when
        Element :: {Key, Value} | Value,
        Lookup :: Key | pos_integer(),
        Key :: atom() | binary(),
        Value :: term().
get_(Collection, Lookup) ->
    case get(Collection, Lookup) of
        {ok, Value} -> Value;
        {error, notfound} -> error({badkey, Lookup})
    end.

%% @doc Like `get/2' expect it also accepts an `Default' value which is
%% returned if the key/index is not found.
-spec get
    (#{Key => Value}, Key, Default) -> Value | Default;
    ([Element], Lookup, Default) -> Value | Default when
        Element :: {Key, Value} | Value,
        Lookup :: Key | pos_integer(),
        Key :: atom() | binary(),
        Value :: term().
get(Collection, Lookup, Default) ->
    case get(Collection, Lookup) of
        {ok, Value} -> Value;
        {error, notfound} -> Default
    end.

%% @doc Like `get/2', except it accepts either a dot separated path in a
%% binary for binary keys, dot separated atom for atom keys, or a list of
%% explicit path elements.
%%
%% To make it a bit more convenient, this allows you to use the dot
%% separated path even with atomed keyed maps.
%%
%% If you need to traverse lists, use a path list with integer indexes.
%%
%% Fails with a `{badkey, Key | Index}' exception if there is no such value.
-spec dget_(Collection, Lookup) -> Value | no_return() when
    Collection :: collection(Key, Value),
    Lookup :: DottedPath | [Key | pos_integer()],
    Key :: key(),
    DottedPath :: key(),
    Value :: term().
dget_(Collection, Lookup) ->
    case dget(Collection, Lookup) of
        {ok, Value} -> Value;
        {error, notfound} -> error({badkey, Lookup})
    end.

%% @doc Like `get/2', except it accepts either a dot separated path in a
%% binary for binary keys, dot separated atom for atom keys, or a list
%% of explicit path elements.
%%
%% To make it a bit more convenient, this allows you to use the dot
%% separated path even with atomed keyed maps.
%%
%% If you need to traverse lists, use a path list with integer indexes.
%%
%% Returns `{error, notfound}' if there is no such value.
-spec dget(Collection, Lookup) -> {ok, Value} | {error, notfound} when
    Collection :: collection(Key, Value),
    Lookup :: DottedPath | [Key | pos_integer()],
    Key :: key(),
    DottedPath :: key(),
    Value :: term().
dget(Map, Key) when is_map_key(Key, Map) ->
    {ok, maps:get(Key, Map)};
dget(Map, Path) when is_atom(Path) orelse is_binary(Path) ->
    PathParts = split_path_parts(Path),
    dget_internal({ok, Map}, PathParts);
dget(Map, Path) ->
    dget_internal({ok, Map}, Path).

%% @doc Like `dget/2' expect it also accepts an `Default' value which is
%% returned if any of the keys/indexes are not found.
-spec dget(Collection, Lookup, Default) -> Value | Default when
    Collection :: collection(Key, Value),
    Lookup :: DottedPath | [Key | pos_integer()],
    Key :: key(),
    DottedPath :: key(),
    Value :: term().
dget(Collection, Lookup, Default) ->
    case dget(Collection, Lookup) of
        {ok, Value} -> Value;
        {error, notfound} -> Default
    end.

%% @doc Sets the given `Value' in the given collection as appropriate.
%% Turns a proplist into an orddict, i.e. a proplist sorted by keys.
-spec set(Collection, Lookup, Value) -> Collection when
    Collection :: collection(Key, Value),
    Lookup :: Key | pos_integer(),
    Key :: key(),
    Value :: term().
set(Map, Key, Value) when is_map(Map) ->
    maps:put(Key, Value, Map);
set(Object, Key, Value) when ?is_ordset(Object) andalso ?is_key(Key) ->
    OrderedDictionary = orddict:from_list(Object),
    orddict:store(Key, Value, OrderedDictionary);
set(List, Index, Value) when is_list(List) andalso is_integer(Index) ->
    {Head, Tail} = lists:split(Index, List),
    Head ++ [Value | Tail].

%% @doc Like `set/2', except it accepts either a dot separated path in a
%% binary for binary keys, dot separated atom for atom keys, or a list of
%% explicit path elements.
%%
%% To make it a bit more convenient, this allows you to use the dot
%% separated path even with atomed keyed maps.
%%
%% If you need to traverse lists, use a path list with integer indexes.
-spec dset(Collection, Lookup, Value) -> Collection when
    Collection :: collection(Key, Value),
    Lookup :: DottedPath | [Key | pos_integer()],
    Key :: key(),
    DottedPath :: key(),
    Value :: term().
dset(Map, Key, Value) when is_map_key(Key, Map) ->
    maps:put(Key, Value, Map);
dset(Map, Path, Value) when is_atom(Path) orelse is_binary(Path) ->
    PathParts = split_path_parts(Path),
    dset_internal(Map, PathParts, Value);
dset(Map, Path, Value) ->
    dset_internal(Map, Path, Value).

%% @doc Returns the given map, proplist or plain list without the element
%% associated with the given `Key' or `Index' if it exists.
-spec delete(Collection, Lookup) -> Collection when
    Collection :: collection(Key, Value),
    Lookup :: Key | pos_integer(),
    Key :: key(),
    Value :: term().
delete(Map, Key) when is_map_key(Key, Map) ->
    maps:remove(Key, Map);
delete(Map, _Key) when is_map(Map) ->
    Map;
delete(Object, Key) when ?is_ordset(Object) andalso ?is_key(Key) ->
    lists:keydelete(Key, 1, Object);
delete(List, Index) when is_list(List) andalso is_integer(Index) ->
    {Head, [_ | Tail]} = lists:split(Index - 1, List),
    Head ++ Tail.

%% @doc Like `delete/2', except it accepts either a dot separated path in a
%% binary for binary keys, dot separated atom for atom keys, or a list of
%% explicit path elements. It only accepts maps, unlike `delete/2'.
%%
%% To make it a bit more convenient, this allows you to use the dot
%% separated path even with atomed keyed maps.
%%
%% If you need to traverse lists, use a path list with integer indexes.
-spec ddelete(Collection, Lookup) -> Collection when
    Collection :: collection(Key, Value),
    Lookup :: DottedPath | [Key | pos_integer()],
    Key :: key(),
    DottedPath :: key(),
    Value :: term().
ddelete(Map, Key) when is_map_key(Key, Map) ->
    maps:remove(Key, Map);
ddelete(Map, Path) when is_atom(Path) orelse is_binary(Path) ->
    PathParts = split_path_parts(Path),
    ddelete_internal(Map, PathParts);
ddelete(Map, Path) ->
    ddelete_internal(Map, Path).

%% @doc Returns the element associated with the given `Key' or `Index', and the
%% given map, proplist or plain list without that element.
%%
%% Effectively a combination of {@link get/2} and {@link delete/2}.
-spec pop
    (#{Key => Value}, Key) -> {Value, map()} | no_return();
    ([Element], Lookup) -> {Value, [Element]} | no_return() when
        Element :: {Key, Value} | Value,
        Lookup :: Key | pos_integer(),
        Key :: atom() | binary(),
        Value :: term().
pop(Collection, Lookup) ->
    Value = get_(Collection, Lookup),
    {Value, delete(Collection, Lookup)}.

%% @doc Returns a map of lists where the keys are the set of values
%% associated with `Key' in each of the maps in `Maps'.
%%
%% This means each key may have one or more maps associated with it.
-spec group_by([Map], Key) -> #{Value => [Map]} when Map :: #{Key => Value}.
group_by(Maps, Fun) when is_function(Fun, 1) ->
    ?assertEqual([], [Term || Term <- Maps, not is_map(Term)]),
    lists:foldl(
        fun(Map, Groups) ->
            case Fun(Map) of
                {ok, Value} ->
                    Group = maps:get(Value, Groups, []),
                    Groups#{Value => [Map | Group]};
                {error, notfound} ->
                    Groups
            end
        end,
        #{},
        Maps
    );
group_by(Maps, Key) ->
    group_by(Maps, fun(Map) -> get(Map, Key) end).

%% @doc Returns a map of maps where the keys are the set of values
%% associated with `Key' in each of the maps in `Maps'.
%%
%% Unlike `group_by/2' this returns the first map as determined by
%% `lists:sort/1'.
-spec group_unique_by([Map], Key) -> #{Value => Map} when Map :: #{Key => Value}.
group_unique_by(Maps, Key) ->
    map_values(group_by(Maps, Key), fun(_Key, Value) ->
        hd(lists:sort(Value))
    end).

%% @doc Returns a map of lists where the keys are the set of values
%% associated with `Key' in each of the `Map's in `Maps'.
%%
%% This works like `group_unique_by/2' except it also accepts an sorting
%% function like `lists:sort/3'.
-spec group_unique_by([Map], Key, SorterFun) -> #{Value => Map} when
    Map :: #{Key => Value},
    SorterFun :: fun((A :: Map, B :: Map) -> boolean()).
group_unique_by(Maps, Key, SorterFun) when is_function(SorterFun, 2) ->
    map_values(group_by(Maps, Key), fun(_Key, Value) ->
        hd(lists:sort(SorterFun, Value))
    end).

%% @doc Returns a list of `Map's where all `Map's that have a `Key'
%% associated with the value ´Value' are not present.
-spec key_delete([Map], Key, Value) -> [Map] when Map :: #{Key => Value}.
key_delete(Maps, Key, Value) ->
    [
        Current
     || Current <- Maps,
        case Current of
            #{Key := CurrentValue} -> CurrentValue =/= Value;
            _Otherwise -> true
        end
    ].

%% @doc Returns the `Map' the has a `Key' associated with the value `Value'.
%% If no such `Map' can be found, it returns `false'.
-spec key_find([Map], Key, Value) -> Map | false when Map :: #{Key => Value}.
key_find([Map | _Maps], Key, Value) when map_get(Key, Map) == Value ->
    Map;
key_find([_Map | Maps], Key, Value) ->
    key_find(Maps, Key, Value);
key_find([], _Key, _Value) ->
    false.

%% @doc Returns the value associated with `Key' for each `Map' that contains
%% `Key'. Maps that are missing `Key' are discarded.
%%
%% This function does not have a corresponding function in `lists'.
key_get([Map | Maps], Key) when is_map_key(Key, Map) ->
    [maps:get(Key, Map) | key_get(Maps, Key)];
key_get([_Map | Maps], Key) ->
    key_get(Maps, Key);
key_get([], _Key) ->
    [].

%% @doc Like `key_get/2' except maps that are missing `Key' are replaced with
%% `Default'.
key_get([Map | Maps], Key, Default) when is_map(Map) ->
    [maps:get(Key, Map, Default) | key_get(Maps, Key, Default)];
key_get([_Map | Maps], Key, Default) ->
    key_get(Maps, Key, Default);
key_get([], _Key, _Default) ->
    [].

%% @doc Returns a list of `Map's where each `Map' that has a key `Key' have
%% been replaced with the result of calling `Fun' with said `Map'.
-spec key_map([Map], Key, Fun) -> [Map] when
    Map :: #{Key => _Value},
    Fun :: fun((Map) -> Map).
key_map([Map | Maps], Key, Fun) when is_map_key(Key, Map) ->
    [Fun(Map) | key_map(Maps, Key, Fun)];
key_map([Map | Maps], Key, Fun) ->
    [Map | key_map(Maps, Key, Fun)];
key_map(Maps, _Key, _Fun) ->
    Maps.

%% @doc Returns `true' if there is a `Map' that has a `Key' associated with
%% the value `Value', `false' otherwise.
key_member([Map | _Maps], Key, Value) when map_get(Key, Map) == Value -> true;
key_member([_Map | Maps], Key, Value) -> key_member(Maps, Key, Value);
key_member([], _Key, _Value) -> false.

%% @doc Similar to `lists:keymerge' except the lists does not need to be
%% sorted or duplicates removed before hand.
key_merge(Maps, Key, Defaults) ->
    key_merger(Maps, Key, Defaults, fun lists:keysort/2, fun lists:keymerge/3).

%% @doc Similar to `lists:ukeymerge' except the lists does not need to be
%% sorted or duplicates removed before hand.
key_unique_merge(Maps, Key, Defaults) ->
    key_merger(Maps, Key, Defaults, fun lists:ukeysort/2, fun lists:ukeymerge/3).

key_replace([Map | Maps], Key, Value, Replacement) when map_get(Key, Map) == Value ->
    [Replacement | Maps];
key_replace([Map | Maps], Key, Value, Replacement) ->
    [Map | key_replace(Maps, Key, Value, Replacement)];
key_replace([], _Key, _Value, _Replacement) ->
    [].

key_sort(Maps, Key) ->
    key_sorter(Maps, Key, fun lists:keysort/2).

key_unique_sort(Maps, Key) ->
    key_sorter(Maps, Key, fun lists:ukeysort/2).

key_store([Map | Maps], Key, Value, NewMap) when map_get(Key, Map) == Value ->
    [NewMap | Maps];
key_store([Map | Maps], Key, Value, NewMap) ->
    [Map | key_store(Maps, Key, Value, NewMap)];
key_store([], _Key, _Value, NewMap) ->
    [NewMap].

key_take([Map | Maps], Key, Value) when map_get(Key, Map) == Value ->
    {value, Map, Maps};
key_take([Map | Maps], Key, Value) ->
    case key_take(Maps, Key, Value) of
        {value, Found, Tail} -> {value, Found, [Map | Tail]};
        false -> false
    end;
key_take([], _Key, _Value) ->
    false.

%% @doc Returns the map transformed using the given function.
map(Map, Fun) when is_function(Fun, 2) andalso is_map(Map) ->
    maps:from_list([
        Fun(Key, Value)
     || {Key, Value} <- maps:to_list(Map)
    ]).

%% @doc Similar to `map_values/2', except over the map's keys.
map_keys(Map, Fun) when is_function(Fun, 2) andalso is_map(Map) ->
    maps:from_list([
        {Fun(Key, Value), Value}
     || {Key, Value} <- maps:to_list(Map)
    ]).

%% @doc Same as `maps:map/2'.
map_values(Map, Fun) when is_function(Fun, 2) andalso is_map(Map) ->
    maps:map(Fun, Map).

deep_map(Map, Fun) when is_function(Fun, 2) andalso is_map(Map) ->
    deep_filter_map(Map, fun(Key, Value) ->
        {true, Fun(Key, Value)}
    end).

deep_map_keys(Map, Fun) when is_function(Fun, 2) andalso is_map(Map) ->
    deep_map(Map, fun(Key, Value) ->
        {Fun(Key, Value), Value}
    end).

deep_map_values(Map, Fun) when is_function(Fun, 2) andalso is_map(Map) ->
    deep_map(Map, fun(Key, Value) ->
        {Key, Fun(Key, Value)}
    end).

deep_filter(Map, Fun) when is_function(Fun, 2) andalso is_map(Map) ->
    deep_filter_map(
        Map,
        fun(Key, Value) ->
            case Fun(Key, Value) of
                true -> {true, {Key, Value}};
                false -> false
            end
        end
    ).

deep_filter_map(Map, Fun) when is_function(Fun, 2) andalso is_map(Map) ->
    maps:from_list(
        lists:filtermap(
            fun
                ({Key, Value}) when is_map(Value) ->
                    Fun(Key, deep_filter_map(Value, Fun));
                ({Key, Value}) when is_list(Value) ->
                    Fun(Key, [
                        if
                            is_map(Inner) -> deep_filter_map(Inner, Fun);
                            true -> Inner
                        end
                     || Inner <- Value
                    ]);
                ({Key, Value}) ->
                    Fun(Key, Value)
            end,
            maps:to_list(Map)
        )
    ).

fold(Map, Init, Fun) when is_function(Fun, 3) andalso is_map(Map) ->
    maps:fold(Fun, Init, Map).

deep_fold(Map, Init, Fun) when is_function(Fun, 3) andalso is_map(Map) ->
    maps:fold(
        fun
            (Key, Value, Acc0) when is_map(Value) ->
                Acc1 = deep_fold(Value, Acc0, Fun),
                Fun(Key, Value, Acc1);
            (Key, Value, Acc0) ->
                Fun(Key, Value, Acc0)
        end,
        Init,
        Map
    ).

deep_flatten(Map) ->
    lists:reverse(deep_fold(Map, [], fun deep_flattener/3)).

deep_flattener(Key, Value, List) ->
    [{Key, Value} | List].

%% @doc Like `merge/2', merging each map in `Maps' left-to-right.
merge(Maps) when is_map(hd(Maps)) ->
    lists:foldl(fun(Next, Acc) -> merge(Acc, Next) end, #{}, Maps).

%% @doc Deeply merges two maps/lists.
%%
%% Like maps:merge, the value from the second map/list overrides the first.
%% Unlike maps:merge nested maps are merged in a similar fashion, allowing
%% partial updates.
%%
%% For lists, it compares the position of the elements in the two lists,
%% given precedence to the value in the second list. Again, merging rather
%% the out right overriding. This also works with uneven lists lengths.
%%
%% If either side is <code>&apos;_&apos;</code>, the underscore atom,
%% then the other side is chosen. This is to allow partial updates
%% inside lists.
merge('_', Value) ->
    Value;
merge(Value, '_') ->
    Value;
merge(Original, Updates) when is_map(Original) andalso is_map(Updates) ->
    maps:from_list([
        {Key,
            merge(
                maps:get(Key, Original, '_'),
                maps:get(Key, Updates, '_')
            )}
     || Key <- lists:umerge(
            %% Map keys are guaranteed to be unique
            lists:sort(maps:keys(Original)),
            lists:sort(maps:keys(Updates))
        )
    ]);
merge(Original, Updates) when is_list(Original) andalso is_list(Updates) ->
    [
        merge(Old, New)
     || {Old, New} <- zip(Original, Updates)
    ];
merge(_Original, Update) ->
    Update.

%% @doc Same as `maps:with', except it accepts the map as the first parameter,
%% like the other functions in `neo'.
-spec with(#{Key => _}, [Key]) -> #{Key := _}.
with(Map, Keys) ->
    maps:with(Keys, Map).

%% @doc Same as `maps:without', except it accepts the map as the first
%% parameter, like the other functions in `neo'.
-spec without(#{Key => _}, [Key]) -> map().
without(Map, Keys) ->
    maps:without(Keys, Map).

%%%_* Private functions ------------------------------------------------------
split_path_parts(Path) when is_binary(Path) ->
    binary:split(Path, <<".">>, [global]);
split_path_parts(Path) when is_atom(Path) ->
    BinaryPath = atom_to_binary(Path, utf8),
    [
        binary_to_atom(Part, utf8)
     || Part <- binary:split(BinaryPath, <<".">>, [global])
    ].

dget_internal(Value, []) -> Value;
dget_internal({error, notfound}, _) -> {error, notfound};
dget_internal({ok, null}, _) -> {error, notfound};
dget_internal({ok, Object}, [Key | Path]) -> dget_internal(get(Object, Key), Path).

dset_internal(_Map, [], Value) ->
    Value;
dset_internal(Object, [Key], Value) ->
    set(Object, Key, Value);
dset_internal(OuterObject, [Key | Path], Value) ->
    InnerObject = get(OuterObject, Key, #{}),
    set(OuterObject, Key, dset_internal(InnerObject, Path, Value)).

ddelete_internal(Map, [Key]) ->
    maps:remove(Key, Map);
ddelete_internal(OuterObject, [Key | Path]) ->
    case get(OuterObject, Key) of
        {ok, InnerObject} ->
            set(OuterObject, Key, ddelete_internal(InnerObject, Path));
        {error, notfound} ->
            OuterObject
    end.

-spec key_to_value_map_tuple_list([Map], Key) -> [{Value, Map}] when Map :: #{Key => Value}.
key_to_value_map_tuple_list(Maps, Key) ->
    [
        {Value, Map}
     || #{Key := Value} = Map <- Maps
    ].

key_merger(Maps, Key, Defaults, SorterFun, MergerFun) ->
    List = SorterFun(1, key_to_value_map_tuple_list(Maps, Key)),
    DefaultList = SorterFun(1, key_to_value_map_tuple_list(Defaults, Key)),
    [
        Map
     || {_Value, Map} <- MergerFun(1, List, DefaultList)
    ].

-spec key_sorter([Map], Key, fun((pos_integer(), TupleList) -> TupleList)) -> [Map] when
    Map :: #{Key => Value},
    TupleList :: [{Value, Map}].
key_sorter(Maps, Key, SorterFun) ->
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
                    neo_test_helpers:format(
                        "expected neo:key_to_value_map_tuple_list to return 2-tuples only, instead got ~W",
                        [Unknown, 10]
                    ),
                    [Maps, Key, SorterFun]
                )
        end
     || Tuple <- SorterFun(1, key_to_value_map_tuple_list(Maps, Key))
    ].

%% This is a copy of `lists:nth', but returning {ok, Value} | false instead.
-spec nth(pos_integer(), [A]) -> {ok, A} | false.
nth(1, [H | _]) ->
    {ok, H};
nth(N, [_ | T]) when N > 1 ->
    nth(N - 1, T);
nth(_N, []) ->
    false.

%% @doc Zips two lists of any length into one list of two-tuples.
%%
%% Unlike lists:zip, this accepts list of different lengths as well.
%% If so, then it sets the missing values to '_', the underscore atom.
-spec zip(A, B) -> [{A | '_', B | '_'}].
zip([], []) -> [];
zip([], [B | Bs]) -> [{'_', B} | zip([], Bs)];
zip([A | As], []) -> [{A, '_'} | zip(As, [])];
zip([A | As], [B | Bs]) -> [{A, B} | zip(As, Bs)].

%%%_* Tests ==================================================================
-ifdef(TEST).

-include_lib("eunit/include/eunit.hrl").
-include("neo_test_helpers.hrl").

-define(EON_MAP_EXAMPLES,
    [null] => null,
    [true] => true,
    [false] => false,
    ["char list"] => "char list",
    [<<"binary">>] => <<"binary">>,
    [123] => 123,
    [2.718] => 2.718,
    [[true]] => [true],
    [[{<<"single">>, property}]] =>
        #{<<"single">> => property},
    [
        [
            {<<"first">>, atom},
            {<<"second">>, "char list"},
            {<<"third">>, <<"binary">>}
        ]
    ] =>
        #{
            <<"first">> => atom,
            <<"second">> => "char list",
            <<"third">> => <<"binary">>
        },
    [[[{<<"first">>, object}], [{<<"second">>, object}]]] =>
        [#{<<"first">> => object}, #{<<"second">> => object}]
).

from_list_test_() ->
    ?function_test(
        from_list(Map),
        [Map],
        #{
            [[]] => #{},
            [#{}] => #{},
            ?EON_MAP_EXAMPLES
        }
    ).

to_list_test_() ->
    ?function_test(
        to_list(Map),
        [Map],
        maps:from_list([
            {[Map], Proplist}
         || {[Proplist], Map} <- maps:to_list(#{
                [[]] => [],
                ?EON_MAP_EXAMPLES
            })
        ])
    ).

get__test_() ->
    ?function_test(
        get_(Map, Key),
        [Map, Key],
        #{
            [#{key => value, unrelated => 123}, key] =>
                value,
            [[{key, value}, {unrelated, 123}], key] =>
                value,
            [[a, b, c], 2] =>
                b
        }
    ).

get_failure_test_() ->
    [
        ?_assertError({badkey, missing}, get_(#{key => value}, missing)),
        ?_assertError({badkey, missing}, get_([{key, value}], missing)),
        ?_assertError({badkey, 10}, get_([a, b, c], 10))
    ].

group_by_test_() ->
    ById = fun(#{id := Id}) -> {ok, Id} end,
    [?_assertError({assertEqual, _}, group_by([1, a, "c"], key))] ++
    ?function_test(
        group_by(Maps, Key),
        [Maps, Key],
        #{
            [[], key] =>
                #{},
            [[#{other => value}, #{key => abc}], key] =>
                #{
                    abc => [#{key => abc}]
                },
            [[#{key => 123, other => value}, #{key => abc}], key] =>
                #{
                    123 => [#{key => 123, other => value}],
                    abc => [#{key => abc}]
                },
            [[#{key => 123, other => value}, #{key => 123, foo => bar}], key] =>
                #{
                    123 => [
                        #{key => 123, foo => bar},
                        #{key => 123, other => value}
                    ]
                },
            [[#{id => 123, name => "Jane"}, #{id => 123, name => "John"}], ById] =>
                #{
                    123 => [
                        #{id => 123, name => "John"},
                        #{id => 123, name => "Jane"}
                    ]
                }
        }
    ).

group_unique_by_test_() ->
    ById = fun(#{id := Id}) -> {ok, Id} end,
    [?_assertError({assertEqual, _}, group_unique_by([1, a, "c"], key))] ++
    ?function_test(
        group_unique_by(Maps, Key),
        [Maps, Key],
        #{
            [[], key] =>
                #{},
            [[#{other => value}, #{key => abc}], key] =>
                #{
                    abc => #{key => abc}
                },
            [[#{key => 123, other => value}, #{key => abc}], key] =>
                #{
                    123 => #{key => 123, other => value},
                    abc => #{key => abc}
                },
            [[#{key => 123, other => value}, #{key => 123, foo => bar}], key] =>
                #{
                    123 => #{key => 123, foo => bar}
                },
            [[#{id => 123, name => "Jane"}, #{id => 123, name => "John"}], ById] =>
                #{
                    123 => #{id => 123, name => "Jane"}
                }
        }
    ).

key_replace_test_() ->
    ?function_test(
        key_replace(Maps, Key, Value, Target),
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
            [[#{key => target}, #{unrelated => 123}], key, target, #{replacement => map}] =>
                [#{replacement => map}, #{unrelated => 123}]
        }
    ).

key_delete_test_() ->
    ?function_test(
        key_delete(Maps, Key, Target),
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

key_find_test_() ->
    ?function_test(
        key_find(Maps, Key, Target),
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

dget_test_() ->
    [
        fun() ->
            Actual = dget(Object, Path),
            ?assertEqual(Expected, Actual)
        end
     || {Expected, Path, Object} <- [
            {{ok, <<"foo">>}, 'top.middle.bottom', #{
                top => #{
                    middle => #{
                        bottom => <<"foo">>
                    }
                }
            }},
            {{ok, 123}, [index, 1], #{
                index => [123, 456]
            }},
            {{ok, <<"Bosse">>}, [permissions, 2, <<"name">>], #{
                permissions => [
                    [
                        {<<"name">>, <<"Karin">>},
                        {<<"age">>, 45}
                    ],
                    [
                        {<<"name">>, <<"Bosse">>},
                        {<<"age">>, 56}
                    ]
                ]
            }},
            {{error, notfound}, <<"moose.sausage">>, #{}}
        ]
    ].

dget__test_() ->
    [
        fun() ->
            Actual = dget_(Object, Path),
            ?assertEqual(Expected, Actual)
        end
     || {Expected, Path, Object} <- [
            {<<"foo">>, 'top.middle.bottom', #{
                top => #{
                    middle => #{
                        bottom => <<"foo">>
                    }
                }
            }},
            {123, [index, 1], #{
                index => [123, 456]
            }},
            {<<"Bosse">>, [permissions, 2, <<"name">>], #{
                permissions => [
                    [
                        {<<"name">>, <<"Karin">>},
                        {<<"age">>, 45}
                    ],
                    [
                        {<<"name">>, <<"Bosse">>},
                        {<<"age">>, 56}
                    ]
                ]
            }}
        ]
    ].

zip_test_() ->
    [
        fun() ->
            Actual = zip(Left, Right),
            ?assertEqual(Expected, Actual)
        end
     || {Left, Right, Expected} <- [
            {[], [], []},
            {[a], [b], [{a, b}]},
            {[a], [], [{a, '_'}]},
            {[], [b], [{'_', b}]},
            {[1, 2, 3], [a, b], [{1, a}, {2, b}, {3, '_'}]},
            {[1, 2], [a, b, c, d], [{1, a}, {2, b}, {'_', c}, {'_', d}]}
        ]
    ].

merge_test_() ->
    [
        fun() ->
            Actual = merge(Left, Right),
            ?assertEqual(Expected, Actual)
        end
     || {Left, Right, Expected} <- [
            {[], [], []},
            {[old], [new], [new]},
            {[old], [], [old]},
            {[old], ['_'], [old]},
            {[], [new], [new]},
            {['_'], [new], [new]},
            {[], ['_'], ['_']},
            {['_'], ['_'], ['_']},
            {old, new, new},
            {old, '_', old},
            {'_', new, new},
            {1, 2, 2},
            {1, '_', 1},
            {[1, 2, 3], [a, b], [a, b, 3]},
            {[1, 2], [a, b, c], [a, b, c]},
            {#{key => old}, #{key => new}, #{key => new}},
            {#{key => old}, #{key => '_'}, #{key => old}},
            {#{nested => #{key => old}}, #{}, #{nested => #{key => old}}},
            {#{nested => #{key => old}}, #{nested => 123}, #{nested => 123}},
            {
                #{
                    nested => #{
                        overridden => hello,
                        kept => world
                    }
                },
                #{
                    nested => #{
                        overridden => holá,
                        added => 123
                    }
                },
                #{
                    nested => #{
                        overridden => holá,
                        kept => world,
                        added => 123
                    }
                }
            },
            {
                #{
                    list => [
                        #{key => old},
                        #{key => <<"binary">>}
                    ]
                },
                #{
                    list => [
                        #{key => new, other => value},
                        '_'
                    ]
                },
                #{
                    list => [
                        #{key => new, other => value},
                        #{key => <<"binary">>}
                    ]
                }
            }
        ]
    ].

merge_list_of_maps_test() ->
    Actual = merge([
        #{
            key => from_first
        },
        #{
            nested => #{
                overridden => from_second,
                other => from_second
            }
        },
        #{
            nested => #{
                overridden => from_third
            },
            <<"binary">> => from_third
        }
    ]),
    ?assertEqual(
        #{
            key => from_first,
            nested => #{
                overridden => from_third,
                other => from_second
            },
            <<"binary">> => from_third
        },
        Actual
    ).

deep_map_keys_test_() ->
    ?function_test(
        deep_map_keys(Map, Fun),
        [Map, Fun],
        #{
            [
                #{
                    <<"integer">> => 123,
                    <<"map">> => #{
                        <<"int">> => 456
                    },
                    <<"list">> => [
                        #{
                            <<"inner">> => 123
                        }
                    ]
                },
                fun(Key, _Value) -> binary_to_existing_atom(Key, utf8) end
            ] =>
                #{
                    integer => 123,
                    map => #{
                        int => 456
                    },
                    list => [
                        #{
                            inner => 123
                        }
                    ]
                }
        }
    ).

-endif.
