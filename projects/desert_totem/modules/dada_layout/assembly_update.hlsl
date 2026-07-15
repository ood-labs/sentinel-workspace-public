#include "dada_edit_types.hlsli"

StructuredBuffer<AssemblyEditState> _Tex0 : register(t0);
StructuredBuffer<AssemblyOverride> _Tex1 : register(t1);
RWStructuredBuffer<AssemblyOverride> OutputBuffer : register(u0);

static const float EDIT_MARKER = 62145.0;

void initializeOverrides(uint guardToken)
{
    [unroll] for (uint i = 0u; i < 4u; ++i) {
        AssemblyOverride edit = (AssemblyOverride)0;
        edit.scale = 1.0;
        edit.object_id = i + 1u;
        edit.marker = i == 0u ? EDIT_MARKER : 0.0;
        OutputBuffer[i] = edit;
    }
    AssemblyOverride guard = (AssemblyOverride)0;
    guard.scale = 1.0;
    guard.object_id = guardToken;
    guard.marker = EDIT_MARKER;
    OutputBuffer[4] = guard;
}

[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    AssemblyEditState state = _Tex0[0];
    if (reset_overrides != 0) { initializeOverrides(state.sequence); return; }
    if (abs(OutputBuffer[0].marker - EDIT_MARKER) > 0.5) { initializeOverrides(state.sequence); return; }
    uint command = (uint)round(state.command);
    if (command < 2u || command > 4u || state.active_id < 1.0 || state.active_id > 4.0) return;
    if (state.sequence == 0u || state.sequence == _Tex1[4].object_id) return;

    uint index = (uint)round(state.active_id) - 1u;
    AssemblyOverride edit = _Tex1[index];
    edit.object_id = index + 1u;
    edit.offset = state.snapshot_offset;
    edit.rotation = state.snapshot_rotation;
    edit.scale = state.snapshot_scale;

    float2 delta = state.pointer - state.start_pointer;
    if (command != 4u) {
        uint tool = (uint)round(state.tool_mode);
        if (tool == 0u) edit.offset += float2(delta.x * 7.4, -delta.y * 10.2);
        if (tool == 1u) edit.rotation += delta.x * 4.5;
        if (tool == 2u) edit.scale += -delta.y * 2.4;
    }
    edit.offset = clamp(edit.offset, float2(-2.2, -2.2), float2(2.2, 2.2));
    edit.rotation = clamp(edit.rotation, -1.2, 1.2);
    edit.scale = clamp(edit.scale, 0.55, 1.65);
    edit.marker = index == 0u ? EDIT_MARKER : edit.marker;
    OutputBuffer[index] = edit;

    AssemblyOverride guard = _Tex1[4];
    guard.object_id = state.sequence;
    guard.marker = EDIT_MARKER;
    OutputBuffer[4] = guard;
}
