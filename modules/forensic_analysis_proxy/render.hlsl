RWTexture2D<float4> OutputUAV : register(u0);

float luminance(float3 c)
{
    return dot(c, float3(0.2126, 0.7152, 0.0722));
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    if (tid.x >= (uint)_Resolution.x || tid.y >= (uint)_Resolution.y) return;

    float2 uv = ((float2)tid.xy + 0.5) / _Resolution.xy;
    uint srcW;
    uint srcH;
    _Tex0.GetDimensions(srcW, srcH);
    float2 texel = 1.0 / max(float2(srcW, srcH), float2(1.0, 1.0));

    float3 c0 = _Tex0.SampleLevel(LinearSampler, uv, 0).rgb;
    float3 cx0 = _Tex0.SampleLevel(LinearSampler, uv - float2(texel.x, 0.0), 0).rgb;
    float3 cx1 = _Tex0.SampleLevel(LinearSampler, uv + float2(texel.x, 0.0), 0).rgb;
    float3 cy0 = _Tex0.SampleLevel(LinearSampler, uv - float2(0.0, texel.y), 0).rgb;
    float3 cy1 = _Tex0.SampleLevel(LinearSampler, uv + float2(0.0, texel.y), 0).rgb;

    float l0 = luminance(c0);
    float local = (luminance(cx0) + luminance(cx1) + luminance(cy0) + luminance(cy1)) * 0.25;
    float detail = abs(l0 - local) * detail_gain;
    float base = lerp(l0, max(l0, detail), detail_mix);
    base = saturate((base - black_point) * analysis_gain);

    float bands = max(2.0, posterize_steps);
    float quantized = floor(base * bands + 0.5) / bands;
    float hard = smoothstep(binary_threshold - binary_softness, binary_threshold + binary_softness, base);
    float signal = lerp(quantized, hard, binary_mix);

    // Analysis preview remains a readable miniature of the authored source.
    float3 paper = float3(0.84, 0.86, 0.83);
    float3 ink = float3(0.005, 0.006, 0.006);
    float3 col = lerp(ink, paper, signal);
    float warm = saturate(c0.r - max(c0.g, c0.b) * 1.35);
    col = lerp(col, float3(1.0, 0.30, 0.045), warm * preserve_current);

    // Hairline frame proves the exact analysis extent without becoming test imagery.
    float2 px = min((float2)tid.xy, _Resolution.xy - 1.0 - (float2)tid.xy);
    float frame = 1.0 - smoothstep(0.0, 1.5, min(px.x, px.y));
    col = lerp(col, paper * 0.55, frame);

    OutputUAV[tid.xy] = float4(saturate(col), 1.0);
}
