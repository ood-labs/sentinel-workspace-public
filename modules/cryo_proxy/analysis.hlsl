// CRYOGRAM / MEASUREMENT — 480x270 analysis conditioning.
//
// The full-resolution specimen bypasses this node entirely; only the Features
// input is downsampled here. Two jobs:
//
//   1. Box-average the crystallographic hatch OUT. The hatch is surface texture,
//      not structure. Left in, it aliases into a moire storm that would bury the
//      corner and line tasks in meaningless candidates.
//   2. Emphasise what the instrument is actually meant to measure: grain regions
//      and the boundaries between them.
//
// Source extent comes from GetDimensions, never from _Resolution — this pass
// renders at 480x270 while its input is 1280x720.

RWTexture2D<float4> OutputUAV : register(u0);

float lumaAt(int2 p, int2 maxP) {
    float3 c = _Tex0.Load(int3(clamp(p, int2(0, 0), maxP), 0)).rgb;
    return dot(c, float3(0.2126, 0.7152, 0.0722));
}

[numthreads(8, 8, 1)]
void main(uint3 id : SV_DispatchThreadID) {
    uint2 dst = (uint2)_Resolution.xy;
    if (id.x >= dst.x || id.y >= dst.y) return;

    uint sw, sh;
    _Tex0.GetDimensions(sw, sh);
    float2 srcRes = float2(max(sw, 1u), max(sh, 1u));
    int2 maxP = int2(srcRes) - 1;

    float2 scale = srcRes / _Resolution.xy;          // source px per output px
    float2 center = (float2(id.xy) + 0.5) * scale;

    // ---- box average across the full footprint: this is what kills the hatch
    float acc = 0.0;
    float wsum = 0.0;
    [unroll] for (int j = 0; j < 4; ++j) {
        [unroll] for (int i = 0; i < 4; ++i) {
            float2 o = (float2(i, j) + 0.5) * 0.25 - 0.5;     // -0.375..0.375
            float2 sp = center + o * scale * hatch_reject;
            acc += lumaAt((int2)floor(sp), maxP);
            wsum += 1.0;
        }
    }
    float base = acc / wsum;

    // ---- island separation -------------------------------------------------
    // A 4px source gap survives the downsample geometrically (verified: 37
    // separate components in the 480x270 image) but the detector still fuses
    // them, so the separation has to be widened in ANALYSIS pixels rather than
    // source pixels. This is a morphological erosion: min over a disc whose
    // radius is authored in output pixels and converted to source space.
    if (erode_px > 0.01) {
        const float2 K[13] = {
            float2( 0.0,  0.0), float2( 1.0,  0.0), float2(-1.0,  0.0),
            float2( 0.0,  1.0), float2( 0.0, -1.0), float2( 0.71, 0.71),
            float2( 0.71,-0.71), float2(-0.71, 0.71), float2(-0.71,-0.71),
            float2( 0.5,  0.0), float2( 0.0,  0.5), float2(-0.5,  0.0),
            float2( 0.0, -0.5)
        };
        float er = erode_px * scale.x;
        float mn = 1.0;
        [unroll] for (int e = 0; e < 13; ++e) {
            mn = min(mn, lumaAt((int2)floor(center + K[e] * er), maxP));
        }
        base = min(base, mn);
    }

    // ---- wide ring for local contrast (boundaries survive, plate flattens) --
    float ring = 0.0;
    [unroll] for (int k = 0; k < 8; ++k) {
        float a = 6.28318530718 * (float)k / 8.0;
        float2 sp = center + float2(cos(a), sin(a)) * local_radius * scale;
        ring += lumaAt((int2)floor(sp), maxP);
    }
    ring /= 8.0;

    float hi = base - ring;
    float sig = base * luma_gain + hi * edge_focus;
    sig = pow(saturate(sig), max(luma_gamma, 0.05));

    OutputUAV[id.xy] = float4(sig, sig, sig, 1.0);
}
