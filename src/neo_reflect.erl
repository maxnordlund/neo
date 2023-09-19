%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% @doc Helper for the behaviours in this library.
%%% @end
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%%%_* Module declaration =====================================================
-module(neo_reflect).

%%%_* Exports ================================================================
%%%_ * API -------------------------------------------------------------------
-export([
    has_implementation/2,
    implementation_for/2,
    is_any_behaviour_implemented/2,
    is_exported/3
]).

%%%_* Types ------------------------------------------------------------------
-export_type([
    behaviour/0
]).

%%%_* Includes ===============================================================
-include("internal.hrl").
-include("assertions.hrl").

%%%_* Macros =================================================================

%%%_* Types ==================================================================
-type behaviour() :: module().
%% Represents one of the behaviours in this library.

%%%_* Code ===================================================================
%%%_ * API -------------------------------------------------------------------
%% @doc Returns the module that implements the supplied behaviour.
%%
%% With assertions enabled it checks that the resolved module implements
%% at least of the given behaviours, raising an error otherwise.
%%
%% It fails with `badarg' exception if no such implementation can be found,
%% or if no behaviours are given.
-spec implementation_for(map() | list() | tuple(), [behaviour(), ...]) -> module().
implementation_for(Term, []) ->
    error(badarg, [Term, []]);
implementation_for(#{'__struct__' := Module}, Behaviours) when
    is_atom(Module) andalso is_list(Behaviours)
->
    ?assertImplementsBehaviour(Module, Behaviours),
    Module;
implementation_for(Map, Behaviours) when is_map(Map) andalso is_list(Behaviours) ->
    neo_maps;
implementation_for(List, Behaviours) when is_list(List) andalso is_list(Behaviours) ->
    neo_lists;
implementation_for({Size, Nodes}, Behaviours) when
    is_integer(Size) andalso (Nodes =:= nil orelse tuple_size(Nodes) =:= 4) andalso
        is_list(Behaviours)
->
    neo_gb_trees;
implementation_for(Dict, Behaviours) when
    is_record(Dict, dict, 9) andalso is_list(Behaviours)
->
    neo_dict;
implementation_for(Array, Behaviours) when
    is_record(Array, array, 5) andalso is_list(Behaviours)
->
    neo_array;
implementation_for(Record, Behaviours) when
    is_atom(element(1, Record)) andalso is_list(Behaviours)
->
    Module = element(1, Record),
    case code:which(Module) of
        non_existing ->
            neo_tuples;
        _ ->
            case is_any_behaviour_implemented(Module, Behaviours) of
                true ->
                    Module;
                false ->
                    %% TODO: If/when I add `neo_eon' backwards compatibility module,
                    %% I should add a check for it here and return `neo_eon'.
                    %% That module will, in turn, do it's own lookup etc.

                    %% Fall back to `neo_tuples' if the module doesn't implement
                    %% any of the given behaviours.
                    %%
                    %% PropEr generated a tuple with `binary' as the first
                    %% element, which is a module from OTP but does not
                    %% implement `neo_collection'. Rather then crash, we
                    %% should just accept reality and fall back to the generic
                    %% tuple implementation.
                    neo_tuples
            end
    end;
implementation_for(Tuple, Behaviours) when
    is_tuple(Tuple) andalso is_list(Behaviours)
->
    neo_tuples;
implementation_for(Reference, Behaviours) when
    is_reference(Reference) andalso is_list(Behaviours)
->
    try ets:info(cast_to_tid(Reference), id) of
        undefined ->
            %% It is a referene to a deleted ets table.
            %% Treat it as an error.
            error(badarg, [Reference, Behaviours]);
        _Tid ->
            neo_ets
    catch
        error:badarg ->
            error(badarg, [Reference, Behaviours])
    end;
implementation_for(Term, Behaviours) when is_list(Behaviours) ->
    error(badarg, [Term, Behaviours]).

%% @doc Returns `true' if the given term has an implementation for one of the
%% given behaviours, `false' otherwise.
has_implementation(Term, Behaviours) ->
    try implementation_for(Term, Behaviours) of
        _Module -> true
    catch
        error:badarg -> false
    end.

