#ifndef DADA_EDIT_TYPES_HLSLI
#define DADA_EDIT_TYPES_HLSLI

struct DadaPart {
    float2 pos_xy; float2 sc_xy;
    float pos_z; float sc_z; float yaw; float tilt; float roll;
    float kind; float mat; float group; float p0; float p1; float p2; float active;
};

struct AssemblyOverride {
    float2 offset;
    float rotation;
    float scale;
    uint object_id;
    float marker;
    float2 pad;
};

struct AssemblyEditState {
    float active_id;
    float dragging;
    float command;
    uint sequence;
    float2 pointer;
    float2 start_pointer;
    float2 snapshot_offset;
    float snapshot_rotation;
    float snapshot_scale;
    float tool_mode;
    float3 pad;
};

static const float2 DADA_W_MIN = float2(-3.7, -0.4);
static const float2 DADA_W_MAX = float2( 3.7,  9.8);

float2 dadaWorldToUv(float2 worldPos)
{
    float2 uv = (worldPos - DADA_W_MIN) / (DADA_W_MAX - DADA_W_MIN);
    uv.y = 1.0 - uv.y;
    return uv;
}

#endif
