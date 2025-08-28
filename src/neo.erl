%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% @doc Convenience functions for working with (nested) maps, and lists of
%%% (nested) maps.
%%%
%%% Mimics the builtin `lists' and `maps' module, and is meant as a
%%% replacement for {@link eon}.
%%%
%%% There are two main differences to `lists' `key*' functions. First they
%%% are named using an underscore, `key_find' instead of `lists:keyfind'.
%%%
%%% Secondly they all take Maps as the first argument, and if appropriate
%%% Key as the second argument.
%%% @end
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%%%_* Module declaration ======================================================
-module(neo).
-compile({no_auto_import, [{get, 2}]}).

%%%_* Exports =================================================================
%%%_ * API --------------------------------------------------------------------

-export([
    dget/2,
    dget/3,
    dget_/2,
    delete/2,
    ddelete/2,
    dset/3,
    fold/3,
    from_list/1,
    from_list/2,
    get/2,
    get/3,
    get_/2,
    group_by/2,
    group_unique_by/2,
    group_unique_by/3,
    has/2,
    map/2,
    map_keys/2,
    map_values/2,
    mapfold/3,
    merge/1,
    merge/2,
    new/0,
    partition/2,
    pop/2,
    set/3,
    to_list/1,
    update_with/3,
    update_with/4,
    with/2,
    without/2
]).

