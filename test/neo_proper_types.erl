%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% @doc Common PropEr types used in the tests.
%%% @end
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%%%_* Module declaration =====================================================
-module(neo_proper_types).

%%%_* Exports ================================================================
%%%_ * API -------------------------------------------------------------------
-export([
    container_of_containers_type/1,
    container_record_type/1,
    container_type/0,
    container_type/1,
    container_with_key_type/0,
    container_with_key_type/1,
    container_with_missing_key_type/1,
    container_with_missing_key_type/2,
    container_with_missing_settable_key_type/2,
    key_type/0,
    orddict_type/0,
    orddict_type/2,
    value_type/0
]).

-export([
    new_container/2
]).

-export([
    format/2,
    smoke/0
]).

%%%_* Types ------------------------------------------------------------------

%%%_* Includes ===============================================================
-include("internal.hrl").
-include("records.hrl").
-include("test_helpers.hrl").
-include_lib("proper/include/proper.hrl").
-include_lib("eunit/include/eunit.hrl").

%%%_* Macros =================================================================
-define(ERL_FMT_ANNO, #{
    location => {0, 0},
    end_location => {0, 0}
    %% inner_location => _ %% Optional
    %% text => _ %% Optional
}).

%%%_* Types ==================================================================

-type function_reference() :: atom() | function().

%%%_* Code ===================================================================
smoke() ->
    Container0 = #container{
        module = maps,
        type = maps,
        orddict = [{<<>>, [0]}],
        collection = #{<<>> => [0]}
    },
    ?var(Container0),
    Tree0 = abstract(Container0),
    Source0 = erl_pp:expr(Tree0, [{linewidth, 1000}]),
    Source1 = unicode:characters_to_list(Source0),
    {ok, Nodes, _} = erlfmt:read_nodes_string("nofile", Source1),
    Algebra = lists:map(fun erlfmt_format:to_algebra/1, Nodes),
    io:format("~s\n", [erlfmt_algebra:format(hd(Algebra), 120)]),
    ok.

abstract(Function) when is_function(Function) ->
    {name, Name} = erlang:fun_info(Function, name),
    {arity, Arity} = erlang:fun_info(Function, arity),
    case erlang:fun_info(Function, type) of
        {type, external} ->
            {module, Module} = erlang:fun_info(Function, module),
            {'fun', ?ERL_FMT_ANNO,
                {function, {atom, ?ERL_FMT_ANNO, Module}, {atom, ?ERL_FMT_ANNO, Name},
                    {integer, ?ERL_FMT_ANNO, Arity}}};
        {type, local} ->
            {'fun', ?ERL_FMT_ANNO, {function, Name, Arity}}
    end;
abstract(Tuple) when is_tuple(Tuple) ->
    {tuple, ?ERL_FMT_ANNO, lists:map(fun abstract/1, tuple_to_list(Tuple))};
abstract(List) when is_list(List) ->
    %% TODO: handle unicode strings, aka case unicode:printable of ...
    lists:foldl(
        fun(Term, ListNode) ->
            {cons, ?ERL_FMT_ANNO, abstract(Term), ListNode}
        end,
        {nil, ?ERL_FMT_ANNO},
        List
    );
abstract(Map) when is_map(Map) ->
    {map, ?ERL_FMT_ANNO,
        maps:fold(
            fun(Key, Value, Fields) ->
                Node = {map_field_assoc, ?ERL_FMT_ANNO, abstract(Key), abstract(Value)},
                [Node | Fields]
            end,
            [],
            Map
        )};
abstract(Value) ->
    Node0 = erl_syntax:abstract(Value),
    Node1 = erl_syntax:set_pos(Node0, ?ERL_FMT_ANNO),
    erl_syntax:revert(Node1).

format(
    #container{
        module = Module,
        type = Type,
        orddict = Orddict,
        collection = Collection
        %% The rest are function references
    },
    Options0
) ->
    Options1 = Options0#{indent_level => 2},
    io_lib:format(
        "#~scontainer~s{\n"
        "    ~stype~s/~smodule~s = ~s~p~s/~s~p~s,\n"
        "    ~sorddict~s = ~s,\n"
        "    ~scollection~s = ~s,\n"
        %% Dim comments
        "    \e[2m%% The rest are function references\e[0m\n"
        "}",
        [
            ?MODULE_RECORD_TAG_COLOR(Options1),
            ?RESET(Options1),
            ?RECORD_FIELD_COLOR(Options1),
            ?RESET(Options1),
            ?RECORD_FIELD_COLOR(Options1),
            ?RESET(Options1),
            ?ATOM_NUMBER_COLOR(Options1),
            Module,
            ?RESET(Options1),
            ?ATOM_NUMBER_COLOR(Options1),
            Type,
            ?RESET(Options1),
            ?RECORD_FIELD_COLOR(Options1),
            ?RESET(Options1),
            neo_test_helpers:format(Orddict, Options1),
            ?RECORD_FIELD_COLOR(Options1),
            ?RESET(Options1),
            neo_test_helpers:format(Collection, Options1)
        ]
    ).

