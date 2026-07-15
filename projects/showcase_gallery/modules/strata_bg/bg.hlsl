// strata_bg — the neutral studio backdrop (plate 0, bottom). A cool-gray gradient void with
// subtle vertical panel rectangles + faint horizontal steps (the framing panels behind the
// mass in ref #7) and a soft vignette. Opaque (alpha 1). 2D screen-space, no camera.
#include "../_shared/palette.hlsli"

RWTexture2D<float4> OutputUAV : register(u0);

float h11(float p) { p = frac(p * 0.1031); p *= p + 33.33; p *= p + p; return frac(p); }

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 px = DTid.xy;
    if (px.x >= (uint)_Resolution.x || px.y >= (uint)_Resolution.y) return;
    float2 res = _Resolution.xy;
    float2 uv = ((float2)px + 0.5) / res;             // y-down
    float2 uvy = float2(uv.x, 1.0 - uv.y);            // y-up for studio

    float3 col = str_studio(uvy) * bg_bright;

    // ---- vertical framing panels: a few bands of slightly offset value with thin seams ----
    if (panel_amt > 0.001)
    {
        float bands = 5.0;
        float fx = uv.x * bands + panel_seed * 3.1;
        float cell = floor(fx);
        float v = (h11(cell * 1.7 + panel_seed) - 0.5) * 0.09 * panel_amt;   // per-panel value shift
        col *= 1.0 + v;
        float seam = frac(fx);
        float sw = 1.2 / res.x * bands;                                       // ~1px seam
        float seamMask = smoothstep(sw, 0.0, seam) + smoothstep(1.0 - sw, 1.0, seam);
        col *= 1.0 - 0.10 * panel_amt * seamMask;                            // thin darker seams
    }
    // one horizontal step (a lighter upper band, like the ref's top panel)
    float step_y = 0.30 + panel_step * 0.5;
    col *= 1.0 + 0.05 * panel_amt * smoothstep(0.01, 0.0, uv.y - step_y);

    // gentle film grain to kill banding on the smooth gradient
    float g = (h11(dot((float2)px, float2(1.0, res.x)) + 7.0) - 0.5) * 0.012;
    col += g;

    OutputUAV[px] = float4(saturate(col), 1.0);
}
