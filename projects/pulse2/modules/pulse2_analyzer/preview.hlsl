// Meaningful intermediate preview — this is a contract, not decoration.
//
// Three stacked lanes (kick / snare / hat), each showing, over ~1.37 s of hop
// history: the per-lane SuperFlux O_i[n] of the whitened spectrum as a filled
// area with a bright cap (white), the live adaptive threshold the picker
// ACTUALLY used (amber line, read from the picker's own trace rather than
// recomputed here so the two cannot drift), and accepted-onset ticks. Over- and
// under-triggering are therefore readable without ground truth: flux crossing
// the amber line with no tick, or a tick with no crossing, is a visible defect.
//
// The whitened spectrogram itself is deliberately NOT drawn here; the
// spectrogram console is 2C2's deliverable and needs its own history buffer.
//
// Monochrome scientific-instrument palette with one warm accent, per CLAUDE.md.

#include "common.hlsli"

StructuredBuffer<PS> St : register(t1);
RWTexture2D<float4> OutputUAV : register(u0);

static const float3 INK    = float3(0.035, 0.037, 0.040);
static const float3 GRID   = float3(0.16, 0.17, 0.18);
static const float3 TRACE  = float3(0.92, 0.94, 0.95);
static const float3 ACCENT = float3(0.98, 0.62, 0.23);

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID) {
    uint2 px = DTid.xy;
    uint W = (uint)_Resolution.x, Hpx = (uint)_Resolution.y;
    if (px.x >= W || px.y >= Hpx) return;

    float3 col = INK;

    PS H = St[HDR_H];
    uint latest = (uint)max(H.c, 0.0);
    uint nHops = (uint)clamp(trace_hops, 32.0, (float)TRACE_SLOTS);

    // Newest hop on the right. Column x maps to generation latest-(nHops-1-x).
    float fx = (float)px.x / max((float)W - 1.0, 1.0);
    uint back = (uint)((1.0 - fx) * (float)(nHops - 1u));
    uint gen = (latest >= back) ? (latest - back) : 0u;

    uint laneH = Hpx / NLANES;
    uint band = min(px.y / max(laneH, 1u), NLANES - 1u);
    uint yInBand = px.y - band * laneH;

    if (yInBand == 0u) col = GRID;                              // lane separator
    if (yInBand == laneH - 1u) col = lerp(INK, GRID, 0.6);

    PS tr = St[trace_index(gen, band)];
    float o   = tr.a;
    float thr = tr.b;
    float hit = tr.c;

    float sc = trace_scale;
    float fy = 1.0 - (float)yInBand / max((float)laneH - 1.0, 1.0);  // 0 at bottom

    // sqrt keeps both the near-zero floor between onsets and the tall transients
    // legible in one fixed band; a linear scale renders this signal as almost
    // entirely empty, since the median flux is ~0 and the p99 is ~0.5.
    float oNorm   = saturate(sqrt(max(o, 0.0) * sc));
    float thrNorm = saturate(sqrt(max(thr, 0.0) * sc));
    float px1 = 1.6 / max((float)laneH, 1.0);

    if (fy <= oNorm) col = lerp(INK, TRACE, 0.22 + 0.5 * saturate(oNorm));
    if (o > 0.0 && abs(fy - oNorm) < px1) col = TRACE;           // bright cap
    if (abs(fy - thrNorm) < px1) col = ACCENT;                   // threshold
    if (hit > 0.5 && yInBand > 2u && yInBand < laneH - 2u)
        col = lerp(col, ACCENT, 0.85);                           // accepted onset

    OutputUAV[px] = float4(col, 1.0);
}
