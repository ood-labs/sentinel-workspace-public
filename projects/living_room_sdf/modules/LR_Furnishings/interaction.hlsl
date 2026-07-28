#include "types.hlsli"
#include "../_shared/ui/sui3_events.hlsli"
#include "_ui.generated.hlsli"
StructuredBuffer<FurnishingState> _Tex0 : register(t0);
StructuredBuffer<PNode> _Tex1 : register(t1);
RWStructuredBuffer<EditorState> OutputBuffer : register(u0);

bool hitSelectedBody(float2 pointer, uint objectId, EditorState st) {
    float2 world = lrPlanWorld(pointer, st.view_pan, st.view_zoom);
    float2 pivot = 0.0; float count = 0.0;
    [loop] for (uint i = 0u; i < LR_RECORD_COUNT; ++i) if (lrObjectForRecord(i) == objectId) {
        pivot += _Tex1[i].position.xz; count += 1.0;
    }
    pivot /= max(count, 1.0);
    FurnishingState state = _Tex0[objectId - 1u];
    float2 low = 1e6, high = -1e6;
    [loop] for (uint i = 0u; i < LR_RECORD_COUNT; ++i) if (lrObjectForRecord(i) == objectId) {
        PNode n = _Tex1[i];
        float2 position = pivot + lrRotate(n.position.xz - pivot, state.yaw_offset) + state.offset;
        float2 half = max(float2(n.width, n.depth) * 0.5, 0.06);
        low = min(low, position - half);
        high = max(high, position + half);
    }
    // Keep narrow lamps, plants, and chairs easy to acquire, and include the
    // visible gizmo handles around the selected assembly.
    float padding = 0.78 / max(st.view_zoom, 0.4);
    return all(world >= low - padding) && all(world <= high + padding);
}

[numthreads(1,1,1)]
void main(uint3 tid : SV_DispatchThreadID) {
    EditorState st = OutputBuffer[0];
    float modeParam = clamp((float)tool_mode, 0.0, 1.0);
    float snapParam = snap_enabled ? 1.0 : 0.0;
    if (abs(st.marker - 7421.0) > 0.5) {
        st = (EditorState)0; st.mode = modeParam; st.snap_enabled = snapParam;
        st.snap_step = snap_step; st.marker = 7421.0; st.pad.xy = float2(snapParam, modeParam);
        st.view_pan = 0.0; st.view_zoom = 1.0; st.middle_down = 0.0;
    }
    st.command = 0.0; st.snap_step = snap_step;
    if (abs(modeParam - st.pad.y) > 0.1) { st.mode = modeParam; st.pad.y = modeParam; }
    if (abs(snapParam - st.pad.x) > 0.1) { st.snap_enabled = snapParam; st.pad.x = snapParam; }

    float4 controlRects[8] = {
        UI_RECT_MOVE * float4(_Resolution.xy, _Resolution.xy),
        UI_RECT_ROTATE * float4(_Resolution.xy, _Resolution.xy),
        UI_RECT_SNAP * float4(_Resolution.xy, _Resolution.xy),
        UI_RECT_FIT * float4(_Resolution.xy, _Resolution.xy),
        UI_RECT_RESET * float4(_Resolution.xy, _Resolution.xy),
        UI_RECT_RESET_ALL * float4(_Resolution.xy, _Resolution.xy),
        float4(0.0, 0.0, 0.0, 0.0),
        float4(0.0, 0.0, 0.0, 0.0)
    };
    int controlHit = sui3HitBank(0.0, controlRects, 6);
    if (controlHit == 0) st.mode = 0.0;
    if (controlHit == 1) st.mode = 1.0;
    // Snap remains a host-owned bool parameter. The completed click toggles
    // that parameter, and the ordinary parameter reconciliation above mirrors
    // it into editor state.
    if (controlHit == 3) { st.view_pan = 0.0; st.view_zoom = 1.0; }
    if (controlHit == 4 && _ViewportSelectionMeta.y > 0u) {
        st.active_id = (float)_ViewportSelectionMeta.y; st.command = 7.0;
    }
    if (controlHit == 5) st.command = 8.0;

    bool beganThisCook = false;
    uint count = min(_ViewportEventCount, 64u);
    [loop] for (uint i = 0u; i < count; ++i) {
        ViewportEvent e = _ViewportEvents[i];
        if (e.type == 2u && e.code == 2u) {
            if (e.phase == 1u) st.middle_down = 1.0;
            if (e.phase == 3u || e.phase == 8u) st.middle_down = 0.0;
        }
        if (e.type == 2u && e.code == 0u && e.phase == 1u && e.position.y >= LR_PLAN_TOP && st.dragging < 0.5) {
            uint selected = _ViewportSelectionMeta.y;
            if (selected > 0u && hitSelectedBody(e.position, selected, st)) {
                st.active_id = (float)selected;
                st.drag_start = e.position;
                st.pointer = e.position;
                st.pad.z = (float)selected;
                st.pad.w = 1.0;
            }
        }
        if (e.type == 2u && e.code == 0u && e.phase == 3u && st.dragging < 0.5) {
            st.pad.zw = 0.0;
        }
        if (e.type == 1u && st.middle_down > 0.5 && e.position.y >= LR_PLAN_TOP) {
            float2 worldDelta = float2(e.delta.x * lrPlanSpan().x, -e.delta.y * lrPlanSpan().y / (1.0 - LR_PLAN_TOP));
            st.view_pan -= worldDelta / max(st.view_zoom, 0.01);
        }
        if (e.type == 3u && e.position.y >= LR_PLAN_TOP) {
            float notches = abs(e.value) > 0.001 ? e.value : e.delta.y;
            float2 anchorBefore = lrPlanWorld(e.position, st.view_pan, st.view_zoom);
            st.view_zoom = clamp(st.view_zoom * pow(1.12, notches), 0.40, 4.50);
            st.view_pan = anchorBefore - lrPlanBaseWorld(e.position) / st.view_zoom;
        }
        if (e.type == 4u && e.phase == 1u) {
            if (e.code == 13u) st.mode = 0.0; // M
            if (e.code == 20u) st.mode = 1.0; // T
            if (e.code == 19u) st.snap_enabled = 1.0 - st.snap_enabled; // S
            if (e.code == 6u) { st.view_pan = 0.0; st.view_zoom = 1.0; } // F
            if (e.code == 52u) { // Backspace
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
