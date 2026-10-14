// Ramp Desk / swatch - every colour field of the desk, per pixel, in its place on screen: the ramp
// (the published entries), the same stops blended three ways, the ramp seen as lightness and with
// each dichromacy, and the picker's plane and hue strip. The layout pass shows them with DL_IMAGE
// at uv = rect / extent, so each pixel is sampled at its own centre and nothing is resampled.
#include "../_shared/ui/il_core.hlsli"
#include "ramp.hlsli"

RWTexture2D<float4> OutputUAV : register(u0);

[numthreads(16, 16, 1)]
void main(uint3 id : SV_DispatchThreadID)
{
    uint W, H;
    OutputUAV.GetDimensions(W, H);
    if (id.x >= W || id.y >= H) return;
    float2 res = float2((float)W, (float)H);
    float s = ilCtx(res).s;
    RdLayout L = rdLayout(res, s);
    float2 p = float2(id.xy) + 0.5;
    float t = rdTOf(L, p.x);
    float3 col = 0.0;

    if (ilIn(p, L.bar))
    {
        col = palSample(t);
    }
    else if (p.x >= L.bar.x && p.x <= L.bar.z && p.y >= L.lane[0].y && p.y <= L.lane[6].w)
    {
        uint lane = 7u;
        [unroll] for (uint a = 0u; a < 7u; a++) if (p.y >= L.lane[a].y && p.y <= L.lane[a].w) lane = a;
        if (lane == 7u) return;
        if (lane < 3u)
        {
            // the same stops in each blend space, straight from the stops
            bool clip;
            col = palToDisplay(rdBlendAt(t, lane, clip));
        }
        else
        {
            float3 lin = palToLinear(palSample(t));
            if (lane == 3u) col = palToDisplay(palLabToLinear(float3(palLinearToLab(lin).x, 0.0, 0.0)));
            else if (lane == 4u) col = palToDisplay(palDeutan(lin));
            else if (lane == 5u) col = palToDisplay(palProtan(lin));
            else col = palToDisplay(palTritan(lin));
        }
    }
    else if (ilIn(p, L.plane))
    {
        // lightness up, chroma right, at the selected stop's hue; outside sRGB: hatched ground
        float2 lc = rdPlaneLC(L, p);
        float3 lin = palLabToLinear(palLchToLab(float3(lc.x, lc.y, rdAsked(rdSel()).z)));
        if (palInGamut(lin)) col = palToDisplay(lin);
        else col = lerp(IL_WELL, IL_GRID, ilGridLine(p.x + p.y, 7.0 * s, 1.0));
    }
    else if (ilIn(p, L.hue))
    {
        // every hue at the stop's lightness and asked-for chroma, each brought inside sRGB
        float3 a = rdAsked(rdSel());
        float h = 360.0 * saturate((p.x - L.hue.x) / max(L.hue.z - L.hue.x, 1.0));
        bool clip;
        col = palToDisplay(palGamutMap(palLchToLab(float3(a.x, a.y, h)), clip));
    }
    else return;
    OutputUAV[id.xy] = float4(col, 1.0);
}
