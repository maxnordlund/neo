#!/usr/bin/env escript

main([App0 | _]) ->
    App1 = list_to_atom(App0),
    RepoRoot = filename:dirname(
        filename:dirname(filename:absname(escript:script_name()))
    ),
    code:add_paths(
        filelib:wildcard(
            %% Wildcard requires / on all platforms
            lists:join(
                $/, (filename:split(RepoRoot) ++ ["_build/{default,docs}/lib/*/ebin"])
            )
        )
    ),
    edoc:application(App1, [
        {doclet, edoc_doclet_chunks},
        {layout, edoc_layout_chunks}
    ]),
    io:format("Generated doc chunks for ~p\n", [App1]);
main(_) ->
    io:format("usage: ~s <erlang application>\n", [
        filename:basename(escript:script_name())
    ]),
    halt(1).