%% @doc Returns `true' if the given module exports a function with the given
%% name and arity.
%%
%% It makes sure to load the module before checking, unlike
%% {@link erlang:function_exported/3}, which means this works in both embedded
%% and interpreted mode.
-spec is_exported(module(), Name :: atom(), arity()) -> boolean().
is_exported(Module, Function, Arity) ->
    code:ensure_loaded(Module),
    erlang:function_exported(Module, Function, Arity).

%% @doc Returns `true' if the given module implements the one of the given
%% behaviours.
-spec is_any_behaviour_implemented(module(), [behaviour()]) -> boolean().
is_any_behaviour_implemented(Module, Behaviours) when
    is_atom(Module) andalso is_list(Behaviours)
->
    ordsets:size(ordsets:intersection(Behaviours, get_behaviours(Module))) > 0.

%%%_* Private ----------------------------------------------------------------
%% @doc Returns the behaviours implemented by the given module.
%%
%% It uses a {@link persistent_term. persistent term} to cache the result.
-spec get_behaviours(module()) -> [behaviour()].
get_behaviours(Module) when is_atom(Module) ->
    case get_cache() of
        #{Module := ImplementedBehaviours} ->
            ImplementedBehaviours;
        _ ->
            ImplementedBehaviours = ordsets:from_list([
                Behaviour
             || {Name, [Behaviour]} <- Module:module_info(attributes),
                ?oneof(Name, behaviour, behavior)
            ]),
            add_to_cache(Module, ImplementedBehaviours),
            ImplementedBehaviours
    end.

get_cache() ->
    persistent_term:get(?MODULE, #{}).

%% @doc Repeatably try to add the given module's behaviours to the cache.
%%
%% This resolves any race between multiple processes using {@link neo} at the
%% same time. After a (short) while the {@link persistent_term} will contain
%% both modules' behaviours and the race is resolved.
add_to_cache(Module, ImplementedBehaviours) ->
    add_to_cache(get_cache(), Module, ImplementedBehaviours).

add_to_cache(Cache, Module, ImplementedBehaviours) when is_map_key(Module, Cache) ->
    %% Silence not used warnings when assertions are off.
    _ = ImplementedBehaviours,
    ?assertEqual(maps:get(Module, Cache), ImplementedBehaviours),
    ok;
add_to_cache(Cache, Module, ImplementedBehaviours) ->
    persistent_term:put(?MODULE, Cache#{Module => ImplementedBehaviours}),
    add_to_cache(get_cache(), Module, ImplementedBehaviours).

%% @doc Hack to convince Dialyzer that the given term can be an
%% {@link ets:tid()}.
%%
%% Otherwise it complains that the call to `ets:info/1' will always fail, and
%% that it breaks the opaques of the given tid.
-compile({inline, cast_to_tid/1}).
-dialyzer({nowarn_function, cast_to_tid/1}).
-spec cast_to_tid(term()) -> ets:tid().
cast_to_tid(Term) ->
    Term.

%%%_* Tests ==================================================================
-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
implementation_for_test_() ->
    neo_test_helpers:test_case(#{
        "missing behaviours" => ?_assertError(
            badarg, implementation_for(?MODULE, [])
        ),
        "Elixir struct" => ?_assertEqual(
            neo_maps, implementation_for(#{'__struct__' => neo_maps}, [neo_collection])
        ),
        "ETS" => #{
            "existing table" => fun() ->
                Tid = ets:new('some table', []),
                ?assertEqual(neo_ets, implementation_for(Tid, [neo_collection]))
            end,
            "deleted table" => fun() ->
                DeletedTid = ets:new('some table', []),
                ets:delete(DeletedTid),
                ?assertError(badarg, implementation_for(DeletedTid, [neo_collection]))
            end,
            "non-tid reference" => fun() ->
                BadTid = make_ref(),
                ?assertError(badarg, implementation_for(BadTid, [neo_collection]))
            end
        },
        "records" => #{
            "with implementation" => ?_assertEqual(
                neo_persistent_term,
                implementation_for(neo_persistent_term:new(), [neo_collection])
            ),
            "missing implementation falls back to neo_tuples" => ?_assertEqual(
                neo_tuples, implementation_for({binary}, [neo_collection])
            )
        }
    }).

get_behaviours_test_() ->
    neo_test_helpers:test_case(#{
        "existing module" => ?_assertEqual(
            [], get_behaviours(?MODULE)
        ),
        "non existing module" => ?_assertError(
            undef, get_behaviours('non existing module')
        )
    }).

-endif.
