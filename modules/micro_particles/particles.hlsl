RWTexture2D<float4> OutputUAV : register(u0);

float hash11(float n)
{
    return frac(sin(n * 127.1 + 311.7) * 43758.5453);
}

float hash21(float2 p)
{
    return frac(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)pixel + 0.5) / _Resolution.xy;
    float2 p = (uv - 0.5) * float2(_Resolution.x / _Resolution.y, 1.0);
    float3 col = 0.0;
    int count = clamp(density, 8, 96);
    float t = _Time * drift;

    for (int i = 0; i < 96; ++i)
    {
        if (i >= count) break;
        float fi = (float)i + seed * 13.17;
        float2 q = float2(hash11(fi + 2.3), hash11(fi + 8.9));
        q = (q - 0.5) * float2(1.75, 1.05) * spread;
        q.x += sin(t * (0.35 + hash11(fi) * 0.55) + fi) * 0.035;
        q.y += cos(t * (0.22 + hash11(fi + 4.0) * 0.4) + fi * 0.7) * 0.028;
        float2 d = p - q;
        float r = (0.0018 + hash11(fi + 12.0) * 0.0045) * scale;
        float dotp = exp(-dot(d, d) / max(r * r, 0.000001));
        float twinkle = 0.55 + 0.45 * sin(_Time * (0.8 + hash11(fi + 21.0) * 1.8) + fi);
        col += dotp * twinkle;
    }

    OutputUAV[pixel] = float4(col * particle_color * brightness, 1.0);
}