new_container(Type, Properties) when is_atom(Type) andalso is_map(Properties) ->
    Lookup = maps:from_list([
        {Field, Index}
     || {Index, Field} <- lists:enumerate(2, record_info(fields, container))
    ]),
    Container0 = new_uninitialized_container(Type),
    Container1 = maps:fold(
        fun(Key, Value, Container) ->
            Index = maps:get(Key, Lookup),
            setelement(Index, Container, Value)
        end,
        Container0,
        Properties
    ),
    initialize_container(Container1).

%%%_ * Types -----------------------------------------------------------------

container_with_key_type() ->
    container_with_key_type([]).

container_with_key_type(Options) ->
    ?LET(
        #container{
            module = Module,
            orddict = Orddict,
            collection = Collection,
            keys = Keys
        } = Container,
        container_type([non_empty | Options]),
        case Module of
            array ->
                Array = proper_symb:eval(Collection),
                Indices = orddict:fetch_keys(array:sparse_to_orddict(Array)),
                {Container, oneof(Indices)};
            lists ->
                {Container, integer(1, length(Orddict))};
            _ when ?is_tuple_type(Container) ->
                {Container, integer(1, length(Orddict))};
            _ ->
                {Container, oneof(Keys(proper_symb:eval(Collection)))}
        end
    ).

container_with_missing_key_type(Sentinel) when is_reference(Sentinel) ->
    container_with_missing_key_type(Sentinel, []).

container_with_missing_key_type(Sentinel, Options) when is_reference(Sentinel) ->
    ?LET(
        #container{
            module = Module,
            collection = Collection,
            size = Size
        } = Container,
        container_type(Options),
        case Module of
            proplists ->
                {Container, return(missing_key)};
            array ->
                {Container, Size(proper_symb:eval(Collection)) + 1};
            lists ->
                {Container, return(0)};
            _ when ?is_tuple_type(Container) ->
                {Container, return(0)};
            _ ->
                {Container, return(Sentinel)}
        end
    ).

container_with_missing_settable_key_type(Sentinel, Options) when
    is_reference(Sentinel)
->
    ?LET(
        #container{
            module = Module,
            collection = Collection,
            size = Size
        } = Container,
        container_type(Options),
        case Module of
            proplists ->
                {Container, return(missing_key)};
            array ->
                {Container, Size(proper_symb:eval(Collection))};
            lists ->
                {Container, Size(Collection) + 1};
            _ when ?is_tuple_type(Container) ->
                {Container, Size(Collection) + 1};
            _ ->
                {Container, return(Sentinel)}
        end
    ).

container_of_containers_type(Options) ->
    container_type([
        {orddict, orddict_type(key_type(), container_type(Options))} | Options
    ]).

container_type() ->
    container_type([]).

container_type(Options) ->
    ?LET(
        Container,
        container_record_type(Options),
        initialize_container(Container)
    ).

container_record_type(Options0) ->
    Options1 = Options0 ++ [with_lists, with_tuples, with_array],
    Options2 = proplists:normalize(Options1, [
        {negations, [
            {non_empty, empty},
            {without_array, with_array},
            {without_lists, with_lists},
            {without_tuples, with_tuples}
        ]}
    ]),
    print_options(Options2),
    ContainerTypes0 = lists:flatten([
        new_uninitialized_container(maps),
        new_uninitialized_container(orddict),
        case proplists:get_bool(with_lists, Options2) of
            true ->
                [
                    new_uninitialized_container(lists),
                    new_uninitialized_container(proplists)
                ];
            false ->
                []
        end,
        new_uninitialized_container(dict),
        new_uninitialized_container(gb_trees),
        case proplists:get_bool(with_array, Options2) of
            true ->
                new_uninitialized_container(array);
            false ->
                []
        end,
        case proplists:get_bool(with_tuples, Options2) of
            true ->
                new_uninitialized_container(tuples);
            false ->
                []
        end
    ]),
    OrddictType1 =
        case
            {
                proplists:get_value(empty, Options2),
                proplists:get_value(orddict, Options2)
            }
        of
            {true, _} ->
                return([]);
            {false, undefined} ->
                non_empty;
            {false, OrddictType0} ->
                non_empty(OrddictType0);
            {undefined, undefined} ->
                undefined;
            {undefined, OrddictType0} ->
                OrddictType0
        end,
    ContainerTypes1 =
        case OrddictType1 of
            undefined ->
                ContainerTypes0;
            non_empty ->
                [
                    Container#container{
                        orddict = non_empty(Container#container.orddict)
                    }
                 || Container <- ContainerTypes0
                ];
            OrddictType1 ->
                [
                    Container#container{orddict = OrddictType1}
                 || Container <- ContainerTypes0
                ]
        end,
    oneof(ContainerTypes1).

