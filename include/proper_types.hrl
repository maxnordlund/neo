-ifndef(NEO_PROPER_TYPES).
-define(NEO_PROPER_TYPES, true).

-include("records.hrl").

-import(neo_proper_types, [
    container_of_containers_type/1,
    container_record_type/1,
    container_type/0,
    container_type/1,
    container_with_key_type/0,
    container_with_key_type/1,
    container_with_missing_key_type/1,
    container_with_missing_key_type/2,
    container_with_missing_settable_key_type/2,
    key_type/0,
    orddict_type/0,
    orddict_type/2,
    value_type/0
]).

-endif.
