RWTexture2D<float4> OutputUAV : register(u0);

float2 rot2(float2 p, float a)
{
    float s = sin(a), c = cos(a);
    return float2(c * p.x - s * p.y, s * p.x + c * p.y);
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)pixel + 0.5) / _Resolution.xy;
    float aspect = _Resolution.x / _Resolution.y;
    float2 p = (uv - 0.5) * float2(aspect, 1.0);
    float r = length(p);
    float t = _Time * drift;
    float3 baseCol = _Tex0.SampleLevel(LinearSampler, uv, 0).rgb;
    float3 col = baseCol;

    // Three nested views: a spatial chamber around the existing hero, not a
    // full-frame additive wash. Each echo is clipped to a different radius.
    [unroll]
    for (int i = 1; i <= 3; ++i)
    {
        float fi = (float)i;
        float sc = pow(scale_step, fi);
        float2 q = rot2(p / sc, rotation * fi + sin(t + fi) * 0.035);
        q += float2(cos(t * 1.3 + fi * 2.1), sin(t * 1.1 + fi * 1.7)) * offset * fi * 0.08;
        float2 sampleUV = q / float2(aspect, 1.0) + 0.5;
        float inside = smoothstep(0.52 / sc + 0.04, 0.52 / sc - 0.02, length(q));
        float band = smoothstep(0.10 + fi * 0.08, 0.17 + fi * 0.08, r) * (1.0 - smoothstep(0.44 + fi * 0.06, 0.58 + fi * 0.06, r));
        col += _Tex0.SampleLevel(LinearSampler, saturate(sampleUV), 0).rgb * inside * band * echo_gain / fi;
    }
    float vignette = 1.0 - smoothstep(0.74, 1.02, r);
    OutputUAV[pixel] = float4(max(col * (0.82 + 0.18 * vignette), 0.0), 1.0);
}
