#include "types.hlsli"
RWStructuredBuffer<ArchitectureEditorState> OutputBuffer : register(u0);

[numthreads(1,1,1)]
void main(uint3 tid : SV_DispatchThreadID) {
    ArchitectureEditorState st = OutputBuffer[0];
    if (abs(st.marker - 8137.0) > 0.5) {
        st = (ArchitectureEditorState)0;
        st.view_zoom = 1.0;
        st.marker = 8137.0;
    }

    uint count = min(_ViewportEventCount, 64u);
    [loop] for (uint i = 0u; i < count; ++i) {
        ViewportEvent e = _ViewportEvents[i];
        if (e.type == 2u && e.code == 2u) {
            if (e.phase == 1u) st.middle_down = 1.0;
            if (e.phase == 3u || e.phase == 8u) st.middle_down = 0.0;
        }
        if (e.type == 1u && st.middle_down > 0.5 && e.position.y >= ARCH_PLAN_TOP) {
            float2 worldDelta = float2(e.delta.x * archPlanSpan().x, -e.delta.y * archPlanSpan().y / (1.0 - ARCH_PLAN_TOP));
            st.view_pan -= worldDelta / max(st.view_zoom, 0.01);
        }
        if (e.type == 3u && e.position.y >= ARCH_PLAN_TOP) {
            float notches = abs(e.value) > 0.001 ? e.value : e.delta.y;
            float2 anchorBefore = archPlanWorld(e.position, st.view_pan, st.view_zoom);
            st.view_zoom = clamp(st.view_zoom * pow(1.12, notches), 0.40, 4.50);
            st.view_pan = anchorBefore - archPlanBaseWorld(e.position) / st.view_zoom;
        }
    }
    OutputBuffer[0] = st;
}
