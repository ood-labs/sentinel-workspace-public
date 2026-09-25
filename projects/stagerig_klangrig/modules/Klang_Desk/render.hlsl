// Klang_Desk: a Push-free desk drawn from the host's per-control state.
// Clicks leave on the `panel` Event output; the Surface Script answers with
// lit/state/color feedback, which arrives here through _ViewportControlState.
#include "../_shared/ui/show_controls.hlsli"
#include "desk_layout.hlsli"

float3 deskRole(uint role) {
    switch (role) {
        case 1: return SC_ACCENT;
        case 2: return SC_ROLE_GO;
        case 3: return SC_ROLE_KILL;
        case 4: return SC_ROLE_WARN;
        case 5: return SC_ROLE_FREEZE;
        case 6: return SC_ROLE_LINK;
        default: return SC_ROLE_NEUTRAL;
    }
}

float4 main(VS_OUTPUT In) : SV_TARGET0 {
    float2 p = In.Uv * _Resolution;
    float2 k = _Resolution / DESK_SIZE;       // layout pixels -> output pixels
    float text = 14.0 * min(k.x, k.y);
    float3 color = SC_SURFACE_BASE;
    [loop] for (uint i = 0; i < DESK_COUNT; i++) {
        float4 r = DESK_RECT[i] * float4(_Resolution, _Resolution);
        if (p.x < r.x - 4.0 || p.x > r.z + 4.0 || p.y < r.y - 4.0 || p.y > r.w + 4.0) continue;
        float3 role = deskRole(DESK_ROLE[i]);
        if (DESK_KIND[i] == 0) {
            scPad(color, p, r.xy, r.zw, i, role, text, DESK_ROLE[i] == 3 || DESK_ROLE[i] == 4);
        } else if (DESK_KIND[i] == 1) {
            scReadout(color, p, r.xy, r.zw, i, SC_TEXT_PRIMARY, 30.0 * min(k.x, k.y), 1);
        } else if (DESK_KIND[i] == 3) {
            scReadout(color, p, r.xy, r.zw, i, SC_TEXT_MUTED, 18.0 * min(k.x, k.y), 1);
        } else {
            scHeader(color, p, r.xy, r.zw, i, 16.0 * min(k.x, k.y));
        }
    }
    return float4(color, 1.0);
}
