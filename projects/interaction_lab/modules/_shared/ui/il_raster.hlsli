// il_raster.hlsli - Interaction Lab kit: the generic draw-list RASTERIZER.
//
// One compute pass draws a station's whole UI from its draw list (il_draw.hlsli). It is the same
// code in every module, so a station's own shaders hold only layout and logic.
//
//   - 16x16 pixel tiles, one thread group each. The group's 256 threads test every command's clip
//     box against the tile and set one bit per hit in a groupshared mask (InterlockedOr). Walking
//     the set bits low-to-high IS painter's order, so there is no prefix sum, only two barriers,
//     and no per-tile list cap. (A first version compacted with a prefix sum: 96 barriers a tile,
//     0.85 ms at 1580x1160.)
//   - Each pixel then walks only its tile's commands: one copy of each painter, compiled once.
//
// A station's raster.hlsl is three lines:
//
//     #define IL_TYPE_TEX _Tex1               // { slot: 1, source: "asset:type" }
//     #define IL_CONTENT_TEX _Tex2            // optional: a texture DL_IMAGE commands sample
//     #include "../_shared/ui/il_raster.hlsli"
//
// with { slot: 0, source: "buffer:dl" }. Define IL_RASTER_CONTENT_BG to use the content texture as
// the background instead of the field colour (for stations whose art is drawn per pixel).
#ifndef IL_RASTER_HLSLI
#define IL_RASTER_HLSLI

#include "../_shared/ui/il_core.hlsli"
#include "../_shared/ui/il_type_metrics.hlsli"

#ifndef IL_TYPE_TEX
#error define IL_TYPE_TEX before including il_raster.hlsli
#endif

#define IL_DL_MAXCMD   4096u
#define IL_DL_GLYPH0   (1u + 4u * IL_DL_MAXCMD)
#define DL_RECT 1u
#define DL_SEG 2u
#define DL_CIRCLE 3u
#define DL_DIAMOND 4u
#define DL_TRI 5u
#define DL_ARC 6u
#define DL_TEXT 7u
#define DL_IMAGE 8u
#define DL_HGRAD 9u
#define DL_ELLIPSE 10u

#define IL_TILE 16u
#define IL_MASK_WORDS (IL_DL_MAXCMD / 32u)

StructuredBuffer<float4> IL_DL : register(t0);
RWTexture2D<float4> OutputUAV : register(u0);

// One bit per command: set when the command's clip box touches this tile. Walking the set bits
// low to high IS painter's order, so no prefix sum (and no list cap) is needed.
groupshared uint gsMask[IL_MASK_WORDS];

float3 ilUnpack(float f) { uint v = (uint)f; return float3(v & 255u, (v >> 8) & 255u, (v >> 16) & 255u) / 255.0; }

float ilRasterGlyph(float2 p, float2 pen, float k, uint face, uint g)
{
    float2 q = (p - pen) / k + IL_TYPE_ORIGIN;
    if (any(q < 0.5) || any(q > IL_TYPE_CELL - 0.5)) return 1e4;
    float2 cell = float2((float)(g % IL_TYPE_COLS), (float)(g / IL_TYPE_COLS)) * IL_TYPE_CELL;
    float4 t = IL_TYPE_TEX.SampleLevel(LinearSampler, (cell + q) / IL_TYPE_ATLAS, 0);
    float v = (face == 0u) ? t.r : ((face == 1u) ? t.g : t.b);
    return (0.5 - v) * 2.0 * IL_TYPE_SPREAD * k;
}

// Coverage of a glyph run. Glyph pen positions are sorted, so find the last pen <= p.x and look at
// it and its neighbours (glyph ink can overhang its advance).
float ilRasterText(float2 p, float4 e1, uint g0, uint n)
{
    float base = e1.x, size = e1.y;
    uint face = (uint)e1.z;
    float k = size / IL_TYPE_EM;
    uint lo = 0u, hi = n - 1u;
    [loop] for (uint it = 0u; it < 7u && lo < hi; it++)
    {
        uint m = (lo + hi + 1u) >> 1;
        if (IL_DL[IL_DL_GLYPH0 + g0 + m].x <= p.x) lo = m; else hi = m - 1u;
    }
    float d = 1e4;
    [unroll] for (int j = -1; j <= 1; j++)
    {
        int gi = (int)lo + j;
        if (gi < 0 || gi >= (int)n) continue;
        float4 gl = IL_DL[IL_DL_GLYPH0 + g0 + (uint)gi];
        d = min(d, ilRasterGlyph(p, float2(gl.x, base), k, face, (uint)gl.y));
    }
    float bias = 0.22 * saturate((22.0 - size) / 13.0);   // light-on-dark small type reads thin
    return saturate(0.5 - d + bias);
}

float ilSdArc(float2 p, float2 c, float r, float a0, float a1)
{
    float2 q = p - c;
    float a = atan2(q.x, -q.y);                          // clockwise from 12 o'clock, -pi..pi
    bool inside = (a >= a0 && a <= a1) || (a + IL_TAU >= a0 && a + IL_TAU <= a1) || (a - IL_TAU >= a0 && a - IL_TAU <= a1);
    if (inside) return abs(length(q) - r);
    float2 e0 = c + r * float2(sin(a0), -cos(a0));
    float2 e1 = c + r * float2(sin(a1), -cos(a1));
    return min(length(p - e0), length(p - e1));
}

