#include "../_shared/anim/anim.hlsli"

StructuredBuffer<float4> PhaseState : register(t0);
RWTexture2D<float4> OutputUAV : register(u0);

float2 rot(float2 p, float a)
{
    float s = sin(a);
    float c = cos(a);
    return float2(c * p.x - s * p.y, s * p.x + c * p.y);
}

float fieldCells(float2 p, float2 orbit)
{
    float a = fbm2D(p * field_scale + orbit * evolution_amount * 0.71, 5);
    float b = fbm2D(rot(p, 1.19) * field_scale * 1.34 - orbit.yx * evolution_amount * 0.63 + 7.9, 4);
    return saturate(a * 0.64 + b * 0.36);
}

float fieldVeins(float2 p, float2 orbit)
{
    float a = fbm2D(p * field_scale + orbit * evolution_amount * 0.82, 5);
    float b = fbm2D(rot(p, -0.91) * field_scale * 0.73 + orbit.yx * evolution_amount * 0.55 + 14.1, 5);
    float foldA = 1.0 - abs(a * 2.0 - 1.0);
    float foldB = 1.0 - abs(b * 2.0 - 1.0);
    return saturate(foldA * foldB * 1.72);
}

float2 travelingCarrier(float tau)
{
    float x = cos(tau * 0.91) + sin(tau * 1.73 + 1.4) * 0.26;
    float y = sin(tau * 0.67 + 0.35) + cos(tau * 1.31 - 0.8) * 0.22;
    return float2(x, y * travel_eccentricity) * travel_amount;
}

float fieldEclipses(float2 p, float tau, float2 evolutionOrbit)
{
    // The carrier translates the whole pressure ecology across the plate.
    // Smaller counter-rotating bodies then continuously change its silhouette.
    float2 q = p - travelingCarrier(tau);
    float2 c0 = float2(cos(tau * 0.73), sin(tau * 0.73)) * float2(0.28, 0.19);
    float2 c1 = float2(cos(-tau * 0.51 + 2.2), sin(-tau * 0.51 + 2.2)) * float2(0.39, 0.21);
    float2 c2 = float2(cos(tau * 0.37 + 4.1), sin(tau * 0.37 + 4.1)) * float2(0.23, 0.31);
    float r0 = exp(-dot(q - c0, q - c0) * 3.5);
    float r1 = exp(-dot(q - c1, q - c1) * 4.8);
    float r2 = exp(-dot(q - c2, q - c2) * 6.1);
    float cut = saturate(r0 + r1 * 0.86 - r2 * 0.72);
    float grain = fbm2D(q * field_scale * 0.72 + evolutionOrbit * evolution_amount * 0.58, 5);
    float tornEdge = 1.0 - abs(grain * 2.0 - 1.0);
    return saturate(cut * (0.70 + tornEdge * 0.32) + grain * 0.24);
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;

    float2 uv = ((float2)pixel + 0.5) / _Resolution.xy;
    float aspect = _Resolution.x / max(1.0, _Resolution.y);
    float2 p = (uv - 0.5) * float2(aspect, 1.0) * 2.0;
    float phaseValue = frac(phase + PhaseState[0].x);
    float tau = phaseValue * AN_TAU;
    float evolutionTau = tau * evolution_rate;
    float2 orbit = float2(cos(evolutionTau), sin(evolutionTau));
    float2 carrier = travelingCarrier(tau);
    float2 traveledP = p - carrier;

    float raw;
    if (mask_mode == 1) raw = fieldVeins(traveledP, orbit);
    else if (mask_mode == 2) raw = fieldEclipses(p, tau, orbit);
    else raw = fieldCells(traveledP, orbit);

    // Pressure bands intersect the organic field; they make the mask suitable
    // for hard localized processing rather than a soft full-frame wobble.
    float bands = 0.5 + 0.5 * sin(dot(traveledP, normalize(float2(0.77, 0.63))) * band_density
                                  + tau * band_motion);
    raw = lerp(raw, raw * smoothstep(0.28, 0.78, bands), band_influence);
    raw = (raw - 0.5) * mask_contrast + 0.5;
    float mask = smoothstep(mask_threshold - mask_softness,
                            mask_threshold + mask_softness,
                            raw);
    mask = lerp(raw, mask, mask_binary);
    if (invert_mask != 0) mask = 1.0 - mask;

    OutputUAV[pixel] = float4(saturate(mask).xxx, 1.0);
}
