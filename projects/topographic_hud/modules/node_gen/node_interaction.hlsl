#include "node_edit_types.hlsli"

StructuredBuffer<NodeOverride> _Tex0 : register(t0);
RWStructuredBuffer<NodeEditState> OutputBuffer : register(u0);

uint editToken(ViewportEvent e)
{
    uint token = asuint(e.position.x)
        ^ (asuint(e.position.y) * 1664525u)
        ^ (e.phase * 1013904223u)
        ^ (e.code * 2246822519u);
    return token == 0u ? 1u : token;
}

[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    NodeEditState state = OutputBuffer[0];
    state.command = 0.0;
    uint events = min(_ViewportEventCount, 64u);
    [loop] for (uint i = 0u; i < events; ++i) {
        ViewportEvent e = _ViewportEvents[i];
        if (e.type == 4u && e.phase == 1u && e.code == 48u && state.dragging > 0.5) {
            state.command = 4.0;
            state.sequence = editToken(e);
            state.dragging = 0.0;
        }

        bool hostSelectionDrag = e.type == 5u && e.code == 3u && e.device == 0u && (e.flags & 16u) != 0u;
        if (!hostSelectionDrag) continue;
        if (e.phase == 5u && _ViewportSelectionMeta.y >= 1u && _ViewportSelectionMeta.y <= 12u) {
            uint objectId = _ViewportSelectionMeta.y;
            NodeOverride edit = _Tex0[objectId - 1u];
            state.active_id = (float)objectId;
            state.dragging = 1.0;
            state.command = 1.0;
            state.sequence = editToken(e);
            state.pointer = e.position;
            state.start_pointer = e.position;
            state.snapshot_offset = edit.offset;
        } else if (state.dragging > 0.5 && (e.phase == 6u || e.phase == 7u || e.phase == 8u)) {
            state.pointer = e.position;
            if (e.phase == 6u) { state.command = 2.0; state.sequence = editToken(e); }
            if (e.phase == 7u) { state.command = 3.0; state.sequence = editToken(e); state.dragging = 0.0; }
            if (e.phase == 8u) { state.command = 4.0; state.sequence = editToken(e); state.dragging = 0.0; }
        }
    }
    OutputBuffer[0] = state;
}
