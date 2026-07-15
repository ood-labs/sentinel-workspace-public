#include "node_edit_types.hlsli"

StructuredBuffer<NodeEditState> _Tex0 : register(t0);
StructuredBuffer<NodeOverride> _Tex1 : register(t1);
RWStructuredBuffer<NodeOverride> OutputBuffer : register(u0);

void initializeOverrides(uint guardToken)
{
    [unroll] for (uint i = 0u; i < 12u; ++i) {
        NodeOverride edit = (NodeOverride)0;
        edit.object_id = i + 1u;
        edit.marker = i == 0u ? 42120.0 : 0.0;
        OutputBuffer[i] = edit;
    }
    NodeOverride guard = (NodeOverride)0;
    guard.object_id = guardToken;
    guard.marker = 42120.0;
    OutputBuffer[12] = guard;
}

[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    NodeEditState state = _Tex0[0];
    if (reset_offsets != 0) { initializeOverrides(state.sequence); return; }
    if (abs(OutputBuffer[0].marker - 42120.0) > 0.5) { initializeOverrides(state.sequence); return; }
    uint command = (uint)round(state.command);
    if (command < 2u || command > 4u || state.active_id < 1.0 || state.active_id > 12.0) return;
    if (state.sequence == 0u || state.sequence == _Tex1[12].object_id) return;
    uint index = (uint)round(state.active_id) - 1u;
    NodeOverride edit = _Tex1[index];
    edit.object_id = index + 1u;
    edit.offset = state.snapshot_offset;
    if (command != 4u) edit.offset += state.pointer - state.start_pointer;
    edit.offset = clamp(edit.offset, -0.25, 0.25);
    OutputBuffer[index] = edit;
    NodeOverride guard = _Tex1[12];
    guard.object_id = state.sequence;
    guard.marker = 42120.0;
    OutputBuffer[12] = guard;
}
