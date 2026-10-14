// Stage / render - a small proscenium stage lit by the blended look: a cyclorama wash, four
// fixtures on a truss whose beams cross the haze and pool on the floor. Light accumulates in
// linear and is tone-mapped once. Master scales all of it; blackout takes it to black.
#include "stage.hlsli"

RWTexture2D<float4> OutputUAV : register(u0);

float segT(float2 p, float2 a, float2 b) { float2 d = b - a; return dot(p - a, d) / max(dot(d, d), 1e-6); }
float box(float2 p, float2 c, float2 hs, float aa) { float2 q = abs(p - c) - hs; float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0); return saturate(0.5 - d / aa); }

[numthreads(8, 8, 1)]
void main(uint3 id : SV_DispatchThreadID)
{
    uint w, h;
    OutputUAV.GetDimensions(w, h);
    if (id.x >= w || id.y >= h) return;
    float aspect = (float)w / (float)h;
    float aa = 1.0 / (float)h;                                   // one pixel in stage units
    float2 p = (float2(id.xy) + 0.5) / (float)h;                 // x 0..aspect, y 0..1 downward

    StLook L = stBlend(stLook((uint)cue_a), stLook((uint)cue_b), saturate(mix));
    float gain = blackout != 0 ? 0.0 : saturate(master);

    const float yH = 0.64;      // horizon: cyclorama above, floor below
    const float yT = 0.085;     // the truss
    const float yF = 0.84;      // where the beams land

    float3 col = 0.0;
    float sx = p.x / aspect - 0.5;
    if (p.y < yH)
    {
        float t = saturate(p.y / yH);
        float3 cyc = lerp(L.cycTop, L.cycBot, t * t * (3.0 - 2.0 * t));
        col += cyc * L.cycLevel * (1.0 - 0.45 * sx * sx * 4.0);
    }
    else
    {
        float d = p.y - yH;
        col += L.cycBot * L.cycLevel * 0.20 * exp(-d * 10.0);  // the wash's spill on the floor
        col += 0.0025;                                          // the floor is there, barely
    }

    float3 lit = 0.0;
    [unroll] for (uint i = 0u; i < ST_FIX; i++)
    {
        StFixture f = L.f[i];
        float2 F = float2(ST_HANG[i] * aspect, yT + 0.026);
        float2 T = float2(f.pan * aspect, yF);
        float R = 0.035 + 0.16 * f.focus;                       // beam radius where it lands
        float t = segT(p, F, T);
        float tc = saturate(t);
        float r = lerp(0.005, R, tc);
        float d = length(p - (F + (T - F) * tc));
        float reach = (t >= 0.0 ? 1.0 : 0.0) * (1.0 - smoothstep(1.0, 1.08, t));
        float beam = exp(-(d * d) / (r * r) * 1.7) * (0.18 + 0.82 * tc) * reach;
        col += f.col * f.inten * beam * haze * 0.40;
        if (p.y >= yH)
        {
            float2 e = (p - T) / float2(R * 1.15, R * 0.30);
            col += f.col * f.inten * exp(-dot(e, e) * 1.4) * 0.95;
        }
        lit += f.col * f.inten;
    }
    col += lit * 0.005 * haze;                                   // the haze glows a little overall
    col *= gain;

    // the rig: unlit metal, seen by the light it is hung in (black in a blackout)
    float metal = 0.022 * gain * (0.4 + 0.6 * saturate(dot(lit, float3(0.3, 0.5, 0.2))));
    float chordA = saturate(0.5 - abs(p.y - (yT - 0.012)) / aa + 1.0);
    float chordB = saturate(0.5 - abs(p.y - (yT + 0.006)) / aa + 1.0);
    float u = frac(p.x / 0.036);
    float zig = (yT - 0.012) + 0.018 * (1.0 - abs(2.0 * u - 1.0));
    float diag = saturate(0.5 - abs(p.y - zig) / (aa * 1.6) + 0.5) * step(yT - 0.013, p.y) * step(p.y, yT + 0.007);
    float truss = max(max(chordA, chordB), diag) * step(0.03 * aspect, p.x) * step(p.x, 0.97 * aspect);
    col = lerp(col, metal, truss);
    [unroll] for (uint k = 0u; k < ST_FIX; k++)
    {
        StFixture f = L.f[k];
        float2 F = float2(ST_HANG[k] * aspect, yT + 0.014);
        float tilt = (f.pan - ST_HANG[k]) * 0.6;                  // the head leans the way it points
        float2 q = p - F;
        q = float2(q.x * cos(tilt) + q.y * sin(tilt), -q.x * sin(tilt) + q.y * cos(tilt));
        col = lerp(col, metal * 1.4, box(q, float2(0.0, 0.0), float2(0.014, 0.016), aa));
        float lens = saturate(0.5 - (length(q - float2(0.0, 0.012)) - 0.0075) / aa);
        float glow = exp(-dot(q - float2(0.0, 0.012), q - float2(0.0, 0.012)) / (0.012 * 0.012));
        col += f.col * f.inten * gain * (lens * 3.0 + glow * 0.6);
    }

    // masking legs at the sides
    float leg = smoothstep(0.034, 0.028, p.x / aspect) + smoothstep(0.966, 0.972, p.x / aspect);
    col *= 1.0 - saturate(leg);

    col = 1.0 - exp(-col * 1.35);
    OutputUAV[id.xy] = float4(pow(saturate(col), 1.0 / 2.2), 1.0);
}
