-ifndef(NEO_ASSERTIONS).
-define(NEO_ASSERTIONS, true).

-include_lib("stdlib/include/assert.hrl").

%% Asserts that the given module implements the behaviour defined by this
%% module.
-define(assertImplementsBehaviour(Module),
    ?assertImplementsBehaviour(Module, [?MODULE])
).

%% Asserts that the given module implements the given behaviour.
%%
%% It fails with `missing_beam' if it can't
%% {@link code:get_object_code/1. load} the BEAM file for the given `Module',
%% and with the error from {@link beam_lib:chunks/2} if one is returned.
-ifdef(NOASSERT).
-define(assertImplementsBehaviour(Module, Behaviours), ok).
-else.
-define(assertImplementsBehaviour(Module, Behaviours), begin
    (fun(X__Module, X__ExpectedBehaviours) ->
        X__Attributes1 =
            case code:is_loaded(X__Module) of
                false ->
                    case code:get_object_code(X__Module) of
                        {X__Module, X__Beam, _} ->
                            case beam_lib:chunks(X__Beam, [attributes]) of
                                {ok, {_, [{attributes, X__Attributes0}]}} ->
                                    X__Attributes0;
                                {error, beam_lib, Reason} ->
                                    error(Reason, [X__Beam, [attributes]])
                            end;
                        error ->
                            error(missing_beam, [X__Module])
                    end;
                _ ->
                    X__Module:module_info(attributes)
            end,
        X__Behaviours =
            ordsets:from_list([
                X__Behaviour
             || {X__Name, X__Values} <- X__Attributes1,
                X__Name =:= behaviour orelse X__Name =:= behavior,
                X__Behaviour <- X__Values
            ]),
        case ordsets:subtract(X__ExpectedBehaviours, X__Behaviours) of
            [] ->
                ok;
            X__MissingBehaviours ->
                error(
                    {assertEqual, [
                        {type, assertImplementsBehaviour},
                        {module, ?MODULE},
                        {line, ?LINE},
                        {expression,
                            unicode:characters_to_list([
                                $[,
                                lists:map(fun atom_to_list/1, X__ExpectedBehaviours),
                                "] -- Behaviours"
                            ])},
                        {expected_behaviours, X__ExpectedBehaviours},
                        {actual_behaviours, X__Behaviours},
                        {missing_behaviours, X__MissingBehaviours},
                        {expected, []},
                        {actual, X__MissingBehaviours}
                    ]}
                )
        end
    end)(
        Module, Behaviours
    )
end).
-endif.

%% Asserts that the given container is an orddict.
-ifdef(NOASSERT).
-define(assertIsOrddict(Orddict, Arguments), ok).
-else.
-define(assertIsOrddict(Orddict, Arguments), begin
    (fun
        ([]) ->
            ok;
        (X__Orddict) ->
            case neo_lists:typeof(orddict, X__Orddict) of
                orddict ->
                    ok;
                X__Type ->
                    error(
                        {assertMatch, [
                            {module, ?MODULE},
                            {line, ?LINE},
                            {expression, ??Orddict},
                            {pattern, "Orddict when typeof(Orddict) =:= orddict"},
                            {value, X__Orddict},
                            {type, X__Type}
                        ]},
                        Arguments
                    )
            end
    end)(
        Orddict
    )
end).
-endif.

%% Asserts that the given container is equal to the expected container.
%%
%% This is similar to `?assertEqual/2', but it uses the expected container's
%% `equals' function for comparison, instead of a plain match (`==').
-ifdef(NOASSERT).
-define(assertContainerEqual(Container, Expected, Actual), ok).
-else.
-define(assertContainerEqual(Container, Expected, Actual), begin
    ((fun(#container{equals = X__Equals}, X__Expected, X__Actual) ->
        case X__Equals(X__Expected, X__Actual) of
            true ->
                ok;
            false ->
                erlang:error(
                    {assertEqual, [
                        {module, ?MODULE},
                        {line, ?LINE},
                        {expression,
                            %% Rebar formats the error message like this:
                            %% ?assertEqual(<expected>, <expression>)
                            neo_test_helpers:flat_format("~s)\e[0m using ~s", [
                                ??Actual,
                                neo_test_helpers:format(X__Equals, #{color => false})
                            ])},
                        {expected, X__Expected},
                        {value, X__Actual}
                    ]}
                )
        end
    end)(
        Container, Expected, Actual
    ))
end).
-endif.

-ifdef(NOASSERT).
-define(assertNotException(Expr), ok).
-else.
-define(assertNotException(Expr), begin
    (fun() ->
        try (Expr) of
            _ -> ok
        catch
            X__Class:X__Reason:X__Stacktrace ->
                erlang:error(
                    {assertNotException, [
                        {module, ?MODULE},
                        {line, ?LINE},
                        {expression, ??Expr},
                        %% Must match ?assertNotException/3
                        {pattern, "{ _ , _ , [...] }"},
                        {unexpected_exception, {X__Class, X__Reason, X__Stacktrace}}
                    ]}
                )
        end
    end)()
end).
-endif.

-endif.
