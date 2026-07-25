// Console render — display spectrogram, newest hop at the right edge.
//
// Everything positional goes through the shared p2_* transform so the pixels a
// user sees and the coordinates the detector reduces are the same mapping.

#include "types.hlsli"

StructuredBuffer<DH> Hist : register(t0);
RWTexture2D<float4> OutputUAV : register(u0);

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID) {
    uint2 px = DTid.xy;
    uint W = (uint)_Resolution.x, H = (uint)_Resolution.y;
    if (px.x >= W || px.y >= H) return;

    // Panel UV with y up, so the frequency axis rises like a spectrogram.
    float2 uv = float2(((float)px.x + 0.5) / (float)W,
                       1.0 - ((float)px.y + 0.5) / (float)H);

    float3 col = P2_INK;

    uint newest = (uint)max(Hist[CURSOR_IDX].v, 0.0);
    if (newest > 0u) {
        float nHops = (float)min(DISP_HOPS, (uint)max(hist_hops, 32.0));
        // uv.x -> hops back from newest; uv.y -> log frequency axis directly,
        // because the display rows ARE the log axis.
        float hopsBack = (1.0 - uv.x) * max(nHops - 1.0, 1.0);

        // A 384x192 history stretched over a ~1280x720 panel is a ~3-4x
        // magnification on both axes. Point sampling turns real audio into
        // blocks and reads as a synthetic pattern, so interpolate. The hop axis
        // is only interpolated where BOTH taps are inside the retained window,
        // otherwise the pair straddles the ring cursor and blends the newest
        // hop against the oldest one.
        float gf = (float)newest - hopsBack;
        uint  g0 = (uint)max(floor(gf), 0.0);
        uint  g1 = min(g0 + 1u, newest);
        float gt = (g1 > g0) ? frac(gf) : 0.0;

        float by = uv.y * (float)DISP_BINS - 0.5;
        uint  b0 = (uint)clamp(floor(by), 0.0, (float)(DISP_BINS - 1u));
        uint  b1 = min(b0 + 1u, DISP_BINS - 1u);
        float bt = saturate(by - floor(by));

        uint r0 = (g0 % DISP_HOPS) * DISP_BINS, r1 = (g1 % DISP_HOPS) * DISP_BINS;
        float e = lerp(lerp(Hist[r0 + b0].eq, Hist[r0 + b1].eq, bt),
                       lerp(Hist[r1 + b0].eq, Hist[r1 + b1].eq, bt), gt);
        col = lerp(P2_INK, float3(0.93, 0.95, 0.96), saturate(e));
    }

    // Decade gridlines, so the frequency axis is readable rather than implied.
    [unroll] for (int d = 0; d < 4; ++d) {
        float hz = 100.0 * pow(10.0, (float)d);
        if (hz < P2_AXIS_LO_HZ || hz > P2_AXIS_HI_HZ) continue;
        float t = log(hz / P2_AXIS_LO_HZ) / log(P2_AXIS_HI_HZ / P2_AXIS_LO_HZ);
        if (abs(uv.y - t) < (0.8 / (float)H)) col = lerp(col, P2_GRID, 0.85);
    }

    OutputUAV[px] = float4(col, 1.0);
}