lists_equals(A, B) ->
    is_list(A) andalso is_list(B) andalso lists:sort(A) =:= lists:sort(B).

proplists_equals(A, B) ->
    is_list(A) andalso is_list(B) andalso
        lists:sort(proplists:compact(A)) =:= lists:sort(proplists:compact(B)).

array_list_delete(Index, Array) ->
    Init = lists:sublist(Array, Index - 1),
    Tail = lists:nthtail(Index, Array),
    Init ++ Tail.

array_list_from_list(Orddict) ->
    [Value || {_Key, Value} <- Orddict].

array_list_keys(Array) ->
    lists:seq(1, length(Array)).

dict_equals(A, B) ->
    is_record(A, dict, 9) andalso is_record(B, dict, 9) andalso
        lists:sort(dict:to_list(A)) =:= lists:sort(dict:to_list(B)).

gb_trees_equals(A, B) when ?is_gb_tree(A) andalso ?is_gb_tree(B) ->
    gb_trees:balance(A) =:= gb_trees:balance(B);
gb_trees_equals(_, _) ->
    false.

array_equals(A, B) ->
    array:is_array(A) andalso array:is_array(B) andalso
        array:sparse_to_orddict(A) =:= array:sparse_to_orddict(B).

array_from_list(Orddict) when is_integer(element(1, hd(Orddict))) ->
    array:from_orddict(Orddict);
array_from_list(Orddict) when is_list(Orddict) ->
    array:from_list([Value || {_Key, Value} <- Orddict]).

array_keys(Array) ->
    orddict:fetch_keys(array:sparse_to_orddict(Array)).

tuple_from_list(Orddict) ->
    list_to_tuple([Value || {_Key, Value} <- Orddict]).

tuple_to_array_list(Tuple) ->
    lists:enumerate(tuple_to_list(Tuple)).

tuple_keys(Tuple) ->
    lists:seq(1, tuple_size(Tuple)).

%% @equiv orddict_type(key_type(), value_type()).
orddict_type() ->
    orddict_type(key_type(), value_type()).

orddict_type(KeyType, ValueType) ->
    ?LET(
        List,
        list({KeyType, ValueType}),
        lists:ukeysort(1, List)
    ).

key_type() ->
    oneof([atom(), binary(), string()]).

