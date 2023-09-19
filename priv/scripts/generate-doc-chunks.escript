#!/usr/bin/env escript

-define(var(Var), io:format("~s = ~p\n", [??Var, Var])).

main([]) ->
    Dependencies = add_dependencies_to_code_path(),
    io:format("Generated doc chunks"),
    maps:foreach(
        %% Can't use local `fun's in an (interpreted) escript
        fun(App, Dependency) ->
            generate_edoc_chunks(App, Dependency)
        end,
        Dependencies
    ),
    io:nl();
main([App | _]) ->
    BuildRoot = build_root(),
    add_dependencies_to_code_path(),
    io:format("Generated doc chunks for ~s", [App]),
    generate_edoc_chunks(App, BuildRoot ++ "/ebin"),
    io:nl();
main(_) ->
    io:format("usage: ~s <erlang application>\n", [
        filename:basename(escript:script_name())
    ]),
    halt(1).

add_dependencies_to_code_path() ->
    BuildRoot = build_root(),
    Dependencies = dependencies(BuildRoot),
    code:add_paths(maps:values(Dependencies)),
    Dependencies.

build_root() ->
    RepoRoot = filename:dirname(
        filename:dirname(
            filename:dirname(filename:absname(escript:script_name()))
        )
    ),
    case
        re:run(RepoRoot, "^(.+)/_build/[^/]+/lib/neo$", [{capture, all_but_first, list}])
    of
        {match, [RebarRoot]} -> RebarRoot;
        nomatch -> RepoRoot
    end.

dependencies(BuildRoot) ->
    %% By ordering the wildcard below correctly, we can skip duplicates (aka
    %% symlinks) and prefer the default profile
    Dependencies = maps:from_list([
        case filelib:wildcard(Dependency ++ "/*.app") of
            [] ->
                {undefined, undefined};
            [AppFile] ->
                App = filename:basename(AppFile, ".app"),
                {App, Dependency}
        end
     || Dependency <- filelib:wildcard(
            %% Wildcard requires / on all platforms
            lists:join(
                $/, (filename:split(BuildRoot) ++ ["_build/{docs,default}/lib/*/ebin"])
            )
        )
    ]),
    maps:remove(undefined, Dependencies).

generate_edoc_chunks(App0, Dependency) ->
    App1 = list_to_atom(App0),
    Macros =
        case
            file:consult(filename:join(filename:dirname(Dependency), "rebar.config"))
        of
            {ok, RebarConfig} -> macro_options(RebarConfig);
            {error, enoent} -> []
        end,
    Includes0 = [
        begin
            Module = list_to_atom(filename:basename(Beam, ".beam")),
            Compile = Module:module_info(compile),
            Options = proplists:get_value(options, Compile, []),
            proplists:get_all_values(i, Options)
        end
     || Beam <- filelib:wildcard(Dependency ++ "/*.beam")
    ],
    Includes1 = ordered_unique_includes(Includes0),
    try
        edoc:application(App1, [
            {preprocess, true},
            {macros, Macros},
            {includes, Includes1},
            {doclet, edoc_doclet_chunks},
            {layout, edoc_layout_chunks}
        ])
    catch
        exit:error ->
            ignore
    end,
    io:format("."),
    App1.

macro_options(RebarConfig) ->
    ErlOpts = proplists:get_value(erl_opts, RebarConfig, []),
    EdocOpts = proplists:get_value(edoc_opts, RebarConfig, []),
    ErlcMacros = maps:from_list([
        case MacroDefinition of
            {d, Macro} -> {Macro, true};
            {d, Macro, Value} -> {Macro, Value}
        end
     || MacroDefinition <- ErlOpts,
        is_tuple(MacroDefinition) andalso d =:= element(1, MacroDefinition)
    ]),
    EdocMacros = maps:from_list(proplists:get_value(macros, EdocOpts, [])),
    maps:to_list(maps:merge(ErlcMacros, EdocMacros)).

ordered_unique_includes([]) ->
    [];
ordered_unique_includes([Head | Tail]) ->
    lists:reverse(
        lists:foldl(
            fun(Include, Includes) ->
                case lists:member(Include, Includes) of
                    true -> Includes;
                    false -> [Include | Includes]
                end
            end,
            lists:reverse(Head),
            Tail
        )
    ).
