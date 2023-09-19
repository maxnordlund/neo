%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% @doc Parse transform which adds a record_info/0 and record_info/1 function
%%% to the transformed module.
%%%
%%% These gives runtime access to the fields and size of a record, just like
%%% the compile time pseudo-function record_info/2.
%%%
%%% This is only used by the tests, but because rebar3 does not like inline
%%% parse transforms under "test/" it has to live here in "src/". This also
%%% means we need to ignore a few warnings from Xref, as it correctly tells us
%%% that the functions from {@link merlin} are not available in the default
%%% profile.
%%% @end
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%%%_* Module declaration =====================================================
-module(neo_record_info_transform).

%%%_* Exports ================================================================
%%%_ * API -------------------------------------------------------------------
%%%_ * Callbacks -------------------------------------------------------------
-export([
    parse_transform/2
]).

%%%_* Types ------------------------------------------------------------------

%%%_* Includes ===============================================================
-include_lib("syntax_tools/include/merl.hrl").

%%%_* Macros =================================================================

%%%_* Types ==================================================================

%%%_* Code ===================================================================
%%%_ * API -------------------------------------------------------------------

%%%_ * Callbacks -------------------------------------------------------------
-spec parse_transform(Forms, Options) -> Forms when
    Forms :: [erl_parse:abstract_form()],
    Options :: [compile:option()].
parse_transform(Forms0, _Options) ->
    Records = [
        Record
     || {attribute, _, record, _} = Record <- Forms0
    ],
    case Records of
        [] ->
            Forms0;
        _ ->
            RecordInfoFunctions0 = record_info_functions(Records),
            RecordInfoFunctions1 = adjust_line_numbers(
                lists:last(Forms0), RecordInfoFunctions0
            ),
            Forms1 = Forms0 ++ RecordInfoFunctions1,
            merlin:return(
                merlin_module:export(Forms1, [{record_info, 0}, {record_info, 1}])
            )
    end.

%%%_* Private ----------------------------------------------------------------
record_info_functions(Records) ->
    Info = lists:map(fun record_info_clause/1, Records),
    MapAssociations = [
        erl_syntax:map_field_assoc(Tag, ?Q("record_info(_@Tag)"))
     || {Tag, _, _} <- Info
    ],
    Clauses = [
        ?Q([
            "(_@Tag) ->",
            "    #{",
            "        fields => [_@FieldNames],",
            "        size => _@Size@",
            "    }"
        ])
     || {Tag, Size, FieldNames} <- Info
    ],
    ?Q([
        "record_info() ->",
        "   #{_ => _@_MapAssociations}.",
        "",
        "record_info(_@_) ->",
        "   _@_Clauses."
    ]).

record_info_clause(Record) ->
    ?Q("-record('@Tag', {'@_@Fields' = _}).") = Record,
    Size = length(Fields) + 1,
    FieldNames = [
        case erl_syntax:type(Field) of
            record_field ->
                erl_syntax:record_field_name(Field);
            typed_record_field ->
                erl_syntax:record_field_name(erl_syntax:typed_record_field_body(Field))
        end
     || Field <- Fields
    ],
    {Tag, Size, FieldNames}.

adjust_line_numbers(LastForm, [RecordInfoFunction | _] = RecordInfoFunctions) ->
    LastAnno = erl_syntax:get_pos(LastForm),
    LastLine =
        case erl_anno:end_location(LastAnno) of
            undefined -> erl_anno:line(LastAnno);
            EndLocation -> erl_anno:line(erl_anno:from_term(EndLocation))
        end,
    Difference = LastLine - merlin_annotations:get(RecordInfoFunction, line),
    merlin:return(
        merlin:transform(
            RecordInfoFunctions, fun adjust_line_transformer/3, Difference
        )
    ).

adjust_line_transformer(exit, Node, Difference) ->
    Line = merlin_annotations:get(Node, line),
    merlin_annotations:merge(Node, #{
        line => Line + Difference,
        generated => true
    });
adjust_line_transformer(_, _, _) ->
    continue.

%%%_* Tests ==================================================================
-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif.
