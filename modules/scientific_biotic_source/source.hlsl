#include "../_shared/anim/anim.hlsli"
#include "types.hlsli"

StructuredBuffer<StimulusRecord> Stimuli : register(t1);
RWTexture2D<float4> OutputUAV : register(u0);

float lineDistance(float2 p, float2 a, float2 b) {
    float2 segment = b - a;
    float t = saturate(dot(p - a, segment) / max(dot(segment, segment), 1e-6));
    return length(p - (a + segment * t));
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    if (tid.x >= (uint)_Resolution.x || tid.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)tid.xy + 0.5) / _Resolution.xy;
    float aspect = _Resolution.x / max(_Resolution.y, 1.0);
    float2 p = (uv - 0.5) * float2(aspect, 1.0);
    float4 field = _Tex0.SampleLevel(LinearSampler, uv, 0);
    float density = field.r;
    float2 gradient = field.gb * 2.0 - 1.0;
    float gradientMagnitude = length(gradient);

    float band = abs(frac(density * contour_bands + 0.5) - 0.5);
    float membranes = smoothstep(0.19, 0.03, band) * membrane_gain;
    float thresholdBody = smoothstep(0.36, 0.62, density);
    float scan = smoothstep(0.032, 0.0, abs(frac(uv.y * 54.0 + density * 3.0) - 0.5) - 0.46);
    float grid = smoothstep(0.012, 0.0, min(abs(frac(uv.x * 24.0) - 0.5), abs(frac(uv.y * 14.0) - 0.5)));
    float3 color = float3(0.003, 0.004, 0.003);
    color += float3(0.10, 0.105, 0.10) * thresholdBody * 0.42;
    color += float3(0.84, 0.85, 0.80) * membranes;
    color += float3(0.22, 0.23, 0.21) * gradientMagnitude * 0.35;
    color += float3(0.055, 0.058, 0.052) * grid * grid_gain;
    color += float3(0.11, 0.115, 0.10) * scan * scan_gain;

    float amberEnergy = 0.0;
    float leaderEnergy = 0.0;
    [unroll] for (uint i = 0u; i < 16u; ++i) {
        if (!stimulusActive(Stimuli[i])) continue;
        float2 seedP = (Stimuli[i].position - 0.5) * float2(aspect, 1.0);
        float2 d = p - seedP;
        float radius = max(Stimuli[i].radius, 0.015);
        float distanceToSeed = length(d);
        float ring = exp(-pow((distanceToSeed - radius * 1.25) / max(radius * 0.13, 0.004), 2.0));
        float core = exp(-dot(d, d) / max(radius * radius * 0.3, 1e-5));
        amberEnergy += (ring * 0.65 + core * 0.25) * saturate(Stimuli[i].mode) * Stimuli[i].strength;
        float2 direction = normalize(Stimuli[i].direction + 1e-4);
        leaderEnergy += exp(-lineDistance(p, seedP, seedP + direction * radius * 1.8) * 260.0)
                      * (0.3 + 0.7 * saturate(Stimuli[i].mode));
    }
    color += accent_color * (amberEnergy * accent_gain + leaderEnergy * 0.22);

    float vignette = saturate(1.0 - dot((uv - 0.5) * float2(1.1, 1.8), (uv - 0.5) * float2(1.1, 1.8)));
    color *= 0.48 + 0.52 * vignette;
    color = color / (1.0 + color);
    color = pow(saturate(color), 1.0 / 2.2);
    OutputUAV[tid.xy] = float4(color, 1.0);
}
