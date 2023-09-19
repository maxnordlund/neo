%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% @doc Implementation of {@link neo_collection} for Erlang's builtin
%%% `persistent_term' module.
%%% @end
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%%%_* Module declaration =====================================================
-module(neo_persistent_term).
-compile({no_auto_import, [size/1]}).

%%%_* Behaviours =============================================================
-behaviour(neo_collection).

%%%_* Exports ================================================================
%%%_ * API -------------------------------------------------------------------
%%%_ * Callbacks -------------------------------------------------------------
-export([
    delete/2,
    get/2,
    get/3,
    keys/1,
    has/2,
    new/0,
    set/3,
    size/1
]).

%%%_* Types ------------------------------------------------------------------
-export_type([
    t/0
]).

%%%_* Includes ===============================================================

%%%_* Macros =================================================================

%%%_* Types ==================================================================
-record(neo_persistent_term, {}).

-opaque t() :: #neo_persistent_term{}.

-type key() :: term().

%%%_* Code ===================================================================
%%%_ * API -------------------------------------------------------------------

%%%_ * Callbacks -------------------------------------------------------------
%% @doc Returns an opaque handle to {@link persistent_term}.
-spec new() -> t().
new() ->
    #neo_persistent_term{}.

%% @doc Returns the number of {@link persistent_term. persistent terms}.
-spec size(t()) -> non_neg_integer().
size(#neo_persistent_term{}) ->
    maps:get(count, persistent_term:info()).

%% @doc Returns `true' if there's a {@link persistent_term. persistent term}
%% for the given `Key', `false' otherwise.
-spec has(t(), key()) -> boolean().
has(#neo_persistent_term{}, Key) ->
    try persistent_term:get(Key) of
        _ -> true
    catch
        error:badarg ->
            false
    end.

%% @doc Returns the list of {@link persistent_term. persistent term} keys.
-spec keys(t()) -> [key()].
keys(#neo_persistent_term{}) ->
    [Key || {Key, _Value} <- persistent_term:get()].

%% @doc Returns the {@link persistent_term. persistent term} for the given
%% `Key'.
%%
%% It fails with `badarg' exception if no such
%% {@link persistent_term. persistent term} can be found.
-spec get(t(), key()) -> term().
get(#neo_persistent_term{}, Key) ->
    persistent_term:get(Key).

%% @doc Returns the {@link persistent_term. persistent term} for the given
%% `Key', or `Default' if no such {@link persistent_term. persistent term} can
%% be found.
-spec get(t(), key(), term()) -> term().
get(#neo_persistent_term{}, Key, Default) ->
    persistent_term:get(Key, Default).

%% @doc Sets the {@link persistent_term. persistent term} for the given
%% `Key' to `Value'.
-spec set(t(), key(), term()) -> t().
set(#neo_persistent_term{}, Key, Value) ->
    persistent_term:put(Key, Value),
    #neo_persistent_term{}.

%% @doc Deletes the {@link persistent_term. persistent term} for the given
%% `Key'.
-spec delete(t(), key()) -> t().
delete(#neo_persistent_term{}, Key) ->
    persistent_term:erase(Key),
    #neo_persistent_term{}.

%%%_* Private ----------------------------------------------------------------

%%%_* Tests ==================================================================
-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").

size_test() ->
    ?assertEqual(length(persistent_term:get()), size(new())).

has_test_() ->
    neo_test_helpers:test_case(#{
        setup => fun() ->
            persistent_term:erase(?MODULE)
        end,
        "existing" => fun() ->
            persistent_term:put(?MODULE, 123),
            ?assert(has(new(), ?MODULE))
        end,
        "non existing" => fun() ->
            ?assertNot(has(new(), ?MODULE))
        end
    }).

keys_test_() ->
    eunit_surefire,
    neo_test_helpers:test_case(#{
        setup => fun() ->
            persistent_term:erase(?MODULE)
        end,
        test => fun() ->
            ?assertNot(lists:member(?MODULE, keys(new()))),
            persistent_term:put(?MODULE, 123),
            ?assert(lists:member(?MODULE, keys(new())))
        end
    }).

get_test_() ->
    neo_test_helpers:test_case(#{
        setup => fun() ->
            persistent_term:erase(?MODULE)
        end,
        "without default" => fun() ->
            Ref = make_ref(),
            persistent_term:put(?MODULE, Ref),
            ?assertEqual(Ref, get(new(), ?MODULE))
        end,
        "with default" => fun() ->
            Ref = make_ref(),
            ?assertError(badarg, get(new(), ?MODULE)),
            ?assertEqual(Ref, get(new(), ?MODULE, Ref))
        end
    }).

set_test_() ->
    neo_test_helpers:test_case(#{
        setup => fun() ->
            persistent_term:erase(?MODULE)
        end,
        test => fun() ->
            Ref = make_ref(),
            set(new(), ?MODULE, Ref),
            ?assertEqual(Ref, persistent_term:get(?MODULE))
        end
    }).

delete_test_() ->
    neo_test_helpers:test_case(#{
        setup => fun() ->
            persistent_term:erase(?MODULE)
        end,
        test => fun() ->
            persistent_term:put(?MODULE, 123),
            ?assertNotException(error, badarg, persistent_term:get(?MODULE)),
            delete(new(), ?MODULE),
            ?assertError(badarg, persistent_term:get(?MODULE))
        end
    }).

-endif.
