// Style Authority - publish the live theme.
//
// This pass is what makes the station load-bearing rather than illustrative:
// every value here leaves the node as a control output, so the other stations
// bind to it with sentinel_expression and retune when it moves.
//
// Includes core only. `sui3_events.hlsli` is deliberately NOT included here --
// the events pass owns the event stream and hands this pass a plain buffer, so
// nothing downstream of the hit-test needs the interaction bindings.
// `au_text.hlsli:9` records the v1 kit failing to compile by pulling event
// bindings into a pass that never declared them.
#include "../_shared/ui/sui3_core.hlsli"

RWStructuredBuffer<float4> Theme : register(u0);

[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    Theme[0] = float4(title_scale, section_scale, body_scale, exposure);
    Theme[1] = float4(outer_padding, section_gap, control_height, control_gap);
    Theme[2] = float4(accent_color.r, accent_color.g, accent_color.b, saturate(demo_value));

    // The PARAMETERS are the single source of truth. `viewport.controls` has
    // the host write them on drag, so there is no second copy of interaction
    // state to keep in sync -- which is exactly why undo, presets and project
    // save work without this module doing anything.
    //
    // Y flipped exactly once, here, at publish time. The stored pad_y is the
    // host's down=more convention so the renderer draws the reticle under the
    // pointer; what LEAVES the node means up=more.
    float2 pub = sui3PublishPad(demo_pad);
    Theme[3] = float4(pub.x, pub.y,
                      demo_toggle > 0.5 ? 1.0 : 0.0,
                      (float)clamp(demo_bank, 0, 3));
}
