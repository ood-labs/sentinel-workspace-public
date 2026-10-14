// Plan (left) and front (right): a 1 m grid and the floor line, beams in their decoded colour and dimmer, body
// boxes shaded grey over them, and a small diamond at each scene object. A red border means the FixtureTypes port
// is missing or of another layout.
#include "probe.hlsli"

StructuredBuffer<float4> Bounds : register(t5);
StructuredBuffer<uint> CanvasIn : register(t8);
RWTexture2D<float4> OutputUAV : register(u0);


float3 toDisplay(float3 c) { return pow(saturate(c), 1.0 / 2.2); }

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    uint w, h;
    OutputUAV.GetDimensions(w, h);
    if (tid.x >= w || tid.y >= h) return;
    float2 px = float2(tid.xy) + 0.5;
    // The canvas is 1280 by 720; other output sizes sample it.
    uint2 cp = uint2(min(px * float2(RP_CANVAS_W, RP_CANVAS_H) / float2(w, h), float2(RP_CANVAS_W - 1, RP_CANVAS_H - 1)));
    RigView v = rpView(Bounds[0], Bounds[1], RP_CANVAS_W, RP_CANVAS_H);
    float2 cpx = float2(cp) + 0.5;
    uint panel = cpx.x < v.panelW ? 0u : 1u;
    float3 col = float3(0.0035, 0.0036, 0.0042);
    float3 o, d;
    rpRay(v, panel, cpx, o, d);
    float2 wq = panel == 0u ? o.xz : o.xy;
    float2 gridDist = abs(wq - round(wq)) * v.scale;
    if (min(gridDist.x, gridDist.y) < 0.6) col = float3(0.011, 0.0115, 0.013);
    if (panel == 1u && abs(o.y) * v.scale < 0.8) col = float3(0.045, 0.045, 0.05);
    uint beam = CanvasIn[(cp.y * RP_CANVAS_W + cp.x) * 2u + 1u];
    if (beam != 0u)
    {
        float3 b = float3((beam >> 16) & 255u, (beam >> 8) & 255u, beam & 255u) / 255.0;
        col += b;
    }
    uint body = CanvasIn[(cp.y * RP_CANVAS_W + cp.x) * 2u];
    if (body != 0u) col = float3(0.30, 0.31, 0.33) * ((float)((body >> 8) & 255u) / 255.0);
    uint objects = min(_Data3_Count, 64u);
    [loop] for (uint k = 0u; k < objects; k++)
    {
        float2 s = rpProject(v, panel, _Data3[k].origin.xyz);
        float2 e = abs(cpx - s);
        if (e.x + e.y <= 5.0) col = float3(0.85, 0.62, 0.2);
    }
    if (abs(cpx.x - v.panelW) < 1.0) col = float3(0.03, 0.03, 0.034);
    float3 outc = toDisplay(col);
    if (!gdtfTablesValid() && (tid.x < 4u || tid.y < 4u || tid.x >= w - 4u || tid.y >= h - 4u)) outc = float3(0.9, 0.2, 0.2);
    OutputUAV[tid.xy] = float4(outc, 1.0);
}
