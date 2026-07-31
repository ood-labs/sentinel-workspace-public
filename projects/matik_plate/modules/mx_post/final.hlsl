// mx_post / final.hlsl — the plate's finishing pass: bloom, grade, grain, vignette, edge burn.
//
// The reference is a printed-looking monochrome plate: dense hairlines with a faint halo, a
// little tooth in the blacks, and slightly heavier corners. Everything here is subtractive
// polish on an image that already reads; nothing structural happens in post.

RWTexture2D<float4> OutputUAV : register(u0);
// _Tex0 (composite), _Tex1 (glow), LinearSampler are engine-injected.

float hash21(float2 p)
{
    float3 p3 = frac(p.xyx * float3(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return frac((p3.x + p3.y) * p3.z);
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 px = DTid.xy;
    if (px.x >= (uint)_Resolution.x || px.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)px + 0.5) / _Resolution.xy;

    float3 base = _Tex0.SampleLevel(LinearSampler, uv, 0).rgb;
    float3 glow = _Tex1.SampleLevel(LinearSampler, uv, 0).rgb;

    float3 col = base + glow * glow_gain;

    // grade: lift the floor slightly so the blacks have tooth, then contrast about mid grey
    col = max(col + black_lift, 0.0);
    col = pow(max(col, 1e-5), 1.0 / max(gamma, 0.05));
    col = saturate((col - 0.5) * contrast + 0.5) * exposure;

    // vignette / edge burn
    float2 c = uv - 0.5;
    float vig = 1.0 - vignette * saturate(dot(c, c) * 2.6);
    col *= vig;

    // grain, animated per frame; strongest in the mid tones where paper texture shows
    float lum = dot(col, float3(0.299, 0.587, 0.114));
    float gsz = max(grain_size, 0.25);
    float2 gp = floor(uv * _Resolution.xy / gsz);
    float g = hash21(gp + frac(_Time * 24.0) * 137.0) - 0.5;
    col += g * grain * (0.35 + 0.65 * (1.0 - abs(lum * 2.0 - 1.0)));

    col *= tint;
    OutputUAV[px] = float4(saturate(col), 1.0);
}
