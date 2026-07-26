// Style Authority - publish the live theme.
//
// This pass is what makes the station load-bearing rather than illustrative:
// every value here leaves the node as a control output, so the other stations
// bind to it with sentinel_expression and retune when it moves.
//
// Includes core only. `sui3_events.hlsli` is deliberately NOT included: this
// module declares no viewport interactions, and pulling in the event bindings
// would fail to compile. `au_text.hlsli:9` records the v1 kit doing exactly
// that.
#include "../_shared/ui/sui3_core.hlsli"

RWStructuredBuffer<float4> Theme : register(u0);

[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    Theme[0] = float4(title_scale, section_scale, body_scale, exposure);
    Theme[1] = float4(outer_padding, section_gap, control_height, control_gap);
    Theme[2] = float4(accent_color.r, accent_color.g, accent_color.b, saturate(demo_value));

    // point2D parameters arrive as float2 in the shader, not flattened
    // components. Y flipped exactly once, here, at publish time.
    float2 pub = sui3PublishPad(demo_pad);
    Theme[3] = float4(pub.x, pub.y,
                      demo_toggle > 0.5 ? 1.0 : 0.0,
                      (float)clamp(demo_bank, 0, 3));
}
