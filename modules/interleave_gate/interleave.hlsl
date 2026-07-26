RWTexture2D<float4> OutputUAV : register(u0);

float luminance(float3 c)
{
    return dot(c, float3(0.2126, 0.7152, 0.0722));
}

float gridEvidence(float2 uv)
{
    float3 c = _Tex1.SampleLevel(LinearSampler, saturate(uv), 0).rgb;
    float lum = luminance(c);
    float chroma = max(c.r, max(c.g, c.b)) - min(c.r, min(c.g, c.b));
    float neutral = 1.0 - smoothstep(0.025, 0.16, chroma);
    float midInk = smoothstep(0.018, 0.075, lum) * (1.0 - smoothstep(0.16, 0.42, lum));
    return midInk * neutral;
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;

    float2 uv = ((float2)pixel + 0.5) / _Resolution.xy;
    float2 texel = 1.0 / max(_Resolution.xy, float2(1.0, 1.0));
    float3 echoCol = _Tex0.SampleLevel(LinearSampler, uv, 0).rgb;
    float3 sourceCol = _Tex1.SampleLevel(LinearSampler, uv, 0).rgb;

    float radiusPx = cut_width;
    float2 ox = float2(texel.x * radiusPx, 0.0);
    float2 oy = float2(0.0, texel.y * radiusPx);
    float gridField = gridEvidence(uv);
    gridField = max(gridField, gridEvidence(uv + ox));
    gridField = max(gridField, gridEvidence(uv - ox));
    gridField = max(gridField, gridEvidence(uv + oy));
    gridField = max(gridField, gridEvidence(uv - oy));
    gridField = max(gridField, gridEvidence(uv + ox * 0.45 + oy * 0.45));
    gridField = max(gridField, gridEvidence(uv - ox * 0.45 - oy * 0.45));

    float aspect = _Resolution.x / max(_Resolution.y, 1.0);
    float2 p = (uv - 0.5) * float2(aspect, 1.0);
    float travelingBand = 0.5 + 0.5 * sin(
        p.x * 10.0 - p.y * 7.0 + _Time * 0.19
        + luminance(sourceCol) * 5.5
    );
    float cut = saturate(gridField * dissolve * lerp(0.45, 1.0, travelingBand));

    float echoLum = luminance(echoCol);
    float levels = max(2.0, tonal_steps);
    float quantized = floor(saturate(echoLum) * levels + 0.5) / levels;
    float3 echoTone = echoCol * (quantized / max(echoLum, 0.001));
    echoTone = min(echoTone, float3(1.0, 1.0, 1.0)) * echo_gain;

    float sourceLum = luminance(sourceCol);
    float orange = saturate((sourceCol.r - max(sourceCol.g, sourceCol.b)) * 3.2);
    float neutralTrace = smoothstep(0.025, 0.28, sourceLum) * (1.0 - orange);

    float3 col = echoTone * (1.0 - cut);
    col += sourceCol * neutralTrace * source_trace * (0.25 + 0.75 * cut);
    col += sourceCol * orange * signal_rescue;

    float voidMask = 1.0 - smoothstep(0.01, 0.055, luminance(col));
    col += voidMask * float3(0.0015, 0.0018, 0.0020);

    OutputUAV[pixel] = float4(saturate(col), 1.0);
}
