%%%_* Module declaration =====================================================
-module(neo_eunit_reporter).

%%%_* Behaviour ==============================================================
-behaviour(eunit_listener).

%%%_* Exports ================================================================
%%%_ * API -------------------------------------------------------------------
-export([
    start/0,
    start/1
]).

%%%_* eunit_listener callbacks -----------------------------------------------
-export([
    init/1,
    handle_begin/3,
    handle_end/3,
    handle_cancel/3,
    terminate/2
]).

%%%_* Types ------------------------------------------------------------------

%%%_* Includes ===============================================================
-include("internal.hrl").
-include("test_helpers.hrl").

%%%_* Macros =================================================================
-define(INDENT, 4).

%%%_* Types ==================================================================
%%%_* Private ----------------------------------------------------------------
-record(test, {
    id :: non_neg_integer(),
    desc :: description(),
    source :: mfa(),
    line :: integer(),
    status :: ok | {error, term()} | {skipped, term()} | undefined,
    time :: pos_integer() | undefined,
    output :: binary() | undefined
}).

-record(group, {
    %% handle_{begin,end}
    id :: non_neg_integer() | undefined,
    desc :: description(),
    spawn :: spawn_options() | undefined,
    order :: order_option() | undefined,
    %% handle_end
    size :: pos_integer() | undefined,
    time :: pos_integer() | undefined,
    output :: iodata() | undefined,
    %% extra
    members = #{} :: #{non_neg_integer() => #group{}}
}).

-record(state, {
    options = #{} :: #{
        verbose => boolean(),
        atom() => term()
    },
    root = #group{}
    % groups = [] :: [group_common_data()],
    % tests = [] :: [test_common_data()]
}).

-type state() :: #state{}.

%% Types for the callbacks. Sadly they aren't properly documented, so this is
%% the result of reading the code and dumping stuff to stdout.

%%%_* Groups -----------------------------------------------------------------
-type group_common_data() ::
    {id, id_path()}
    | {desc, description()}
    | {spawn, spawn_options()}
    | {order, order_option()}.

-type group_end_data() ::
    group_common_data()
    | {size, pos_integer()}
    | {time, pos_integer()}
    | {output, iodata()}.

-type group_cancel_data() ::
    group_common_data()
    % | {id, non_neg_integer()}
    | {reason, cancel_descriptor()}.

%%%_* Tests ------------------------------------------------------------------
-type test_common_data() ::
    {id, id_path()}
    | {desc, description()}
    | {source, mfa()}
    | {line, integer()}.

-type test_end_data() ::
    test_common_data()
    | {status, ok | {error, term()} | {skipped, term()}}
    | {time, pos_integer()}
    | {output, binary()}.

-type test_cancel_data() ::
    test_common_data()
    % | {id, non_neg_integer()}
    | {reason, cancel_descriptor()}.

%%%_* Common -----------------------------------------------------------------
-type description() :: binary() | undefined.

-type spawn_options() :: local | {remote, node()}.

-type order_option() :: inorder | inparallel | {inparallel, non_neg_integer()}.

