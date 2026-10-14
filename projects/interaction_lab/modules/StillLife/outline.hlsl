// Still Life / outline - the selection, drawn the way an editor draws it: a two-pixel silhouette
// line just outside each selected object, accent for the active one, ink for the rest, and
// ghosted where something stands in front of it (the solve's depth, in beauty.a, decides).
//
// The silhouette comes from the field itself: march the selected objects alone and keep the
// ray's closest approach; a ray that misses but passes within ~two pixels of the surface is on
// the line. No id buffer, no edge filter - and it stays exact at any distance.
#include "../_shared/ui/il_core.hlsli"

#define SL_RECORD_ONLY
#include "still.hlsli"
#undef SL_RECORD_ONLY
StructuredBuffer<SlObject> Objs : register(t1);
#define SL_OBJECTS Objs
#include "still.hlsli"

RWTexture2D<float4> OutputUAV : register(u0);

[numthreads(8, 8, 1)]
void main(uint3 id : SV_DispatchThreadID)
{
    float2 res = _Resolution.xy;
    if (id.x >= (uint)res.x || id.y >= (uint)res.y) return;
    float4 beauty = _Tex0.Load(int3(id.xy, 0));
    float3 col = beauty.rgb;

    // only the selected objects whose projected bounding circle (plus the line's width) covers
    // this pixel: the march below then runs on the selection's footprint, not the whole frame
    uint mask = 0u;
    float2 px = float2(id.xy) + 0.5;
    float ppuK = 0.5 * res.y * _ProjMatrix[1][1];                // px per metre at unit depth
    [loop] for (uint k = 1u; k <= SL_MAX; k++)
    {
        if (Objs[k].kind == K_EMPTY || !slSelected(Objs[k].id)) continue;
        float3 c = slProject(Objs[k].pos, res);
        float rpx = slRadius(Objs[k].kind) * Objs[k].scale * ppuK / max(c.z, 1e-3);
        if (c.z <= 0.0 || length(px - c.xy) < rpx * 1.15 + 6.0) mask |= 1u << (k - 1u);
    }

    if (mask != 0u)
    {
        float2 uv = (float2(id.xy) + 0.5) / res;
        float3 ro, rd;
        slRay(uv, ro, rd);
        float t = 0.0, dmin = 1e9, tmin = 0.0;
        uint recMin = 0u;
        bool inside = false;
        [loop] for (uint i = 0u; i < 80u; i++)
        {
            float3 p = ro + rd * t;
            float d = 1e9;
            uint r = 0u;
            [loop] for (uint k2 = 1u; k2 <= SL_MAX; k2++)
            {
                if ((mask & (1u << (k2 - 1u))) == 0u) continue;
                SlObject o = Objs[k2];
                float di = slKindSd(o.kind, qRot(qConj(o.rot), p - o.pos) / o.scale) * o.scale;
                if (di < d) { d = di; r = k2; }
            }
            if (d < dmin) { dmin = d; tmin = t; recMin = r; }
            if (d < 0.0004 * (1.0 + t)) { inside = true; break; }
            t += d;
            if (t > 40.0) break;
        }
        // world size of one pixel at the closest approach, then the miss distance in pixels
        float wpp = 2.0 * max(tmin, 1e-3) / (res.y * max(_ProjMatrix[1][1], 1e-3));
        float dpx = inside ? 1e9 : dmin / wpp;
        // a dark hairline hugging the silhouette, then the line: it separates from the object's
        // own colour (an amber line on a terracotta orb would just read as a bigger orb)
        float key = 1.0 - smoothstep(0.5, 1.3, dpx);
        float band = smoothstep(0.5, 1.3, dpx) * (1.0 - smoothstep(2.9, 3.7, dpx));
        bool hidden = beauty.a < tmin - 0.01;
        uint act = slActive();
        float3 ink = (recMin == act) ? IL_ACCENT : IL_INK;
        col = lerp(col, IL_PANEL, key * (hidden ? 0.0 : 0.55));
        col = lerp(col, ink, band * (hidden ? 0.35 : 1.0));
    }
    OutputUAV[id.xy] = float4(col, 1.0);
}
