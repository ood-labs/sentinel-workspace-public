#include "types.hlsli"
#include "../_shared/ui/sui_interaction.hlsli"
#include "_ui.generated.hlsli"
StructuredBuffer<MassingState> _Tex0 : register(t0);
StructuredBuffer<PNode> _Tex1 : register(t1);
RWStructuredBuffer<EditorState> OutputBuffer : register(u0);

bool hitSelectedBody(float2 pointer, uint objectId, EditorState st) {
    float2 world = pbPlanWorld(pointer, st.view_pan, st.view_zoom);
    float2 low = 1e6, high = -1e6;
    [loop] for (uint i = 0u; i < PB_RECORD_COUNT; ++i) if (pbObjectForRecord(i) == objectId) {
        PNode n = _Tex1[i]; float2 halfExtent = max(float2(n.width, n.depth) * 0.5, 0.08);
        low = min(low, n.position.xz - halfExtent); high = max(high, n.position.xz + halfExtent);
    }
    float padding = 0.55 / max(st.view_zoom, 0.4);
    return all(world >= low - padding) && all(world <= high + padding);
}

[numthreads(1,1,1)]
void main(uint3 tid : SV_DispatchThreadID) {
    EditorState st = OutputBuffer[0];
    float modeParam = clamp((float)tool_mode, 0.0, 1.0); float snapParam = snap_enabled ? 1.0 : 0.0;
    if (abs(st.marker - 9241.0) > 0.5) {
        st = (EditorState)0; st.mode = modeParam; st.snap_enabled = snapParam; st.snap_step = snap_step; st.marker = 9241.0;
        st.pad.xy = float2(snapParam, modeParam); st.view_zoom = 1.0;
    }
    st.command = 0.0; st.snap_step = snap_step;
    if (abs(modeParam - st.pad.y) > 0.1) { st.mode = modeParam; st.pad.y = modeParam; }
    if (abs(snapParam - st.pad.x) > 0.1) { st.snap_enabled = snapParam; st.pad.x = snapParam; }

    uint down = (suiInteraction(UI_INDEX_MOVE).down ? 1u : 0u) |
                (suiInteraction(UI_INDEX_ROTATE).down ? 2u : 0u) |
                (suiInteraction(UI_INDEX_RESET).down ? 4u : 0u) |
                (suiInteraction(UI_INDEX_RESET_ALL).down ? 8u : 0u) |
                (suiInteraction(UI_INDEX_FIT).down ? 16u : 0u);
    uint pressed = down & ~(uint)round(st.control_latch); st.control_latch = (float)down;
    if ((pressed & 1u) != 0u) st.mode = 0.0;
    if ((pressed & 2u) != 0u) st.mode = 1.0;
    if ((pressed & 4u) != 0u && _ViewportSelectionMeta.y > 0u) { st.active_id = (float)_ViewportSelectionMeta.y; st.command = 7.0; }
    if ((pressed & 8u) != 0u) st.command = 8.0;
    if ((pressed & 16u) != 0u) { st.view_pan = 0.0; st.view_zoom = 1.0; }

    bool beganThisCook = false; uint count = min(_ViewportEventCount, 64u);
    [loop] for (uint i = 0u; i < count; ++i) {
        ViewportEvent e = _ViewportEvents[i];
        if (e.type == 2u && e.code == 2u) {
            if (e.phase == 1u) st.middle_down = 1.0;
            if (e.phase == 3u || e.phase == 8u) st.middle_down = 0.0;
        }
        if (e.type == 2u && e.code == 0u && e.phase == 1u && pbInPlan(e.position) && st.dragging < 0.5) {
            uint selected = _ViewportSelectionMeta.y;
            if (selected > 0u && hitSelectedBody(e.position, selected, st)) {
                st.active_id = (float)selected; st.drag_start = e.position; st.pointer = e.position; st.pad.z = (float)selected; st.pad.w = 1.0;
            }
        }
        if (e.type == 2u && e.code == 0u && e.phase == 3u && st.dragging < 0.5) st.pad.zw = 0.0;
        if (e.type == 1u && st.middle_down > 0.5 && pbInPlan(e.position)) {
            float2 localDelta = e.delta / max(PB_PLAN_RECT.zw - PB_PLAN_RECT.xy, 0.001);
            st.view_pan -= float2(localDelta.x, -localDelta.y) * pbPlanSpan() / max(st.view_zoom, 0.01);
        }
        if (e.type == 3u && pbInPlan(e.position)) {
            float notches = abs(e.value) > 0.001 ? e.value : e.delta.y;
            float2 anchorBefore = pbPlanWorld(e.position, st.view_pan, st.view_zoom);
            st.view_zoom = clamp(st.view_zoom * pow(1.12, notches), 0.40, 4.50);
            st.view_pan = anchorBefore - pbPlanBaseWorld(e.position) / st.view_zoom;
        }
        if (e.type == 4u && e.phase == 1u) {
            if (e.code == 13u) st.mode = 0.0;
            if (e.code == 20u) st.mode = 1.0;
            if (e.code == 19u) st.snap_enabled = 1.0 - st.snap_enabled;
            if (e.code == 6u) { st.view_pan = 0.0; st.view_zoom = 1.0; }
            if (e.code == 52u) {
                bool shift = (e.modifiers & VIEWPORT_MODIFIER_SHIFT) != 0u;
                if (shift) st.command = 8.0;
                else if (_ViewportSelectionMeta.y > 0u) { st.active_id = (float)_ViewportSelectionMeta.y; st.command = 7.0; }
            }
            if (e.code == 48u && st.dragging > 0.5) { st.command = 4.0; st.dragging = 0.0; }
        }
        bool anyLeftDrag = e.type == 5u && e.code == 3u && e.device == 0u;
        bool hostSelectionDrag = anyLeftDrag && (e.flags & 16u) != 0u;
        bool armedBodyDrag = anyLeftDrag && st.pad.w > 0.5;
        if (!hostSelectionDrag && !armedBodyDrag) continue;
        if (e.phase == 5u && _ViewportSelectionMeta.y > 0u) {
            st.active_id = armedBodyDrag ? st.pad.z : (float)_ViewportSelectionMeta.y;
            if (!armedBodyDrag) st.drag_start = e.position;
            st.pointer = e.position; st.dragging = 1.0; st.command = 1.0; beganThisCook = true;
        } else if (st.dragging > 0.5 && (e.phase == 6u || e.phase == 7u || e.phase == 8u)) {
            st.pointer = e.position;
            if (e.phase == 8u) { st.command = 4.0; st.dragging = 0.0; st.pad.zw = 0.0; }
            else if (e.phase == 7u) { st.command = beganThisCook ? 5.0 : 3.0; st.dragging = 0.0; st.pad.zw = 0.0; }
            else st.command = beganThisCook ? 6.0 : 2.0;
        }
    }
    OutputBuffer[0] = st;
}
