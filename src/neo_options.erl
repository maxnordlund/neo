%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%%%_* Module declaration ======================================================
-module(neo_options).

%%%_* Exports =================================================================
%%%_ * API --------------------------------------------------------------------

-export([ normalize/2, partition_config/1 ]).

-export([ partition_option/2 ]).

%%%_ * Types ------------------------------------------------------------------

-export_type([ options/0
             , proplist/0
             , proplist/2
             ]).

%%%_* Includes ================================================================

%%%_ * Types ==================================================================

-type option() :: atom().

-type value() :: term().

-type aliases() :: [option()].

-type expansions() :: [value()].

-type config() :: #{
    {option()} => expansions(),
    [option()|aliases()] => value(),
    option() => value()
}.

-type partitioned_config() :: #{
    negations := #{ option() := option() },
    aliases := #{ option() := option() },
    expansions := #{ option() := expansions() },
    defaults := #{}
}.

-type options() :: #{ option() => value() }.

-type proplist() :: proplist(atom(), term()).

-type proplist(Key, Value) :: [Key | {Key, Value}].

%%%_* Macros ==================================================================

%%%_* Code ====================================================================
%%%_ * API --------------------------------------------------------------------

%% Helper for functions accepting proplists and maps as options.
%% Using makes is nice because of pattern matching, but using proplists is nice
%% when calling.
%% Compare #{ flag => true } vs [flag] and #{ key => value } vs [{key, value}]
%% The latter is ok, but the former is where proplists shine.
%% Also, the proplists module has some nice functions for no_<flag> and aliases,
%% let's expose them for map users as well.
%%
%% The net result is that can you write a trampoline calling `normalize',
%% and pattern match on the resulting nice map in a private function where
%% the real implementation lies.
-spec normalize(options() | proplist(option(), value()), config()) -> options().
normalize(Options, Config) when is_map(Options) ->
    normalize(maps:to_list(Options), Config);
normalize(Options, Config) when is_list(Options) andalso is_map(Config) ->
    #{
        negations := Negations,
        aliases := Aliases,
        expansions := Expansions,
        defaults := Defaults
    } = partition_config(Config),
    Proplist = proplists:unfold(proplists:normalize(Options, [
        %% Must come in this order
        {negations, maps:to_list(Negations)},
        {aliases, maps:to_list(Aliases)},
        {expand, maps:to_list(Expansions)}
    ])),
    neo:merge(Defaults, neo:from_list(Proplist)).

%%%_* Private functions ------------------------------------------------------
-spec partition_config(config()) -> partitioned_config().
partition_config(Config) when is_map(Config) ->
     lists:foldl(fun partition_option/2, #{
        negations => #{},
        aliases => #{},
        expansions => #{},
        defaults => #{}
    }, maps:to_list(Config)).

-spec partition_option(Stage, Config) -> partitioned_config() when
    Stage :: {option(), term()} | {[option()], term()} | {{option()}, expansions()},
    Config :: config().
partition_option({Key, Flag}, Config) when is_boolean(Flag) ->
    BinaryKey = atom_to_binary(Key, utf8),
    BinaryNoKey = <<"no_"/utf8, BinaryKey/binary>>,
    AtomNoKey = binary_to_atom(BinaryNoKey, utf8),
    neo:merge(Config, #{
        negations => #{ AtomNoKey => {Key, Flag} },
        defaults => #{ Key => Flag }
    });
partition_option({[Target|Aliases], Value}, Config) ->
    neo:merge(Config, #{
        aliases => maps:from_list([
            {Alias, Target}
        ||
            Alias <- Aliases
        ]),
        defaults => #{
            Target => Value
        }
    });
partition_option({{Key}, Expansions}, Config) when is_list(Expansions) ->
    neo:dset(Config, [expansions, Key], Expansions);
partition_option({Key, Value}, Config) ->
    neo:dset(Config, [defaults, Key], Value).

%%%_* Tests ============================================================
-ifdef(TEST).

-include_lib("eunit/include/eunit.hrl").

-define(OPTIONS_CONFIG, #{
    {expand} => [all, this, stuff],
    [colour, color, 'färg'] => red,
    plain => property,
    warnings => true
}).

normalization_for_test() ->
    Options = ?OPTIONS_CONFIG,
    Expected = #{
        negations => #{
            no_warnings => {warnings, true}
        },
        aliases => #{
            color => colour,
            'färg' => colour
        },
        expansions => #{
            expand => [all, this, stuff]
        },
        defaults => #{
            colour => red,
            plain => property,
            warnings => true
        }
    },
    ?assertEqual(Expected, partition_config(Options)).

-endif.