value_type() ->
    %% Should be any, but that breaks the plain list type.
    %% This way its `from_list' does not accidentally create an orddict or
    %% proplist.
    oneof([integer(), binary(), string()]).

%%%_* Private ----------------------------------------------------------------
new_uninitialized_container(maps) ->
    #container{
        module = maps,
        delete = remove
    };
new_uninitialized_container(orddict) ->
    #container{
        module = orddict,
        delete = erase,
        get = fetch,
        keys = fetch_keys
    };
new_uninitialized_container(lists) ->
    #container{
        module = lists,
        equals = fun lists_equals/2,
        delete = fun array_list_delete/2,
        from_list = fun array_list_from_list/1,
        get = nth,
        keys = fun array_list_keys/1,
        new = fun() -> [] end,
        size = fun erlang:length/1,
        to_list = enumerate
    };
new_uninitialized_container(proplists) ->
    #container{
        module = proplists,
        type = lists,
        orddict = orddict_type(
            ?SUCHTHAT(Key, atom(), Key =/= missing_key),
            oneof([boolean(), integer(), binary()])
        ),
        equals = fun proplists_equals/2,
        from_list = compact,
        get = get_value,
        keys = get_keys,
        new = fun() -> [] end,
        size = fun erlang:length/1,
        to_list = unfold
    };
new_uninitialized_container(dict) ->
    #container{
        module = dict,
        equals = fun dict_equals/2,
        delete = erase,
        get = fetch,
        keys = fetch_keys
    };
new_uninitialized_container(gb_trees) ->
    #container{
        module = gb_trees,
        equals = fun gb_trees_equals/2,
        from_list = from_orddict,
        new = empty
    };
new_uninitialized_container(array) ->
    #container{
        module = array,
        orddict = oneof([
            orddict_type(nat(), value_type()),
            orddict_type()
        ]),
        delete = reset,
        equals = fun array_equals/2,
        from_list = fun array_from_list/1,
        to_list = sparse_to_orddict,
        keys = fun array_keys/1,
        size = sparse_size
    };
new_uninitialized_container(tuples) ->
    #container{
        type = {},
        module = undefined,
        new = fun() -> {} end,
        from_list = fun tuple_from_list/1,
        to_list = fun tuple_to_array_list/1,
        keys = fun tuple_keys/1,
        delete = fun erlang:delete_element/2,
        get = fun erlang:element/2,
        size = fun erlang:tuple_size/1
    }.

initialize_container(#container{} = Container0) ->
    Container1 = Container0#container{
        type =
            case Container0#container.type of
                undefined -> Container0#container.module;
                Type -> Type
            end,
        delete = fun_for(Container0, #container.delete, 2),
        equals = fun_for(Container0, #container.equals, 2),
        from_list = fun_for(Container0, #container.from_list, 1),
        get = fun_for(Container0, #container.get, 2),
        keys = fun_for(Container0, #container.keys, 1),
        new = fun_for(Container0, #container.new, 0),
        size = fun_for(Container0, #container.size, 1),
        to_list = fun_for(Container0, #container.to_list, 1)
    },
    #container{orddict = Orddict, from_list = FromList, to_list = ToList} = Container1,
    Container2 = Container1#container{
        collection =
            case maps:from_list(erlang:fun_info(FromList)) of
                #{type := local} ->
                    FromList(Orddict);
                #{type := external, module := maps, name := from_list} ->
                    maps:from_list(Orddict);
                #{type := external, module := erlang, name := list_to_tuple} ->
                    list_to_tuple(Orddict);
                #{type := external, module := Module, name := Name} ->
                    {'$call', Module, Name, [Orddict]}
            end,
        %% Some collections lose info, let it do so
        orddict = ToList(FromList(Orddict))
    },
    ?assertEqual(
        #{},
        maps:filter(fun is_function_field/2, to_map(Container2)),
        "all function references must be resolved"
    ),
    Container2.

%% @private
fun_for(#container{module = Module} = Container, Index, Arity) ->
    case element(Index, Container) of
        Fun when is_function(Fun) ->
            ?assertMatch(_ when is_function(Fun, Arity), Fun, "arity must match"),
            Fun;
        Name when is_atom(Name) ->
            fun Module:Name/Arity
    end.

%% @private
to_map(#container{} = Container) ->
    maps:from_list([
        {Field, element(Index, Container)}
     || {Index, Field} <- lists:enumerate(2, record_info(fields, container))
    ]).

%% @private
is_function_field(Field, _Value) when
    ?oneof(Field, module, type, orddict, collection)
->
    %% Ignore non-function fields
    false;
is_function_field(_Field, Value) ->
    %% All other fields must be `fun's
    not is_function(Value).

print_options(Options0) ->
    Options1 = proplists:unfold(Options0),
    Options2 = [{atom_to_list(Option), Value} || {Option, Value} <- Options1],
    Options3 = proplists:to_map(Options2),
    {With, Without} = maps:fold(fun partion_type_options/3, {[], []}, Options3),
    Formatted0 = [
        case Options3 of
            #{empty := true} -> <<"empty">>;
            #{empty := false} -> <<"non empty">>;
            _ -> <<>>
        end,
        case With of
            [] ->
                <<>>;
            _ ->
                [<<" with ">>, lists:join(<<", ">>, With)]
        end,
        case Options3 of
            #{orddict := _OrddictType} when With =:= [] -> <<" custom orddict">>;
            #{orddict := _OrddictType} -> <<", custom orddict">>;
            _ -> <<>>
        end,
        case Without of
            [] ->
                <<>>;
            _ ->
                [<<" without ">>, lists:join(<<", ">>, Without)]
        end
    ],
    case iolist_to_binary(Formatted0) of
        <<>> -> ok;
        Formatted1 -> io:format("Container options: ~s\n", [Formatted1])
    end.

partion_type_options(<<"with_", Type/bytes>>, true, {With, Without}) ->
    {[Type | With], Without};
partion_type_options(<<"with_", Type/bytes>>, false, {With, Without}) ->
    {With, [Type | Without]};
partion_type_options(_, _, {With, Without}) ->
    {With, Without}.

%%%_* Tests ==================================================================
-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif.
