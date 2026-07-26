// CRYOGRAM / MEASUREMENT — human-readable inspection of the analysis branch.
//
// This output is NEVER wired into Features. It exists so the conditioning can
// be judged by eye: what the detector actually receives, the transfer curve
// being applied to it, and a live per-column density trace of the conditioned
// signal. Slot 0 ("Analysis") stays free of any drawn marks.

// Include the drawing primitives directly. sui_v2.hlsli also pulls in
// sui_interaction.hlsli, which requires _ViewportControlFlags — only injected
// for modules that declare viewport.controls. This node has no controls.
#include "../_shared/ui/sui_core.hlsli"
#include "../_shared/ui/sui_typography.hlsli"

RWTexture2D<float4> OutputUAV : register(u0);

static const float3 CRYO_INK = float3(0.93, 0.93, 0.94);
static const float3 CRYO_DIM = float3(0.42, 0.42, 0.45);

// "ANALYSIS"
static const int LBL_ANALYSIS[8] = { 65, 78, 65, 76, 89, 83, 73, 83 };

float cryoString(SuiContext c, float2 anchorUv, SuiTextStyle st, int codes[8], int n) {
    float cov = 0.0;
    float advance = 6.0 * st.scalePx + st.trackingPx;
    [loop] for (int i = 0; i < n; ++i) {
        float2 o = float2((float)i * advance, 0.0) * c.invResolution;
        cov = max(cov, suiGlyph(c, anchorUv + o, st, codes[i]));
    }
    return cov;
}

[numthreads(8, 8, 1)]
void main(uint3 id : SV_DispatchThreadID) {
    uint2 res = (uint2)_Resolution.xy;
    if (id.x >= res.x || id.y >= res.y) return;

    SuiContext c = suiContext(id.xy, _Resolution.xy);
    SuiTextStyle st = suiTextStyleTracked(1.0, 0.0, 0.0);

    float sig = _Tex0.Load(int3(id.xy, 0)).r;

    // conditioned signal, held back so the instrument marks stay on top
    float3 col = float3(sig, sig, sig) * 0.72;

    // ---- frame + corner registration --------------------------------------
    float4 frame = float4(9.0, 9.0, _Resolution.x - 9.0, _Resolution.y - 9.0) /
                   float4(_Resolution.xy, _Resolution.xy);
    suiComposite(col, CRYO_DIM, suiStrokeRect(c, frame, 1.0) * 0.85);

    float2 fp[4] = {
        float2(frame.x, frame.y), float2(frame.z, frame.y),
        float2(frame.x, frame.w), float2(frame.z, frame.w)
    };
    [unroll] for (int k = 0; k < 4; ++k) {
        suiComposite(col, CRYO_INK, suiLinePx(c, fp[k] - float2(7.0, 0.0) * c.invResolution,
                                                 fp[k] + float2(7.0, 0.0) * c.invResolution, 1.0));
        suiComposite(col, CRYO_INK, suiLinePx(c, fp[k] - float2(0.0, 7.0) * c.invResolution,
                                                 fp[k] + float2(0.0, 7.0) * c.invResolution, 1.0));
    }

    // ---- label + real output extent ---------------------------------------
    float2 lblAt = float2(16.0, 14.0) * c.invResolution;
    suiComposite(col, CRYO_INK, cryoString(c, lblAt, st, LBL_ANALYSIS, 8));

    // Measured source extent -> measured analysis extent. Printed, not assumed:
    // a scaled pass must never take the root resolution for its input extent.
    uint sw, sh;
    _Tex1.GetDimensions(sw, sh);

    float2 numAt = float2(16.0 + 8.0 * 6.0 + 4.0, 14.0) * c.invResolution;
    suiComposite(col, CRYO_DIM, suiInteger(c, numAt, st, (int)sw, 4));
    suiComposite(col, CRYO_DIM, suiGlyph(c, numAt + float2(4.0 * 6.0 + 2.0, 0.0) * c.invResolution, st, 120));
    suiComposite(col, CRYO_DIM, suiInteger(c, numAt + float2(5.0 * 6.0 + 4.0, 0.0) * c.invResolution, st, (int)sh, 4));

    float2 dstAt = numAt + float2(9.0 * 6.0 + 12.0, 0.0) * c.invResolution;
    suiComposite(col, CRYO_INK, suiGlyph(c, dstAt, st, 62)); // '>'
    suiComposite(col, CRYO_INK, suiInteger(c, dstAt + float2(8.0, 0.0) * c.invResolution, st, (int)res.x, 3));
    suiComposite(col, CRYO_INK, suiGlyph(c, dstAt + float2(3.0 * 6.0 + 10.0, 0.0) * c.invResolution, st, 120));
    suiComposite(col, CRYO_INK, suiInteger(c, dstAt + float2(4.0 * 6.0 + 12.0, 0.0) * c.invResolution, st, (int)res.y, 3));

    // ---- transfer wedge: the ACTUAL curve this node applies ----------------
    float4 wedge = float4(0.615, 0.040, 0.955, 0.082);
    if (c.uv.x > wedge.x && c.uv.x < wedge.z && c.uv.y > wedge.y && c.uv.y < wedge.w) {
        float t = (c.uv.x - wedge.x) / max(wedge.z - wedge.x, 1e-5);
        float mapped = pow(saturate(t * luma_gain), max(luma_gamma, 0.05));
        col = float3(mapped, mapped, mapped);
    }
    suiComposite(col, CRYO_DIM, suiStrokeRect(c, wedge, 1.0));

    // ---- live per-column density of the conditioned signal ------------------
    float4 strip = float4(0.033, 0.878, 0.967, 0.962);
    suiComposite(col, CRYO_DIM, suiStrokeRect(c, strip, 1.0) * 0.55);
    if (c.uv.x > strip.x && c.uv.x < strip.z && c.uv.y > strip.y && c.uv.y < strip.w) {
        int sx = (int)id.x;
        float sum = 0.0;
        [loop] for (int r = 0; r < 24; ++r) {
            int sy = (int)(((float)r + 0.5) / 24.0 * _Resolution.y);
            sum += _Tex0.Load(int3(sx, sy, 0)).r;
        }
        float dens = saturate(sum / 24.0 * 1.6);
        float top = lerp(strip.w, strip.y, dens);
        if (c.uv.y > top) suiComposite(col, CRYO_INK, 0.80);
    }

    OutputUAV[id.xy] = float4(saturate(col), 1.0);
}