-export([
    format_error/2
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
%% A key used in a {@link collection()} based on an {@link orddict} or {@link maps. map}.

-type proplist(A, B) :: [{A, B}].
%% An {@link proplists:unfold/1. unfolded} proplist. Can also be viewed as an
%% {@link orddict. unordered dictionary}.

-type proplist() :: proplist(key(), term()).
%% A {@link proplist()} from {@link key()} to any term.

-type collection(Key, Value) ::
    #{Key := Value | collection(Key, Value)}
    | proplist(Key, Value | collection(Key, Value))
    | [Value | collection(Key, Value)].
%% Either an {@link orddict}, {@link maps. map}, or plain list. Each may be
%% recursive to allow for deeply nested structures.
%%
%% @see dget/2
%% @see dset/3

-type collection() :: collection(key(), term()).
%% A {@link collection()} from {@link key()} to any term.

%%%_* Macros ==================================================================
-define(is_key(Key), (is_atom(Key) orelse is_binary(Key))).

-define(is_ordset(Object),
    (length(Object) =:= 0 orelse
        (tuple_size(hd(Object)) =:= 2 andalso
            ?is_key(element(1, hd(Object)))))
).

-define(raiseBadkey(Lookup, Arguments),
    error(badkey, Arguments, [{error_info, #{}}])
).

%%%_* Code ====================================================================
%%%_ * API --------------------------------------------------------------------

%% @doc Same as {@link from_list/2}, but empty lists, `[]', are converted to
%% empty maps, `#{}', .
-spec from_list(proplist(A, B)) -> #{A := B}.
from_list(Value) ->
    from_list(Value, #{substitutions => #{[] => #{}}}).

%% @doc Returns the given list of key-value pairs as a map.
%%
%% The values may also be lists, or native maps, of nested key-value pairs. All
%% will be converted to native maps. You can view it as {@link maps:from_list/1}
%% recursive cousin.
%%
%% You may also supply an options map with a `substitutions' map for replacing
%% specific values while converting. Instead of using a `substitutions' map,
%% or in conjuction with one, you can supply a `transformations' map with
%% `fun's to be called for specific keys.
%%
%% This way you can easily change the default behaviour of converting empty
%% lists to empty maps by supplying a different (or no) `substitutions' map.
%%
%% You can also use this to preserve some subtree for being converted, or
%% apply additional transformations. However, do note that the substitutions
%% and transformations are applied on all levels. This means that if you given
%% it an options map like this `#{transformations => #{user => fun ...}}', you
%% will transform <em>all</em> `user' objects, on <em>any</em> level.
-spec from_list(CollectionIn, Options) -> CollectionOut when
    CollectionIn :: neo_collection:t(Key, ValueIn),
    Options :: #{
        substitutions => #{Key := ValueOut},
        transformations => #{Key := fun((ValueIn) -> ValueOut)}
    },
    CollectionOut :: neo_collection:t(Key, ValueIn | ValueOut).
from_list(Value, #{substitutions := Substitutions}) when
    is_map_key(Value, Substitutions)
->
    maps:get(Value, Substitutions);
from_list(List, Options) when is_list(List) andalso is_map(Options) ->
    case neo_lists:typeof(List) of
        orddict -> from_list_internal(List, Options);
        _ -> [from_list(Element, Options) || Element <- List]
    end;
from_list(CollectionOrValue, Options) when is_map(Options) ->
    case neo_reflect:has_implementation(CollectionOrValue, [neo_collection]) of
        true -> from_list_internal(CollectionOrValue, Options);
        false -> CollectionOrValue
    end.

from_list_internal(Collection, Options) when is_map(Options) ->
    Transformations = maps:get(transformations, Options, #{}),
    neo_collection:to(Collection, maps, fun
        (Key, Value) when is_function(map_get(Key, Transformations), 1) ->
            Transformer = maps:get(Key, Transformations),
            {Key, Transformer(Value)};
        (Key, Value) ->
            {Key, from_list(Value, Options)}
    end).

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

-compile({inline, new/0}).

%% @doc Creates a new map, for compatibility with {@link eon}.
new() -> #{}.

%% @doc Returns `true' if the given `Collection' contains the given `Lookup'.
-spec has(Collection, Lookup) -> boolean() when
    Collection :: collection(Key, Value),
    Lookup :: Key | pos_integer(),
    Key :: key(),
    Value :: any().
has(Collection, Key) ->
    neo_collection:has(Collection, Key).

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
get(Collection, Lookup) ->
    neo_collection:fetch(Collection, Lookup).

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
        {error, notfound} -> ?raiseBadkey(Lookup, [Collection, Lookup])
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
    neo_collection:get(Collection, Lookup, Default).

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
    neo_deep:get(Collection, split_path_parts(Lookup)).

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
dget(Map, Path) ->
    neo_deep:fetch(Map, split_path_parts(Path)).

%% @doc Like `dget/2' expect it also accepts an `Default' value which is
%% returned if any of the keys/indexes are not found.
-spec dget(Collection, Lookup, Default) -> Value | Default when
    Collection :: collection(Key, Value),
    Lookup :: DottedPath | [Key | pos_integer()],
    Key :: key(),
    DottedPath :: key(),
    Value :: term().
dget(Collection, Lookup, Default) ->
    neo_deep:get(Collection, split_path_parts(Lookup), Default).

%% @doc Sets the given `Value' in the given collection as appropriate.
%% Turns a proplist into an orddict, i.e. a proplist sorted by keys.
-spec set(Collection, Lookup, Value) -> Collection when
    Collection :: collection(Key, Value),
    Lookup :: Key | pos_integer(),
    Key :: key(),
    Value :: term().
set(Map, Key, Value) when is_map(Map) ->
    Map#{Key => Value};
set(Collection, Key, Value) ->
    neo_collection:set(Collection, Key, Value).

%% @doc Like `set/3', except it accepts either a dot separated path in a
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
    Map#{Key => Value};
dset(Collection, Path, Value) ->
    neo_deep:set(Collection, split_path_parts(Path), Value).

%% @doc Updates the `Key' in `Collection' using `Fun', or fails with
%% `{badkey, Lookup}' if `Collection' does not have an association for `Key'.
update_with(Map, Key, Fun) when is_map_key(Key, Map) andalso is_function(Fun, 1) ->
    maps:update_with(Key, Fun, Map);
update_with(Map, Key, Fun) when is_map(Map) andalso is_function(Fun, 1) ->
    ?raiseBadkey(Key, [Map, Key, Fun]);
update_with(List, Key, Fun) when is_list(List) andalso is_function(Fun, 1) ->
    case neo_lists:typeof(List) of
        orddict ->
            case orddict:is_key(Key, List) of
                true -> orddict:update(Key, Fun, List);
                false -> ?raiseBadkey(Key, [List, Key, Fun])
            end;
        _ ->
            update_with_internal(List, Key, Fun)
    end;
update_with(Collection, Key, Fun) when is_function(Fun, 1) ->
    update_with_internal(Collection, Key, Fun).

update_with_internal(Collection, Key, Fun) when is_function(Fun, 1) ->
    case neo_collection:has(Collection, Key) of
        true ->
            Value = neo_collection:get(Collection, Key),
            neo_collection:set(Collection, Key, Fun(Value));
        false ->
            ?raiseBadkey(Key, [Collection, Key, Fun])
    end.

%% @doc Updates the `Key' in `Collection' using `Fun', or sets it to `Default'
%% if `Collection' does not have an association for `Key'.
update_with(Map, Key, Default, Fun) when is_map(Map) andalso is_function(Fun, 1) ->
    maps:update_with(Key, Fun, Default, Map);
update_with(List, Key, Default, Fun) when is_list(List) andalso is_function(Fun, 1) ->
    case neo_lists:typeof(List) of
        orddict ->
            orddict:update(Key, Fun, Default, List);
        _ ->
            update_with_internal(List, Key, Default, Fun)
    end;
update_with(Collection, Key, Default, Fun) when is_function(Fun, 1) ->
    update_with_internal(Collection, Key, Default, Fun).

update_with_internal(Collection, Key, Default, Fun) when is_function(Fun, 1) ->
    case neo_collection:has(Collection, Key) of
        true ->
            Value = neo_collection:get(Collection, Key),
            set(Collection, Key, Fun(Value));
        false ->
            set(Collection, Key, Default)
    end.

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

ddelete_internal(Map, [Key]) ->
    maps:remove(Key, Map);
ddelete_internal(OuterObject, [Key | Path]) ->
    case get(OuterObject, Key) of
        {ok, InnerObject} ->
            set(OuterObject, Key, ddelete_internal(InnerObject, Path));
        {error, notfound} ->
            OuterObject
    end.

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
%% function like `lists:sort/2'.
-spec group_unique_by([Map], Key, SorterFun) -> #{Value => Map} when
    Map :: #{Key => Value},
    SorterFun :: fun((A :: Map, B :: Map) -> boolean()).
group_unique_by(Maps, Key, SorterFun) when is_function(SorterFun, 2) ->
    map_values(group_by(Maps, Key), fun(_Key, Value) ->
        hd(lists:sort(SorterFun, Value))
    end).

%% @doc Returns the value associated with `Key' for each `Map' that contains
%% `Key'. Maps that are missing `Key' are discarded.
%%
%% This function does not have a corresponding function in `lists'.

%% @doc Returns a list of `Map's where each `Map' that has a key `Key' have
%% been replaced with the result of calling `Fun' with said `Map'.

%% @doc Returns the map transformed using the given function.
%%
%% Unlike {@link maps:map/2}, this allows for changing the key as well as the
%% value.
-spec map(CollectionIn, Mapper) -> CollectionOut when
    CollectionIn :: neo_collection:t(KeyIn, ValueIn),
    CollectionOut :: neo_collection:t(KeyOut, ValueOut),
    Mapper :: neo_stream:mapper(KeyIn, ValueIn, KeyOut, ValueOut).
map(Collection, Mapper) when is_function(Mapper) ->
    neo_collection:to(Collection, Collection, Mapper).

%% @doc Similar to `map_values/2', except over the map's keys.
-spec map_keys(CollectionIn, Mapper) -> CollectionOut when
    CollectionIn :: neo_collection:t(KeyIn, Value),
    CollectionOut :: neo_collection:t(KeyOut, Value),
    Mapper :: neo_stream:mapper(KeyIn, Value, KeyOut, Value).
map_keys(Collection, Mapper) when is_function(Mapper) ->
    neo_collection:to(Collection, Collection, fun(Key, Value) ->
        {Mapper(Key, Value), Value}
    end).

%% @doc Same as `maps:map/2'.
-spec map_values(CollectionIn, Mapper) -> CollectionOut when
    CollectionIn :: neo_collection:t(Key, InputValue),
    CollectionOut :: neo_collection:t(Key, OutputValue),
    Mapper :: neo_stream:mapper(Key, InputValue, Key, OutputValue).
map_values(Collection, Mapper) when is_function(Mapper) ->
    neo_collection:to(Collection, Collection, fun(Key, Value) ->
        {Key, Mapper(Key, Value)}
    end).

%% @doc Like {@link maps:fold/3} or {@link lists:foldl/3}
fold(Map, InitialAccumulator, Folder) when is_map(Map) andalso is_function(Folder, 3) ->
    maps:fold(
        fun(Key, Value, Accumulator) ->
            Folder(Accumulator, Key, Value)
        end,
        InitialAccumulator,
        Map
    );
fold(Collection, InitialAccumulator, Folder) when is_function(Folder, 3) ->
    neo_iterable:fold(Collection, InitialAccumulator, Folder).

%% @doc Like {@link lists:mapfoldl/3}, except it works on `maps' and `orddicts'.
%%
%% If `Fun' has arity 2 this becomes equivalent to {@link lists:mapfoldl/3}
%% over a plain list, or if given a {@link maps. map} over the results of
%% {@link maps:to_list/1}.
%%
%% If `Fun' has arity 3 then this becomes more similar to {@link maps:fold/3},
%% where the `Fun' takes the `Key' as the first parameter. For plain lists,
%% which has no explicit keys, this will use the elements index as the key.
-spec mapfold(Collection, Init, Fun) -> Result when
    Collection :: collection(InputKey, InputValue),
    Init :: term(),
    Fun :: KeyValueFun | ValueFun,
    KeyValueFun :: fun((InputKey, InputValue, Accumulator) -> FunReturn),
    ValueFun :: fun((InputValue, Accumulator) -> FunReturn),
    FunReturn :: {OutputKey, OutputValue, Accumulator} | {OutputValue, Accumulator},
    Result :: {collection(OutputKey, OutputValue), Accumulator}.
mapfold(Map, Init, Fun) when is_function(Fun, 3) andalso is_map(Map) ->
    maps:fold(
        fun(Key, Value0, {OutputMap, Accumulator0}) ->
            case Fun(Key, Value0, Accumulator0) of
                {Value1, Accumulator1} ->
                    {OutputMap#{Key => Value1}, Accumulator1};
                {NewKey, Value1, Accumulator1} ->
                    {OutputMap#{NewKey => Value1}, Accumulator1}
            end
        end,
        {#{}, Init},
        Map
    );
mapfold(Object, Init, Fun) when is_function(Fun, 3) andalso ?is_ordset(Object) ->
    lists:mapfoldl(
        fun({Key, Value0}, Accumulator0) ->
            case Fun(Key, Value0, Accumulator0) of
                {Value1, Accumulator1} ->
                    {{Key, Value1}, Accumulator1};
                {NewKey, Value1, Accumulator1} ->
                    {{NewKey, Value1}, Accumulator1}
            end
        end,
        Init,
        Object
    );
mapfold(List0, Init, Fun) when is_function(Fun, 3) andalso is_list(List0) ->
    {List1, {_LastIndex, Accumulator2}} = lists:mapfoldl(
        fun(Element0, {Index, Accumulator0}) ->
            {Element1, Accumulator1} = Fun(Index, Element0, Accumulator0),
            {Element1, {Index + 1, Accumulator1}}
        end,
        {1, Init},
        List0
    ),
    {List1, Accumulator2};
mapfold(Map, Init, Fun) when is_function(Fun, 2) andalso is_map(Map) ->
    maps:fold(
        fun(Key, Value, Accumulator) ->
            Fun({Key, Value}, Accumulator)
        end,
        Init,
        Map
    );
mapfold(List, Init, Fun) when is_function(Fun, 2) andalso is_list(List) ->
    lists:mapfoldl(Fun, Init, List).

%% @doc Like `merge/2', merging each map in `Maps' left-to-right.
-spec merge([neo_collection:t(Key, Value)]) -> #{Key := Value}.
merge(List) when is_list(List) ->
    lists:foldl(fun(Next, Map) -> merge(Map, Next) end, #{}, List).

%% @doc Deeply merges two maps/lists.
%%
%% Like `maps:merge/2', the value from the second map/list overrides the first.
%% Unlike `maps:merge/2', this merges nested collections in a similar fashion,
%% allowing partial updates.
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
merge(Original, Updates) when is_list(Original) andalso is_list(Updates) ->
    [
        merge(Old, New)
     || {Old, New} <- zip(Original, Updates)
    ];
merge(Original, Updates) ->
    New =
        case
            neo_reflect:has_implementation(Original, [neo_collection]) andalso
                neo_reflect:has_implementation(Updates, [neo_collection])
        of
            true ->
                neo_collection:merge_with(Original, Updates, fun merge_internal/3);
            false ->
                Updates
        end,
    case is_proplist(Original) orelse is_proplist(Updates) of
        true -> proplists:compact(New);
        false -> New
    end.

merge_internal(_, '_', Value) ->
    Value;
merge_internal(_, Value, '_') ->
    Value;
merge_internal(_, Left, Right) ->
    case
        neo_reflect:has_implementation(Left, [neo_collection]) andalso
            neo_reflect:has_implementation(Right, [neo_collection])
    of
        true ->
            merge(Left, Right);
        false ->
            Right
    end.

%% @doc Same as `maps:with', except it accepts the map as the first parameter,
%% like the other functions in `neo'.
-spec with(#{Key => _}, [Key]) -> #{Key := _}.
with(Collection, Keys) ->
    neo_collection:with(Collection, Keys).

%% @doc Same as `maps:without', except it accepts the map as the first
%% parameter, like the other functions in `neo'.
-spec without(#{Key => _}, [Key]) -> map().
without(Collection, Keys) ->
    neo_collection:without(Collection, Keys).

%% @doc Partitions the given collection into two, where the first contains all
%% elements for which `Predicate' returns `true', and the second contains all
%% elements for which `Predicate' returns `false'.
partition(Map, Predicate) when is_map(Map) andalso is_function(Predicate, 2) ->
    maps:fold(
        fun(Key, Value, {True, False}) ->
            case Predicate(Key, Value) of
                true -> {True#{Key => Value}, False};
                false -> {True, False#{Key => Value}}
            end
        end,
        {#{}, #{}},
        Map
    );
partition(Object, Predicate) when
    ?is_ordset(Object) andalso is_function(Predicate, 2)
->
    lists:partition(fun({Key, Value}) -> Predicate(Key, Value) end, Object);
partition(List, Predicate) when is_list(List) andalso is_function(Predicate, 1) ->
    lists:partition(Predicate, List).

%% @doc Callback for extended error information
%%
%% See https://www.erlang.org/eeps/eep-0054.html
-spec format_error(Reason, StackTrace) -> ErrorMap when
    Reason :: term(),
    StackTrace :: erlang:stacktrace(),
    ErrorMap :: #{pos_integer() => unicode:chardata()}.
format_error(badkey, [{?MODULE, _Function, [Collection | _Arguments], _Info} | _]) ->
    CollectionType =
        if
            is_map(Collection) -> <<"map">>;
            ?is_ordset(Collection) -> <<"ordset">>;
            is_list(Collection) -> <<"list">>
        end,
    #{
        1 => <<"not present in ", CollectionType/binary>>
    };
format_error(badkey, [{_Moduke, _Function, _Arguments, _Info} | _]) ->
    %% Boilerplate for future expansion, also see erl_stdlib_errors' implementation.
    %% ErrorInfoMap = proplists:get_value(error_info, Info, #{}),
    %% Cause = maps:get(cause, ErrorInfoMap, none),
    #{}.

%%%_* Private functions ------------------------------------------------------
split_path_parts(Path) when is_list(Path) ->
    Path;
split_path_parts(Path) when is_binary(Path) ->
    binary:split(Path, <<".">>, [global]);
split_path_parts(Path) when is_atom(Path) ->
    BinaryPath = atom_to_binary(Path, utf8),
    [
        binary_to_atom(Part, utf8)
     || Part <- binary:split(BinaryPath, <<".">>, [global])
    ].

is_proplist(List) when is_list(List) ->
    neo_lists:typeof(List) =:= proplist;
is_proplist(_) ->
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
-include("test_helpers.hrl").

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

app_version_in_sync_test_() ->
    neo_test_helpers:test_case(#{
        setup => fun() ->
            application:load(neo)
        end,
        tests => #{
            "with the latest git tag" => fun() ->
                Applications = application:loaded_applications(),
                {neo, _Description, Version} = lists:keyfind(neo, 1, Applications),
                GitVersion = ?cmd("git tag --list --sort=-version:refname | head -n1"),
                ?assertEqual(
                    GitVersion,
                    Version ++ "\n",
                    "the latest git tag must match the version in src/neo.app.src"
                )
            end,
            "with the README" => fun() ->
                Applications = application:loaded_applications(),
                {neo, _Description, Version} = lists:keyfind(neo, 1, Applications),
                {ok, Readme} = file:read_file(
                    filename:join(filename:dirname(?FILE), "../README.md")
                ),
                Result = re:run(
                    Readme,
                    "{neo, {git, \"git@github.com:kivra/neo.git\", {tag, \"((?:\\d+\\.){2}\\d)\"}}}",
                    [{capture, all_but_first, list}]
                ),
                ?assertNotEqual(
                    nomatch,
                    Result,
                    "README.md must contain an example of using neo with rebar3 as a git dependency"
                ),
                ?assertMatch(
                    {match, [Version]},
                    Result,
                    "the version in README.md must match the one in src/neo.app.src"
                )
            end
        }
    }).

from_list_test_() ->
    ?function_test(
        from_list(Map),
        [Map],
        #{
            [[]] => #{},
            [#{}] => #{},
            [[{<<"items">>, #{0 => [{<<"plan">>, <<"kivra-scanning-regular">>}]}}]] =>
                #{
                    <<"items">> => #{
                        0 => #{
                            <<"plan">> => <<"kivra-scanning-regular">>
                        }
                    }
                },
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
        ?_assertError(badkey, get_(#{key => value}, missing)),
        ?_assertError(badkey, get_([{key, value}], missing)),
        ?_assertError(badkey, get_([a, b, c], 10))
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
                        {<<"age">>, 45},
                        {<<"name">>, <<"Karin">>}
                    ],
                    [
                        {<<"age">>, 56},
                        {<<"name">>, <<"Bosse">>}
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
                        {<<"age">>, 45},
                        {<<"name">>, <<"Karin">>}
                    ],
                    [
                        {<<"age">>, 56},
                        {<<"name">>, <<"Bosse">>}
                    ]
                ]
            }}
        ]
    ].

set_test_() ->
    ?function_test(
        set(Object, Key, Value),
        [Object, Key, Value],
        #{
            [#{}, key, target] =>
                #{key => target},
            [#{key => value}, key, target] =>
                #{key => target},
            [[], 1, target] =>
                [target],
            [[value], 1, target] =>
                [target]
        }
    ).

dset_test_() ->
    ?function_test(
        dset(Object, Path, Value),
        [Object, Path, Value],
        #{
            [#{}, [key], target] =>
                #{key => target},
            [#{key => value}, [key], target] =>
                #{key => target},
            [[], [1], target] =>
                [target],
            [[value], [1], target] =>
                [target],
            [#{}, [top, 1], target] =>
                #{top => [target]},
            [#{}, [top, 1, key], target] =>
                #{top => [#{key => target}]}
        }
    ).

fold_test_() ->
    Sum = fun(Sum, _Key, Value) -> Value + Sum end,
    ?function_test(
        fold(Collection, Init, Sum),
        [Collection, Init, Sum],
        #{
            [#{a => 1, b => 2, c => 3}, 0, Sum] => 6,
            [[{a, 1}, {b, 2}, {c, 3}], 0, Sum] => 6
        }
    ).

-define(mapfold_test(Collection, Init, Fun, Expected),
    {
        neo_test_helpers:flat_format("mapfold(~p, ~p, ~s)", [Collection, Init, ??Fun]),
        fun() ->
            ?assertEqual(Expected, mapfold(Collection, Init, Fun))
        end
    }
).
mapfold_test_() ->
    Map = #{a => 1, b => 2, c => 3},
    Object = lists:sort(maps:to_list(Map)),
    List = [1, 2, 3],
    [
        ?mapfold_test(List, 0, fun mapfold_sum/2, {[2, 4, 6], 6}),
        ?mapfold_test(List, 0, fun mapfold_sum/3, {[2, 4, 6], 6}),
        ?mapfold_test(Map, 0, fun mapfold_sum/3, {#{a => 2, b => 4, c => 6}, 6}),
        ?mapfold_test(Map, '_', fun mapfold_invert/3, {#{1 => a, 2 => b, 3 => c}, '_'}),
        ?mapfold_test(Object, 0, fun mapfold_sum/3, {[{a, 2}, {b, 4}, {c, 6}], 6}),
        ?mapfold_test(Object, '_', fun mapfold_invert/3, {[{1, a}, {2, b}, {3, c}], '_'})
    ].

mapfold_sum(X, Sum) -> {X * 2, X + Sum}.
mapfold_sum(_, X, Sum) -> {X * 2, X + Sum}.
mapfold_invert(Key, X, _) -> {X, Key, '_'}.

zip_test_() ->
    ?function_test(
        zip(Left, Right),
        [Left, Right],
        #{
            [[], []] => [],
            [[a], [b]] => [{a, b}],
            [[a], []] => [{a, '_'}],
            [[], [b]] => [{'_', b}],
            [[1, 2, 3], [a, b]] => [{1, a}, {2, b}, {3, '_'}],
            [[1, 2], [a, b, c, d]] => [{1, a}, {2, b}, {'_', c}, {'_', d}]
        }
    ).

merge_test_() ->
    ?function_test(
        merge(Left, Right),
        [Left, Right],
        #{
            [[], []] => [],
            [[old], [new]] => [new],
            [[old], []] => [old],
            [[old], ['_']] => [old],
            [[], [new]] => [new],
            [['_'], [new]] => [new],
            [[], ['_']] => ['_'],
            [['_'], ['_']] => ['_'],
            [old, new] => new,
            [old, '_'] => old,
            ['_', new] => new,
            [1, 2] => 2,
            [1, '_'] => 1,
            [[1, 2, 3], [a, b]] => [a, b, 3],
            [[1, 2], [a, b, c]] => [a, b, c],
            [#{key => old}, #{key => new}] => #{key => new},
            [#{key => old}, #{key => '_'}] => #{key => old},
            [#{nested => #{key => old}}, #{}] => #{nested => #{key => old}},
            [#{nested => #{key => old}}, #{nested => 123}] => #{nested => 123},
            [
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
                }
            ] =>
                #{
                    nested => #{
                        overridden => holá,
                        kept => world,
                        added => 123
                    }
                },
            [
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
                }
            ] =>
                #{
                    list => [
                        #{key => new, other => value},
                        #{key => <<"binary">>}
                    ]
                }
        }
    ).

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

update_with_test_() ->
    Fun = fun(N) -> N * 2 end,
    ?function_test(
        update_with(Map, Key, Fun),
        [Map, Key],
        #{
            [#{key => 1}, key] => #{key => 2},
            [#{a => 1, b => 1}, a] => #{a => 2, b => 1},
            [[{key, 1}], key] => [{key, 2}],
            [[{a, 1}, {b, 2}], a] => [{a, 2}, {b, 2}],
            [[1], 1] => [2],
            [[1, 2, 3], 2] => [1, 4, 3],
            [[{<<"abc">>, 2}, {<<"xyz">>, 1}], <<"abc">>] => [
                {<<"abc">>, 4}, {<<"xyz">>, 1}
            ]
        }
    ).

update_with_failure_test_() ->
    Fun = fun(N) -> N * 2 end,
    [
        ?_assertError(badkey, update_with(#{}, key, Fun)),
        ?_assertError(badkey, update_with(#{a => 1}, key, Fun)),
        ?_assertError(badkey, update_with([], key, Fun)),
        ?_assertError(badkey, update_with([{a, 1}], key, Fun)),
        ?_assertError(badkey, update_with([], 10, Fun)),
        ?_assertError(badkey, update_with([1, 2, 3], 10, Fun))
    ].

-endif.
