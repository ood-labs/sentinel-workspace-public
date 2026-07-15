#include "fruit_scene_types.hlsli"

StructuredBuffer<CardEditState> _Tex0 : register(t0);
StructuredBuffer<CardOverride> _Tex1 : register(t1);
RWStructuredBuffer<CardOverride> OutputBuffer : register(u0);

void initializeCards() {
    [loop] for (uint i = 0u; i < 64u; ++i) {
        CardOverride edit = (CardOverride)0;
        edit.scale = 1.0;
        edit.object_id = i + 1u;
        edit.marker = i == 0u ? 7419.0 : 0.0;
        OutputBuffer[i] = edit;
    }
}

[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    if (abs(OutputBuffer[0].marker - 7419.0) > 0.5) initializeCards();
    CardEditState state = _Tex0[0];
    uint command = (uint)round(state.command);
    if (command < 2u || command > 4u || state.active_id < 1.0) return;

    uint index = min((uint)round(state.active_id) - 1u, 63u);
    CardOverride edit = _Tex1[index];
    edit.offset = state.snapshot_offset;
    edit.rotation = state.snapshot_rotation;
    edit.scale = max(state.snapshot_scale, 0.05);
    if (command != 4u) {
        float2 deltaPixels = (state.pointer - state.start_pointer) * max(_Resolution.xy, 1.0.xx);
        uint mode = (uint)clamp(round(state.mode), 0.0, 2.0);
        if (mode == 0u) edit.offset += float3(deltaPixels.x / 90.0, -deltaPixels.y / 90.0, 0.0);
        if (mode == 1u) edit.rotation += (deltaPixels.x - deltaPixels.y) * 0.012;
        if (mode == 2u) edit.scale *= max(0.10, 1.0 + (deltaPixels.x - deltaPixels.y) / 180.0);
    }
    OutputBuffer[index] = edit;
}
