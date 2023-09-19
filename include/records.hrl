-record(container, {
    %% Implementing module, e.g. `orddict'
    module :: module(),
    %% The type of container, usually the same as `module', but not always
    type :: atom(),
    %% Random orddict, used to generate the example value for this container
    orddict = neo_proper_types:orddict_type() :: orddict:orddict(),
    %% The example value
    collection :: term(),
    %% Function names for the various operations needed
    delete = delete :: neo_proper_types:function_reference(),
    equals = fun erlang:'=:='/2 :: neo_proper_types:function_reference(),
    from_list = from_list :: neo_proper_types:function_reference(),
    get = get :: neo_proper_types:function_reference(),
    keys = keys :: neo_proper_types:function_reference(),
    new = new :: neo_proper_types:function_reference(),
    size = size :: neo_proper_types:function_reference(),
    to_list = to_list :: neo_proper_types:function_reference()
}).

-record(stream_operator, {
    type :: map | filter | filtermap,
    module = orddict :: module(),
    orddict_function :: fun(),
    stream_function :: fun()
}).
