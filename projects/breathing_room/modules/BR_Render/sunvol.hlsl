// BR_Render / sunvol.hlsl -- what INSIDE the room shades the sunbeams.
//
// The beam pass decides analytically whether a point in the air can see the sun out of a window
// (opening, sashes, reveal, glass, sheers, street trees) -- crisp and cheap, but blind to the room
// itself, so beams passed straight through the chimney breast and would pass through the sofa.
// This pass marches a soft shadow ray from every cell of a ~15 cm grid toward the sun, through the
// room's own detail (breast, trims, radiators, furniture), as far as the room box. The beams
// multiply by it; the window part stays analytic and sharp.
#include "render_common.hlsli"

RWStructuredBuffer<float> SunVol : register(u0);

[numthreads(64, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    SunGrid g = sunGrid();
    int i = (int)tid.x;
    if (i >= g.count) return;
    int3 c = int3(i % g.n.x, (i / g.n.x) % g.n.y, i / (g.n.x * g.n.y));
    float3 x = g.origin + (float3)c * g.spacing;
    BRSkyCtx S = scSkyCtx();
    float3 L = S.sunDir;
    if (L.y < 0.0 || sun_direct == 0) { SunVol[i] = 0.0; return; }
    float3 fN;
    float tB = boxExit(x, L, fN);
    float t = 0.02, res = 1.0;
    [loop] for (int k = 0; k < 48; k++)
    {
        float3 p = x + L * t;
        SHit slab;
        SHit det = mapSplit(p, slab, false);
        float d = det.d;
        if (d < 0.004) { res = 0.0; break; }
        res = min(res, 6.0 * d / t);
        t += max(d, 0.03);
        if (t >= tB) break;
    }
    SunVol[i] = smoothstep(0.0, 1.0, saturate(res));
}