-type cancel_descriptor() ::
    timeout
    | {timeout, #{stacktrace := erlang:stacktrace()}}
    | {blame, non_neg_integer()}
    | {abort, term()}
    | {exit, term()}
    | {startup, term()}.

-type id_path() :: [non_neg_integer()].
%% @doc A list of ids, [parent, parent, ..., this test or group]

%%%_* Code ===================================================================
%%%_* API -------------------------------------------------------------------

start() ->
    start([]).

start(Options) ->
    eunit_listener:start(?MODULE, Options).

%%%_* eunit_listener callbacks -----------------------------------------------
-spec init(proplists:proplist()) -> state().
init(Options) ->
    State = #state{options = proplists:to_map(Options)},
    State.

-spec handle_begin
    (group, Group, state()) -> state() when
        Group :: [group_common_data()];
    (test, Test, state()) -> state() when
        Test :: [test_common_data()].
handle_begin(group, Data, #state{} = State) ->
    update_group(State, Data);
handle_begin(test, Data, #state{} = State) ->
    update_test(State, Data).

-spec handle_end
    (group, Group, state()) -> state() when
        Group :: [group_end_data()];
    (test, Test, state()) -> state() when
        Test :: [test_end_data()].
handle_end(group, Data, #state{} = State) ->
    update_group(State, Data);
handle_end(test, Data, #state{} = State) ->
    update_test(State, Data).

-spec handle_cancel
    (group, Group, state()) -> state() when
        Group :: [group_cancel_data()];
    (test, Test, state()) -> state() when
        Test :: [test_cancel_data()].
handle_cancel(group, Data, #state{} = State) ->
    update_group(State, Data);
handle_cancel(test, Data, #state{} = State) ->
    update_test(State, Data).

-spec terminate
    ({ok, Data}, state()) -> any() when
        Data :: [
            {pass, pos_integer()}
            | {fail, pos_integer()}
            | {skip, pos_integer()}
            | {cancel, pos_integer()}
        ];
    ({error, Reason}, state()) -> any() when
        Reason :: term().
terminate({ok, Data}, State) ->
    io:format("Terminated successfully\n", []),
    print(State),
    print(Data),
    ok;
terminate({error, Reason}, State) ->
    io:format("Terminated with reason ~p\nand state ~tp", [Reason, State]),
    ok.

%%%_* Private ----------------------------------------------------------------
update_group(#state{root = Root} = State, Data) ->
    {id, Path} = proplists:lookup(id, Data),
    Id =
        case Path of
            [] -> undefined;
            _ -> lists:last(Path)
        end,
    Group = #group{
        id = Id,
        desc = proplists:get_value(desc, Data),
        spawn = proplists:get_value(spawn, Data),
        order = proplists:get_value(order, Data)
    },
    S = State#state{
        root = merge(Root#group.id, Root, nest(Group, Path))
    },
    S.

update_test(#state{root = Root} = State, Data) ->
    {id, Path} = proplists:lookup(id, Data),
    Id =
        case Path of
            [] -> undefined;
            _ -> lists:last(Path)
        end,
    Test = #test{
        id = Id,
        desc = proplists:get_value(desc, Data),
        source = proplists:get_value(source, Data),
        line = proplists:get_value(line, Data),
        status = proplists:get_value(status, Data),
        time = proplists:get_value(time, Data),
        output = proplists:get_value(output, Data)
    },
    S = State#state{
        root = merge(Root#group.id, Root, nest(Test, Path))
    },
    S.

nest(#group{} = Group, []) ->
    Group;
nest(#test{} = Test, []) ->
    Test;
nest(#group{members = Members} = Group, [Id | Ids]) ->
    Group#group{members = Members#{Id => nest(Group, Ids)}};
nest(#test{} = Test, [Id | Ids]) ->
    #group{members = #{Id => nest(Test, Ids)}}.

merge(_Id, #group{} = ExistingGroup, #group{} = NewGroup) ->
    NewGroup#group{
        size = get_defined_field(#group.size, ExistingGroup, NewGroup),
        time = get_defined_field(#group.time, ExistingGroup, NewGroup),
        output = get_defined_field(#group.output, ExistingGroup, NewGroup),
        members = maps:merge_with(
            fun merge/3, ExistingGroup#group.members, NewGroup#group.members
        )
    };
merge(_Id, #test{} = ExistingTest, #test{} = NewTest) ->
    NewTest#test{
        status = get_defined_field(#test.status, ExistingTest, NewTest),
        time = get_defined_field(#test.time, ExistingTest, NewTest),
        output = get_defined_field(#test.output, ExistingTest, NewTest)
    }.

get_defined_field(Field, Left, Right) ->
    case element(Field, Left) of
        undefined ->
            element(Field, Right);
        Value ->
            ?assertEqual(Value, element(Field, Right), "existing fields must match"),
            Value
    end.

print(Term) ->
    {ok, Columns} = io:columns(),
    PaperWidth = Columns,
    RibbonWidth = PaperWidth - 15,
    Options = #{
        color => true,
        paper => PaperWidth,
        ribbon => RibbonWidth
    },
    io:put_chars(
        prettypr:format(
            to_doc(Term, Options), PaperWidth, RibbonWidth
        )
    ),
    io:nl().

to_doc(#state{} = State, Options) ->
    record_to_doc(State, record_info(fields, state), Options);
to_doc(#test{} = Test, Options) ->
    record_to_doc(Test, record_info(fields, test), Options);
to_doc(#group{} = Group, Options) ->
    record_to_doc(Group, record_info(fields, group), Options);
to_doc(Atom, Options) when is_atom(Atom) ->
    concat_horizontally([
        prettypr:null_text(?ATOM_NUMBER_COLOR(Options)),
        prettypr:text(atom_to_list(Atom)),
        prettypr:null_text(?RESET(Options))
    ]);
to_doc(Integer, Options) when is_integer(Integer) ->
    concat_horizontally([
        prettypr:null_text(?NUMBER_COLOR(Options)),
        prettypr:text(integer_to_list(Integer)),
        prettypr:null_text(?RESET(Options))
    ]);
to_doc(Float, Options) when is_float(Float) ->
    concat_horizontally([
        prettypr:null_text(?NUMBER_COLOR(Options)),
        prettypr:text(float_to_list(Float)),
        prettypr:null_text(?RESET(Options))
    ]);
to_doc(List, Options) when is_list(List) ->
    case io_lib:printable_unicode_list(List) of
        true ->
            [[$", FormattedString, $"]] = io_lib:format("~tp", [List]),
            concat_horizontally([
                prettypr:null_text(?STRING_COLOR(Options)),
                prettypr:text(FormattedString),
                prettypr:null_text(?RESET(Options))
            ]);
        false ->
            [
                prettypr:text("[")
                | [
                    prettypr:nest(
                        ?INDENT,
                        to_doc(Element, Options)
                    )
                 || Element <- List
                ]
            ] ++
                [
                    prettypr:text("]")
                ]
    end;
to_doc(Binary, Options) when is_binary(Binary) ->
    [[$<, $<, FormattedString, $>, $>]] = io_lib:format("~tp", [Binary]),
    concat_horizontally([
        prettypr:text("<<"),
        prettypr:null_text(?STRING_COLOR(Options)),
        prettypr:text(io_lib:write_string(FormattedString)),
        prettypr:null_text(?RESET(Options)),
        prettypr:text(">>")
    ]);
to_doc(Map, Options) when is_map(Map) ->
    nest(
        prettypr:text("#{"),
        [
            map_field_to_doc(Map, Key, Options)
         || Key <- lists:sort(maps:keys(Map))
        ],
        prettypr:text("}")
    );
to_doc(Term, #{paper := PaperWidth, ribbon := RibbonWidth}) ->
    Doc = erl_prettypr:layout(erl_parse:abstract(Term), [
        {paper, PaperWidth, ribbon, RibbonWidth}
    ]),
    % io:format("~tp ->\n  ~ts\n", [Term, prettypr:format(Doc)]),
    Doc.

nest(Header, Documents, Trailer) ->
    prettypr:above(
        prettypr:beside(
            prettypr:break(Header),
            prettypr:nest(
                ?INDENT,
                concat_vertically(Documents)
            )
        ),
        Trailer
    ).

map_field_to_doc(Map, Key, Options) ->
    concat_horizontally([
        to_doc(Key, Options),
        prettypr:text(" => "),
        to_doc(maps:get(Key, Map), Options),
        prettypr:break(prettypr:text(","))
    ]).

record_to_doc(Record, Fields, Options) ->
    Tag = concat_horizontally([
        prettypr:text("#"),
        prettypr:null_text(?MODULE_RECORD_TAG_COLOR(Options)),
        prettypr:text(atom_to_list(element(1, Record))),
        prettypr:null_text(?RESET(Options)),
        prettypr:text("{")
    ]),
    nest(
        Tag,
        [
            record_field_to_doc(Record, Field, Index, Options)
         || {Index, Field} <- lists:enumerate(2, Fields)
        ],
        prettypr:text("}")
    ).

record_field_to_doc(Record, Field, Index, Options) ->
    FieldName = atom_to_list(Field),
    concat_horizontally([
        prettypr:null_text(?RECORD_FIELD_COLOR(Options)),
        prettypr:text(FieldName),
        prettypr:null_text(?OPERATOR_COLOR(Options)),
        prettypr:text(" = "),
        prettypr:null_text(?RESET(Options)),
        prettypr:beside(
            prettypr:nest(
                -length(FieldName) - ?INDENT,
                to_doc(element(Index, Record), Options)
            ),
            prettypr:text(",")
        )
    ]).

concat_horizontally(Documents) ->
    lists:foldr(fun prettypr:beside/2, prettypr:empty(), Documents).

concat_vertically(Documents) ->
    % concat_horizontally(lists:map(fun prettypr:break/1, Documents)).
    lists:foldr(fun prettypr:above/2, prettypr:empty(), Documents).

%%%_* Tests ==================================================================
-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").

-endif.
