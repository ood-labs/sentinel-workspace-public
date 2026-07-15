struct FractalSeed {
    float4 orbit;
    float4 color;
    float4 rule;
    float4 warp;
};

StructuredBuffer<FractalSeed> Seeds : register(t0);
RWTexture2D<float4> OutputUAV : register(u0);

float lineMask(float d, float w)
{
    return 1.0 - smoothstep(w, w + 0.004, d);
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;

    float2 uv = ((float2)pixel + 0.5) / _Resolution.xy;
    float2 p = (uv - 0.5) * float2(_Resolution.x / _Resolution.y, 1.0) * 2.0;
    float3 col = float3(0.015, 0.018, 0.025);

    float grid = max(lineMask(abs(frac(p.x * 4.0 + 0.5) - 0.5) / 4.0, 0.0015),
                     lineMask(abs(frac(p.y * 4.0 + 0.5) - 0.5) / 4.0, 0.0015));
    col += float3(0.035, 0.05, 0.075) * grid;

    [loop]
    for (uint i = 0; i < 64; ++i)
    {
        FractalSeed s = Seeds[i];
        if (s.rule.w < 0.5) continue;
        float2 c = s.orbit.xy;
        float d = length(p - c);
        float r = s.orbit.z;
        float core = 1.0 - smoothstep(r * 0.28, r * 0.28 + 0.01, d);
        float halo = max(0.0, 1.0 - d / max(r * 3.2, 0.001));
        col += s.color.rgb * (core * 0.9 + halo * halo * 0.24);
    }

    OutputUAV[pixel] = float4(saturate(col), 1.0);
}
