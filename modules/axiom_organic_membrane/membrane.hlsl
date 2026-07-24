#include "../_shared/anim/anim.hlsli"

StructuredBuffer<float4> PhaseState : register(t2);
RWTexture2D<float4> OutputUAV : register(u0);

float2 rotate2(float2 p, float a)
{
    float s = sin(a);
    float c = cos(a);
    return float2(c * p.x - s * p.y, s * p.x + c * p.y);
}

float2 perpendicular(float2 v)
{
    return float2(-v.y, v.x);
}

float organicNoise(float2 p, float2 orbit)
{
    float a = fbm2D(p * warp_scale + orbit * 0.83, 5);
    float b = fbm2D(rotate2(p, 1.047) * warp_scale * 1.21 - orbit.yx * 0.67 + 11.73, 4);
    return lerp(a, 1.0 - abs(b * 2.0 - 1.0), fold_character);
}

float2 flowVector(float2 p, float phaseValue)
{
    float tau = phaseValue * AN_TAU;
    float2 orbit = float2(cos(tau), sin(tau));
    float n0 = fbm2D(p * warp_scale + orbit * 0.72, 5);
    float n1 = fbm2D(rotate2(p, 1.31) * warp_scale - orbit.yx * 0.61 + 19.2, 5);
    float2 flow = (float2(n0, n1) - 0.5) * 2.0;

    float2 centerA = float2(cos(tau * 0.73), sin(tau * 0.73)) * float2(0.38, 0.23);
    float2 centerB = float2(cos(-tau * 0.51 + 2.1), sin(-tau * 0.51 + 2.1)) * float2(0.49, 0.29);
    float2 dA = p - centerA;
    float2 dB = p - centerB;
    float wA = exp(-dot(dA, dA) * 3.8);
    float wB = exp(-dot(dB, dB) * 4.6);
    flow += perpendicular(dA) * wA * vortex_amount;
    flow -= perpendicular(dB) * wB * vortex_amount * 0.82;
    return flow;
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

    float maskValue = _Tex1.SampleLevel(LinearSampler, uv, 0).r;
    float localizedMask = smoothstep(mask_threshold - mask_softness,
                                     mask_threshold + mask_softness,
                                     maskValue);
    float distortionMask = lerp(1.0, localizedMask, mask_influence);
    float localAmount = displacement * lerp(mask_floor, 1.0 + mask_gain, distortionMask);

    float2 flow = flowVector(p, phaseValue);
    float2 uvOffset = flow * localAmount / float2(aspect, 1.0);
    float2 warpedUv = uv + uvOffset;

    // Directional echo samples stretch ink into short organic ligaments instead
    // of merely bending the original rectilinear edges.
    float3 rigidSource = _Tex0.SampleLevel(LinearSampler, uv, 0).rgb;
    float3 s0 = _Tex0.SampleLevel(LinearSampler, warpedUv, 0).rgb;
    float3 s1 = _Tex0.SampleLevel(LinearSampler, warpedUv - uvOffset * 0.42, 0).rgb;
    float3 s2 = _Tex0.SampleLevel(LinearSampler, warpedUv + uvOffset * 0.23, 0).rgb;
    float3 draggedSource = s0 * (1.0 - ink_drag * 0.48) + s1 * ink_drag * 0.31 + s2 * ink_drag * 0.17;
    float3 source = lerp(rigidSource, draggedSource, distortionMask);

    float2 orbit = float2(cos(tau), sin(tau));
    float membrane = organicNoise(p + flow * 0.19, orbit);
    float secondary = organicNoise(rotate2(p, -0.77) + 3.4, -orbit.yx);
    float tissue = saturate(lerp(membrane, membrane * secondary * 1.65, fold_character));

    // Animated erosion actually changes connectivity. This gives Features
    // moving islands rather than a homeomorphic bend of one giant rectangle.
    float tearGate = smoothstep(tear_threshold - tear_softness,
                                tear_threshold + tear_softness,
                                tissue);
    float gate = lerp(1.0, tearGate, tear_amount * distortionMask);
    float3 col = source * gate;

    // Pick up a restrained warm membrane edge from the real displaced signal.
    float eps = 2.0 / max(1.0, _Resolution.y);
    float nx = organicNoise(p + float2(eps, 0.0) + flow * 0.19, orbit);
    float ny = organicNoise(p + float2(0.0, eps) + flow * 0.19, orbit);
    float grad = saturate(length(float2(nx - membrane, ny - membrane)) / max(eps, 1e-5) * 0.045);
    float filament = smoothstep(0.18, 0.72, grad) * (1.0 - tearGate) * filament_amount * distortionMask;
    float sourceLuma = dot(source, float3(0.2126, 0.7152, 0.0722));
    col = lerp(col, accent_color * (0.42 + sourceLuma * 0.58), filament);

    // A moving pressure ridge makes the displacement legible as performance
    // motion without adding unrelated decorative telemetry.
    float ridgePhase = dot(p, normalize(float2(0.82, 0.57))) * 2.4 - tau;
    float ridge = pow(0.5 + 0.5 * sin(ridgePhase), 18.0) * pressure_ridge;
    col += ridge * sourceLuma * accent_color * 0.22 * distortionMask;

    OutputUAV[pixel] = float4(saturate(col), 1.0);
}
