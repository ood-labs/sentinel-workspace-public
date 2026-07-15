#ifndef TOPO_NODE_EDIT_TYPES_HLSLI
#define TOPO_NODE_EDIT_TYPES_HLSLI

struct NodeOverride {
    float2 offset;
    uint object_id;
    float marker;
};

struct NodeEditState {
    float active_id;
    float dragging;
    float command;
    uint sequence;
    float2 pointer;
    float2 start_pointer;
    float2 snapshot_offset;
    float2 pad1;
};

struct NodeRecord {
    float2 pos;
    float radius;
    float intensity;
    float color_mix;
    float kind;
    float seed;
    float active;
};

#endif
