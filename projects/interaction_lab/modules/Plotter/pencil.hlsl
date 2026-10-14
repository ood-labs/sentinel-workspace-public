// Plotter / pencil - the whole plot as a faint pencil underdrawing, so an edit on the Path Desk
// shows on the sheet at once, before the pen gets there. Scattered, not per pixel: one thread per
// sample stamps the line to the next sample in half-pixel steps, each a bilinear 2 x 2 footprint.
//
// Nothing clears the guide. Each entry is (cook << 8 | coverage): a stamp replaces an entry from
// any other cook and keeps the larger coverage within its own, and present reads only this cook's
// entries. The cook number lives in the buffer's last element, counted by this pass alone - no other
// pass's timing is assumed. (A separate clear pass did not work: two passes writing one buffer,
// with nothing passed between them, are not guaranteed to run in manifest order - a clear listed
// first wiped every stamp - and a counter written by the plan pass was read a cook stale here.)
#include "plotter.hlsli"

StructuredBuffer<float4> W : register(t0);        // the Path Desk's "Path" (data input)
RWStructuredBuffer<uint> G : register(u0);

groupshared uint gsCook;
static uint g_cook;

void stamp(uint ix, uint cov)
{
    uint want0 = (g_cook << 8) | cov;
    uint cur = G[ix];
    [allow_uav_condition] for (uint tries = 0u; tries < 8u; tries++)
    {
        uint want = ((cur >> 8) == g_cook) ? max(cur, want0) : want0;
        if (want == cur) break;
        uint orig;
        InterlockedCompareExchange(G[ix], cur, want, orig);
        if (orig == cur) break;
        cur = orig;
    }
}

void splat(float2 q, float w)
{
    float2 f = q - 0.5;
    int2 i0 = (int2)floor(f);
    float2 fr = f - (float2)i0;
    [unroll] for (int dy = 0; dy < 2; dy++)
    [unroll] for (int dx = 0; dx < 2; dx++)
    {
        int2 c = i0 + int2(dx, dy);
        if (c.x < 0 || c.y < 0 || c.x >= 1280 || c.y >= 720) continue;
        float wgt = (dx == 0 ? 1.0 - fr.x : fr.x) * (dy == 0 ? 1.0 - fr.y : fr.y) * w;
        uint cov = (uint)(saturate(wgt) * 255.0);
        if (cov > 0u) stamp((uint)c.y * 1280u + (uint)c.x, cov);
    }
}

[numthreads(PLOT_SAMPLES, 1, 1)]
void main(uint gi : SV_GroupIndex)
{
    if (gi == 0u)
    {
        uint c = G[PL_PENCIL_COOK] + 1u;
        if (c >= 0xFFFFFFu) c = 1u;
        G[PL_PENCIL_COOK] = c;
        gsCook = c;
    }
    GroupMemoryBarrierWithGroupSync();
    g_cook = gsCook;
    uint k = gi;
    // the path whose samples k and k + 1 both belong to
    bool inside = false;
    [unroll] for (uint p = 0u; p < PLOT_PATHS; p++)
    {
        float4 r = W[PLOT_PATH0 + p];
        uint first = (uint)r.x, n = (uint)r.y;
        if (n >= 2u && k >= first && k + 1u < first + n) inside = true;
    }
    if (!inside) return;
    float2 a = W[PLOT_SAMPLE0 + k].xy, b = W[PLOT_SAMPLE0 + k + 1u].xy;
    uint steps = clamp((uint)ceil(length(b - a) * 2.0), 1u, 64u);
    [loop] for (uint i = 0u; i < steps; i++) splat(lerp(a, b, (float)i / (float)steps), 1.6);
}
