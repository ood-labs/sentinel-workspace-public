RWTexture2D<float4> OutputUAV : register(u0);

float luminance(float3 c)
{
    return dot(c, float3(0.2126, 0.7152, 0.0722));
}

float hash21(float2 p)
{
    p = frac(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return frac(p.x * p.y);
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    if (tid.x >= (uint)_Resolution.x || tid.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)tid.xy + 0.5) / _Resolution.xy;
    float2 texel = 1.0 / _Resolution.xy;
    float3 center = _Tex0.SampleLevel(LinearSampler, uv, 0).rgb;
    float3 local = 0.25 * (
        _Tex0.SampleLevel(LinearSampler, saturate(uv + float2(texel.x, 0.0)), 0).rgb +
        _Tex0.SampleLevel(LinearSampler, saturate(uv - float2(texel.x, 0.0)), 0).rgb +
        _Tex0.SampleLevel(LinearSampler, saturate(uv + float2(0.0, texel.y)), 0).rgb +
        _Tex0.SampleLevel(LinearSampler, saturate(uv - float2(0.0, texel.y)), 0).rgb
    );
    float3 sharpened = center + (center - local) * sharpen;
    float3 graded = max(sharpened - black_lift, 0.0);
    graded = (graded - 0.5) * contrast + 0.5;
    graded *= exposure;
    // Exponential print shoulder preserves separation in dense white record
    // clusters instead of pushing every overlapping marker to display white.
    graded = 1.0 - exp(-graded * highlight_rolloff);

    float l = luminance(graded);
    float3 neutral = l.xxx;
    float amberMask = saturate(graded.r - max(graded.g, graded.b) * 1.45);
    graded = lerp(neutral, graded, saturation);
    graded = lerp(graded, max(graded, center), amberMask * accent_preservation);

    float px = 1.0 / _Resolution.y;
    float2 safeMin = float2(0.035, 0.062);
    float2 safeMax = 1.0 - safeMin;
    float safeEdge = min(
        min(abs(uv.x - safeMin.x), abs(uv.x - safeMax.x)),
        min(abs(uv.y - safeMin.y), abs(uv.y - safeMax.y)));
    bool inHorizontalRange = uv.x >= safeMin.x && uv.x <= safeMax.x;
    bool inVerticalRange = uv.y >= safeMin.y && uv.y <= safeMax.y;
    float safeLine = smoothstep(px * 1.4, px * 0.2, safeEdge)
                   * ((inHorizontalRange || inVerticalRange) ? 1.0 : 0.0);

    float cornerLength = 0.025;
    float cornerTicks = 0.0;
    cornerTicks = max(cornerTicks, step(abs(uv.y - safeMin.y), px) * step(uv.x, safeMin.x + cornerLength) * step(safeMin.x, uv.x));
    cornerTicks = max(cornerTicks, step(abs(uv.x - safeMin.x), px) * step(uv.y, safeMin.y + cornerLength) * step(safeMin.y, uv.y));
    cornerTicks = max(cornerTicks, step(abs(uv.y - safeMax.y), px) * step(safeMax.x - cornerLength, uv.x) * step(uv.x, safeMax.x));
    cornerTicks = max(cornerTicks, step(abs(uv.x - safeMax.x), px) * step(safeMax.y - cornerLength, uv.y) * step(uv.y, safeMax.y));
    graded += frame_ink * max(safeLine * safe_frame_mix * 0.18, cornerTicks * safe_frame_mix);

    graded += (hash21((float2)tid.xy + 17.0) - 0.5) * dither;
    OutputUAV[tid.xy] = float4(saturate(graded), 1.0);
}
