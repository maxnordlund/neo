# `neo`
Neo is a replacement for [`eon`][1] that uses Erlang's native maps instead of
[`orddict`][2]. It aims for feature parity with `eon`, however some functions
may have a different name, for example `neo:delete/2` instead of `eon:del/2`.

## Installation
Add it to your [`rebar.config`'s `deps`][3] and run `rebar3 compile --deps_only`.

```erlang
{deps, [
    {neo, {git, "git@github.com:kivra/neo.git", {tag, "1.0.1"}}}
]}.
```

## Documentation
All public `neo` functions comes with `edoc`, which you can generate by running
`rebar3 edoc` in this repo. That will generate both a HTML version, and
[doc chunks][4] you then can access in the [Erlang shell][5].

[1]: https://github.com/kivra/eon
[2]: http://erlang.org/doc/man/orddict.html
[3]: https://www.rebar3.org/docs/configuration/dependencies/
[4]: https://www.erlang.org/erlang-enhancement-proposals/eep-0048.html
[5]: https://www.erlang.org/doc/man/shell_docs.html
