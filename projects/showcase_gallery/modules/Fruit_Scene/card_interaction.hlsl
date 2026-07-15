#include "fruit_scene_types.hlsli"

StructuredBuffer<CardOverride> _Tex0 : register(t0);
RWStructuredBuffer<CardEditState> OutputBuffer : register(u0);

[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    CardEditState state = OutputBuffer[0];
    if (state.mode < 0.0 || state.mode > 2.0 || isnan(state.mode)) state = (CardEditState)0;
    if (state.dragging < 0.5) state.mode = (float)clamp(transform_mode, 0, 2);
    state.command = 0.0;

    uint events = min(_ViewportEventCount, 64u);
    [loop] for (uint i = 0u; i < events; ++i) {
        ViewportEvent e = _ViewportEvents[i];
        if (e.type == 4u && e.phase == 1u) {
            if (e.code == 33u) state.mode = 0.0;
            if (e.code == 34u) state.mode = 1.0;
            if (e.code == 35u) state.mode = 2.0;
            if (e.code == 48u && state.dragging > 0.5) {
                state.command = 4.0;
                state.dragging = 0.0;
            }
        }

        bool hostSelectionDrag = e.type == 5u && e.code == 3u && e.device == 0u && (e.flags & 16u) != 0u;
        if (!hostSelectionDrag) continue;

        if (e.phase == 5u && _ViewportSelectionMeta.y > 0u) {
            uint activeId = _ViewportSelectionMeta.y;
            uint index = min(activeId - 1u, 63u);
            CardOverride edit = _Tex0[index];
            state.active_id = (float)activeId;
            state.dragging = 1.0;
            state.command = 1.0;
            state.start_pointer = e.position;
            state.pointer = e.position;
            state.snapshot_offset = edit.offset;
            state.snapshot_rotation = edit.rotation;
            state.snapshot_scale = edit.scale;
        } else if (state.dragging > 0.5 && (e.phase == 6u || e.phase == 7u || e.phase == 8u)) {
            state.pointer = e.position;
            if (e.phase == 6u) state.command = 2.0;
            if (e.phase == 7u) { state.command = 3.0; state.dragging = 0.0; }
            if (e.phase == 8u) { state.command = 4.0; state.dragging = 0.0; }
        }
    }
    OutputBuffer[0] = state;
}
