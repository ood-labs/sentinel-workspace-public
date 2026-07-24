RWTexture2D<float4> OutputUAV : register(u0);

float hash11(float n) { return frac(sin(n * 91.17 + 17.3) * 43127.1); }

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)pixel + 0.5) / _Resolution.xy;
    float2 p = (uv - 0.5) * float2(_Resolution.x / _Resolution.y, 1.0);
    float t = _Time * drift;
    float r = length(p);
    float a = atan2(p.y, p.x) + t * 0.08 + sin(r * 5.0 + t) * warp * 0.08;
    float3 col = 0.0;

    for (int i = 1; i <= 24; ++i)
    {
        if (i > rings) break;
        float fi = (float)i;
        float target = 0.12 + fi * 0.085;
        float width = 0.0025 + 0.0015 * hash11(fi + 4.0);
        float ring = exp(-abs(r - target - sin(a * 3.0 + t + fi) * warp * 0.006) / width);
        float gate = smoothstep(0.08, 0.2, r) * (1.0 - smoothstep(0.82, 1.05, r));
        col += ring * gate * (0.3 + 0.7 * hash11(fi + 9.0));
    }

    float sector = abs(sin(a * max((float)cuts, 2.0) + t * 0.16));
    float spokes = pow(saturate(1.0 - sector), 34.0) * smoothstep(0.12, 0.25, r) * (1.0 - smoothstep(0.78, 1.02, r));
    col += spokes * (0.45 + 0.25 * sin(t + r * 8.0));

    float depthFade = smoothstep(1.05, 0.12, r) * (0.55 + 0.45 * sin(t * 0.7 + r * 12.0));
    OutputUAV[pixel] = float4(col * depthFade * portal_color * brightness, 1.0);
}
