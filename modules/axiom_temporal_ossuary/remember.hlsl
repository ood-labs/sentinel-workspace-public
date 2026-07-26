#include "../_shared/anim/anim.hlsli"

RWTexture2D<float4> OutputUAV : register(u0);

float luminance(float3 color)
{
    return dot(color, float3(0.2126, 0.7152, 0.0722));
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    if (tid.x >= (uint)_Resolution.x || tid.y >= (uint)_Resolution.y) return;

    float2 uv = ((float2)tid.xy + 0.5) / _Resolution.xy;
    float tau = frac(phase) * AN_TAU;
    float2 orbit = float2(cos(tau), sin(tau));
    float n0 = fbm2D(uv * 5.7 + orbit * 0.62, 4);
    float n1 = fbm2D(uv.yx * 6.3 - orbit.yx * 0.55 + 9.4, 4);
    float2 flow = (float2(n0, n1) - 0.5) * advection;
    flow += float2(-orbit.y, orbit.x) * advection * 0.18;

    float2 prevUv = uv + flow;
    float3 previous = _Tex1.SampleLevel(LinearSampler, prevUv, 0).rgb;
    if (diffusion > 0.00001)
    {
        float2 spread = diffusion / max(_Resolution.xy, 1.0) * _Resolution.y;
        previous = (previous * 2.0
                  + _Tex1.SampleLevel(LinearSampler, prevUv + float2(spread.x, 0.0), 0).rgb
                  + _Tex1.SampleLevel(LinearSampler, prevUv - float2(spread.x, 0.0), 0).rgb
                  + _Tex1.SampleLevel(LinearSampler, prevUv + float2(0.0, spread.y), 0).rgb
                  + _Tex1.SampleLevel(LinearSampler, prevUv - float2(0.0, spread.y), 0).rgb) / 6.0;
    }

    float3 current = _Tex0.SampleLevel(LinearSampler, uv, 0).rgb;
    if (reset_memory != 0)
    {
        OutputUAV[tid.xy] = float4(current, 1.0);
        return;
    }

    float retention = saturate(memory);
    float3 fadedPrevious = lerp(paper_color, previous, retention);
    float motionDifference = abs(luminance(current) - luminance(previous));
    float moving = smoothstep(trail_threshold * 0.5, trail_threshold + 0.08, motionDifference);
    float3 remembered;

    if (memory_mode == 1)
    {
        remembered = lerp(current, fadedPrevious, retention * (0.42 + moving * 0.42));
        remembered.r = max(remembered.r, previous.r * accent_retention * moving);
    }
    else if (memory_mode == 2)
    {
        float previousInk = 1.0 - luminance(previous);
        float residue = smoothstep(trail_threshold, trail_threshold + 0.24, previousInk * moving);
        remembered = lerp(current, min(current, previous), residue * retention);
    }
    else
    {
        // Union dark engravings over a fading paper reference. This preserves
        // moving tracked structure without turning the whole frame to mud.
        float previousInk = smoothstep(trail_threshold, trail_threshold + 0.28,
                                       1.0 - luminance(fadedPrevious));
        float unionAmount = saturate(previousInk * retention * trail_gain);
        remembered = lerp(current, min(current, fadedPrevious), unionAmount);
        float accentMemory = saturate((previous.r - max(previous.g, previous.b)) * 2.4);
        remembered = lerp(remembered, accent_color,
                          accentMemory * accent_retention * retention * moving);
    }

    OutputUAV[tid.xy] = float4(saturate(remembered), 1.0);
}
