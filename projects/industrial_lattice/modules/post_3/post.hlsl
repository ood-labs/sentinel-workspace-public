// industrial_mono_post - high-contrast black-and-white industrial photo grade.

RWTexture2D<float4> OutputUAV : register(u0);

float hash21(float2 p)
{
    p = frac(p * float2(123.34, 345.45));
    p += dot(p, p + 34.345);
    return frac(p.x * p.y);
}

float3 sceneAt(float2 uv)
{
    return _Tex0.SampleLevel(LinearSampler, saturate(uv), 0).rgb;
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)pixel + 0.5) / _Resolution.xy;
    float aspect = _Resolution.x / _Resolution.y;

    float3 scene = sceneAt(uv);
    float3 bloom = 0;
    float wsum = 0.0;
    [loop]
    for (int i = 0; i < 40; i++)
    {
        float fi = (float)i;
        float a = fi * 2.399963;
        float r = sqrt(fi / 40.0) * bloom_radius;
        float2 off = float2(cos(a), sin(a)) * r * float2(1.0 / aspect, 1.0);
        float3 s = sceneAt(uv + off);
        float l = dot(s, float3(0.299, 0.587, 0.114));
        float b = max(l - bloom_threshold, 0.0);
        bloom += s * b;
        wsum += 1.0;
    }

    float3 col = scene * exposure + bloom * (bloom_intensity / max(wsum, 1.0));
    float grey = dot(col, float3(0.299, 0.587, 0.114));
    grey = pow(max(grey, 0.0), gamma_lift);
    grey = (grey - 0.5) * contrast + 0.5;
    grey = smoothstep(crush_blacks, lift_highlights, grey);

    float warm = dot(col, float3(0.45, 0.36, 0.22));
    float cool = dot(col, float3(0.22, 0.32, 0.46));
    float toned = lerp(grey, grey + (warm - cool) * split_tone_amount, 0.35);
    float3 outCol = lerp(float3(toned, toned, toned), col, saturation);

    float2 q = (uv - 0.5) * float2(aspect, 1.0);
    outCol *= 1.0 - vignette * saturate(dot(q, q) * 1.65);

    float grain = (hash21(uv * _Resolution.xy + frac(_Time) * 83.0) - 0.5) * grain_amount;
    outCol += grain;

    OutputUAV[pixel] = float4(max(outCol, 0.0), 1.0);
}