void ilRasterCmd(inout float3 col, float2 p, uint ci)
{
    uint base = 1u + 4u * ci;
    float4 e0 = IL_DL[base];
    if (p.x < e0.x || p.y < e0.y || p.x >= e0.z || p.y >= e0.w) return;   // clip
    float4 e1 = IL_DL[base + 1u];
    float4 e2 = IL_DL[base + 2u];
    float4 e3 = IL_DL[base + 3u];
    uint kind = (uint)e3.x;
    float cov = 0.0;
    float3 c = e2.rgb;
    float a = e2.a;

    if (kind == DL_RECT)
    {
        float d = ilSdBox(p, e1, e3.y);
        if (a > 0.0) ilOver(col, c, ilFill(d) * a);
        if (e3.z > 0.0) ilOver(col, ilUnpack(e3.w), ilBorder(d, e3.z));
        return;
    }
    if (kind == DL_SEG)
    {
        cov = ilStroke(ilSdSeg(p, e1.xy, e1.zw), e3.y);
        if (e3.z > 0.0)
        {
            float2 dir = normalize(e1.zw - e1.xy + 1e-6);
            cov *= ilDash(dot(p - e1.xy, dir), e3.z, e3.w);
        }
    }
    else if (kind == DL_CIRCLE)
    {
        float d = length(p - e1.xy) - e1.z;
        cov = (e1.w > 0.0) ? ilStroke(d, e1.w) : ilFill(d);
    }
    else if (kind == DL_DIAMOND)
    {
        float d = ilSdDiamond(p, e1.xy, e1.z);
        cov = (e1.w > 0.0) ? ilStroke(d, e1.w) : ilFill(d);
    }
    else if (kind == DL_TRI)
    {
        uint dir = (uint)e3.y;
        float2 q = p - e1.xy;
        if (dir == 1u) q.y = -q.y;
        else if (dir == 2u) q = float2(q.y, -q.x);
        else if (dir == 3u) q = float2(q.y, q.x);
        cov = ilFill(ilSdTriDown(q, float2(0.0, 0.0), e1.z, e1.w));
    }
    else if (kind == DL_ARC)
    {
        cov = ilFill(ilSdArc(p, e1.xy, e1.z, e3.y, e3.z) - 0.5 * e1.w);
    }
    else if (kind == DL_TEXT)
    {
        cov = ilRasterText(p, e1, (uint)e3.y, (uint)e3.z);
    }
    else if (kind == DL_IMAGE)
    {
#ifdef IL_CONTENT_TEX
        float2 t = (p - e1.xy) / max(e1.zw - e1.xy, 1e-3);
        float2 uv = lerp(e2.xy, e2.zw, t);
        c = IL_CONTENT_TEX.SampleLevel(LinearSampler, uv, 0).rgb * ilUnpack(e3.y);
        cov = 1.0;
        a = e3.z;
#endif
    }
    else if (kind == DL_HGRAD)
    {
        float t = saturate((p.x - e1.x) / max(e1.z - e1.x, 1e-3));
        c = lerp(e2.rgb, ilUnpack(e3.y), t);
        cov = ilFill(ilSdBox(p, e1, e3.z));
        a = 1.0;
    }
    else if (kind == DL_ELLIPSE)
    {
        // iq's first-order ellipse distance: exact on the curve, which is all AA and strokes need
        float2 q = p - e1.xy;
        float2 r = max(e1.zw, 1e-3);
        float k0 = length(q / r);
        float k1 = max(length(q / (r * r)), 1e-6);
        float d = k0 * (k0 - 1.0) / k1;
        cov = (e3.y > 0.0) ? ilStroke(d, e3.y) : ilFill(d);
        if (e3.z > 0.0)
        {
            // dash by arc length, approximated with the mean radius
            float arc = (atan2(q.y / r.y, q.x / r.x) + IL_PI) * 0.5 * (r.x + r.y);
            cov *= ilDash(arc, e3.z, e3.w);
        }
    }
    ilOver(col, c, cov * a);
}

[numthreads(16, 16, 1)]
void main(uint3 tid : SV_DispatchThreadID, uint3 gid : SV_GroupID, uint gi : SV_GroupIndex)
{
    uint W, H;
    OutputUAV.GetDimensions(W, H);
    float4 tile = float4(gid.xy * IL_TILE, gid.xy * IL_TILE + IL_TILE);
    uint n = min((uint)IL_DL[0].x, IL_DL_MAXCMD);

    if (gi < IL_MASK_WORDS) gsMask[gi] = 0u;
    GroupMemoryBarrierWithGroupSync();
    // each thread tests every 256th command against the tile
    [loop] for (uint c = gi; c < n; c += 256u)
    {
        float4 bb = IL_DL[1u + 4u * c];
        if (bb.x < tile.z && bb.z > tile.x && bb.y < tile.w && bb.w > tile.y)
            InterlockedOr(gsMask[c >> 5], 1u << (c & 31u));
    }
    GroupMemoryBarrierWithGroupSync();

    if (tid.x >= W || tid.y >= H) return;
    float2 p = float2(tid.xy) + 0.5;
#if defined(IL_RASTER_CONTENT_BG) && defined(IL_CONTENT_TEX)
    float3 col = IL_CONTENT_TEX.SampleLevel(LinearSampler, p / float2(W, H), 0).rgb;
#else
    float3 col = IL_FIELD;
#endif
    uint words = (n + 31u) >> 5;
    [loop] for (uint w = 0u; w < words; w++)
    {
        uint bits = gsMask[w];
        [loop] while (bits != 0u)
        {
            uint b = firstbitlow(bits);
            bits &= bits - 1u;
            ilRasterCmd(col, p, (w << 5) + b);
        }
    }
    OutputUAV[tid.xy] = float4(saturate(col), 1.0);
}

#endif
