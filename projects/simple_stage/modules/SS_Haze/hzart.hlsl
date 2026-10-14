// SS_Haze / hzart — the preview's image: the field averaged through the hall (hzsum's projections), in plan over
// long section, one grey ramp. Haze shows where the clouds are and how thick; Air how fast it moves; Heat how
// warm it runs above the room (the rig's plumes, the crowd). The type, the frames, the machines and the readout
// column are recorded by layout.hlsl and drawn over this by the shared UI kit (ui.hlsl).
#include "hz_grid.hlsli"
#include "hz_proj.hlsli"
#include "haze_view.hlsli"
#include "../_shared/ui/il_core.hlsli"
StructuredBuffer<float4> T : register(t0);
StructuredBuffer<float4> P : register(t1);
RWTexture2D<float4> OutputUAV : register(u0);

// bilinear over projection lines (u runs fastest; u, v are cell coordinates with centres at integers)
float4 projAt(uint base, uint nu, uint nv, float u, float v)
{
    u = clamp(u, 0.0, nu - 1.0); v = clamp(v, 0.0, nv - 1.0);
    uint u0 = min((uint)u, nu - 2u), v0 = min((uint)v, nv - 2u);
    float fu = u - u0, fv = v - v0;
    uint r0 = base + v0 * nu + u0, r1 = r0 + nu;
    return lerp(lerp(P[r0], P[r0 + 1u], fu), lerp(P[r1], P[r1 + 1u], fu), fv);
}
// what the view shows, 0..1
float tone(float4 fine, float4 air)
{
    if (field_view == 1) return 1.0 - exp(-air.x / 0.6);              // air speed, m/s
    if (field_view == 2) return 1.0 - exp(-max(air.y, 0.0) / 1.5);     // kelvin above ambient
    return 1.0 - exp(-0.55 * fine.x);                            // haze units
}
float3 ramp(float t) { return lerp(IL_WELL, IL_INK * 0.92, pow(saturate(t), 0.85)); }
// a quiet 5 m grid from the stage centre, so distances read
float grid5(float a) { float f = abs(frac(a / 5.0 + 0.5) - 0.5) * 5.0 * gS; return saturate(1.0 - f); }

[numthreads(8, 8, 1)]
void main(uint3 id : SV_DispatchThreadID)
{
    uint W, H;
    OutputUAV.GetDimensions(W, H);
    if (id.x >= W || id.y >= H) return;
    float2 p = id.xy + 0.5;
    HzDomain d = hzDomain(T[1], T[2], T[3]);
    hazeView(float2(W, H), d);
    float3 c = IL_FIELD;
    float4 pr = planRect(), sr = sectRect();
    float hf = 0.5 * d.h;
    if (p.y >= 34.0 && p.x < W - HV_SIDE)
    {
        ilOver(c, IL_PANEL, ilFill(ilSdBox(p, ilInset(pr, -8.0), IL_RADIUS)));
        ilOver(c, IL_PANEL, ilFill(ilSdBox(p, ilInset(sr, -8.0), IL_RADIUS)));
        float z = viewZ(p.x);
        if (ilIn(p, pr))
        {
            float x = viewX(p.y);
            float4 fine = projAt(P_FP, FX, FZ, (x - d.lo.x) / hf - 0.5, (z - d.lo.z) / hf - 0.5);
            float4 air = projAt(P_AP, AX, AZ, (x - d.lo.x) / d.h - 0.5, (z - d.lo.z) / d.h - 0.5);
            c = ramp(tone(fine, air));
            ilOver(c, IL_INK, 0.06 * max(grid5(z), grid5(x)));
        }
        else if (ilIn(p, sr))
        {
            float y = viewY(p.y);
            float4 fine = projAt(P_FE, FZ, FY, (z - d.lo.z) / hf - 0.5, (y - d.lo.y) / hf - 0.5);
            float4 air = projAt(P_AE, AZ, AY, (z - d.lo.z) / d.h - 0.5, (y - d.lo.y) / d.h - 0.5);
            c = ramp(tone(fine, air));
            ilOver(c, IL_INK, 0.06 * max(grid5(z), grid5(y - d.floorY)));
        }
    }
    OutputUAV[id.xy] = float4(c, 1.0);
}
// rev 3 (headers changed: the shader cache keys on this file)
