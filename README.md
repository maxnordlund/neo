# `neo`
Neo is a replacement for [`eon`][1] that uses Erlang's native maps instead of
[`orddict`][2]. It aims for feature parity with `eon`, however some functions
may have a different name, for example `neo:delete/2` instead of `eon:del/2`.

## Installation
Add it to your [`rebar.config`'s `deps`][3] and run
`rebar3 compile --deps_only`.

```erlang
{deps, [
    {neo, {git, "git@github.com:kivra/neo.git", {tag, "1.1.2"}}}
]}.
```

## Documentation
All public `neo` functions comes with `edoc`. You can either access them
through the [shell][4], or run `rebar3 edoc` and view the resulting HTML.

[1]: https://github.com/kivra/eon
[2]: http://erlang.org/doc/man/orddict.html
[3]: https://www.rebar3.org/docs/configuration/dependencies/
[4]: https://www.erlang.org/doc/man/shell_docs.html
