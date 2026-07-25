// AUTOPSIA — performance deck state.
// Publishes the pad positions and the selected look as control outputs so the
// rest of the graph can be driven by expressions. The host owns the pads
// themselves (viewport.controls), so this pass only mirrors them into a buffer.
//
// Layout (float, one per control_output offset):
//   0 field_x   4 field_y   8 relief_x  12 relief_y
//  16 print_x  20 print_y  24 look      28 hold
//   Deck[2] = selection state
//
// LOOK SELECTION IS EVENT-DRIVEN, NOT PARAMETER-DRIVEN.
// `button`-type parameters do NOT deliver a usable pressed level to the shader:
// they read as a constant 1.0 every frame regardless of the value reported in
// the state tree. Testing their level made the last button in the chain win
// permanently (stuck on Section); edge-detecting them fired every button once on
// the first frame and then froze forever. So the four look buttons are hit-
// tested here against real click gestures, which carry an unambiguous position
// and a single completion phase. (`bool` parameters are unaffected and are
// still read normally -- see hold_field below.)
RWStructuredBuffer<float4> Deck : register(u0);

bool inRect(float2 p, float4 r) {
    return p.x >= r.x && p.x <= r.z && p.y >= r.y && p.y <= r.w;
}

[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    float4 sel = Deck[2];
    if (sel.w < 0.5 || isnan(sel.x)) sel = float4(2.0, 0.0, 0.0, 1.0);   // Register default

    // Button rects, in the same normalized space the renderer draws them.
    float4 bImpression = float4(0.040, 0.845, 0.255, 0.930);
    float4 bInspection = float4(0.275, 0.845, 0.490, 0.930);
    float4 bRegister   = float4(0.510, 0.845, 0.725, 0.930);
    float4 bSectioned  = float4(0.745, 0.845, 0.950, 0.930);

    uint count = min(_ViewportEventCount, 64u);
    [loop] for (uint i = 0u; i < count; ++i) {
        ViewportEvent e = _ViewportEvents[i];
        // one completed click arrives as type 5 / code 1 / phase 7
        if (!(e.type == 5u && e.code == 1u && e.phase == 7u)) continue;
        float2 p = e.position;
        if      (inRect(p, bImpression)) sel.x = 0.0;
        else if (inRect(p, bInspection)) sel.x = 1.0;
        else if (inRect(p, bRegister))   sel.x = 2.0;
        else if (inRect(p, bSectioned))  sel.x = 3.0;
    }

    sel.y = hold_field > 0.5 ? 1.0 : 0.0;

    // point2D parameters arrive as float2 in the shader, not flattened components.
    //
    // Y IS FLIPPED EXACTLY ONCE, HERE. The host stores pad Y increasing DOWNWARD
    // (0 at the top of the control rect), but every macro axis is authored so
    // that "up = more". Publishing 1-y makes the control outputs carry the
    // semantic value, while the renderer's own 1-y undoes it and lands the
    // reticle back on the raw pointer position. Flipping in the renderer instead
    // mirrored the reticle against the mouse.
    Deck[0] = float4(saturate(pad_field.x),  saturate(1.0 - pad_field.y),
                     saturate(pad_relief.x), saturate(1.0 - pad_relief.y));
    Deck[1] = float4(saturate(pad_print.x),  saturate(1.0 - pad_print.y), sel.x, sel.y);
    Deck[2] = sel;
    Deck[3] = float4(0.0, 0.0, 0.0, 0.0);
}
