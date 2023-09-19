-include_lib("stdlib/include/assert.hrl").

-ifndef(NOASSERT).
-define(if_asserting(Block), Block).
-else.
-define(if_asserting(Block), ok).
-endif.

-ifdef(TEST).

-define(var(Expr), begin
    (fun(X__Term) ->
        io:format("~ts = ~tp\n", [??Expr, X__Term]),
        X__Term
    end)(
        Expr
    )
end).
-else.
-define(var(Expr), ok).
-endif.

%% Poor mans `in' operator
-define(oneof(Value, Alt1, Alt2), (Value =:= Alt1 orelse Value =:= Alt2)).

%% Poor mans `in' operator
-define(oneof(Value, Alt1, Alt2, Alt3),
    (Value =:= Alt1 orelse ?oneof(Value, Alt2, Alt3))
).

%% Poor mans `in' operator
-define(oneof(Value, Alt1, Alt2, Alt3, Alt4),
    (Value =:= Alt1 orelse ?oneof(Value, Alt2, Alt3, Alt4))
).

%% Poor mans `in' operator
-define(oneof(Value, Alt1, Alt2, Alt3, Alt4, Alt5),
    (Value =:= Alt1 orelse ?oneof(Value, Alt2, Alt3, Alt4, Alt5))
).

%% Poor mans `in' operator
-define(oneof(Value, Alt1, Alt2, Alt3, Alt4, Alt5, Alt6),
    (Value =:= Alt1 orelse ?oneof(Value, Alt2, Alt3, Alt4, Alt5, Alt6))
).

-define(is_pos_integer(Limit), (is_integer(Limit) andalso Limit >= 0)).

-define(is_non_neg_integer(Limit), (is_integer(Limit) andalso Limit > 0)).

-define(is_callback(Function),
    (is_function(Function, 1) orelse is_function(Function, 2))
).

-define(call_callback(Callback, KeyIn, ValueIn),
    if
        is_function(Callback, 2) -> Callback(KeyIn, ValueIn);
        is_function(Callback, 1) -> Callback(ValueIn)
    end
).
