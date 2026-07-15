#ifndef TOPO_LABEL_EDIT_TYPES_HLSLI
#define TOPO_LABEL_EDIT_TYPES_HLSLI

struct LabelOverride {
    float2 offset;
    uint object_id;
    float marker;
};

struct LabelEditState {
    float active_id;
    float dragging;
    float command;
    uint sequence;
    float2 pointer;
    float2 start_pointer;
    float2 snapshot_offset;
    float2 pad1;
};

struct LabelRecord {
    float2 pos;
    float scale;
    float label_id;
    float color_mix;
    float rotation;
    float active;
    float pad0;
};

#endif
