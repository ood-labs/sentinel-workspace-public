// Preview for ShapeRecord buffers: simple marker view of all active records.

RWTexture2D<float4> OutputUAV : register(u0);

struct ShapeRecord {
    float4 p0;
    float4 p1;
    float4 color;
    float4 style;
};

StructuredBuffer<ShapeRecord> Shapes : register(t0);

float segDist(float2 p, float2 a, float2 b)
{
    float2 pa = p - a;
    float2 ba = b - a;
    float h = saturate(dot(pa, ba) / max(dot(ba, ba), 1e-5));
    return length(pa - ba * h);
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)pixel + 0.5) / _Resolution.xy;
    float3 col = float3(0.02, 0.025, 0.028);

    [loop]
    for (uint i = 0; i < 32; ++i)
    {
        ShapeRecord r = Shapes[i];
        if (r.style.z < 0.5 || r.color.a <= 0.0) continue;
        float d = min(length(uv - r.p0.xy), segDist(uv, r.p0.xy, r.p1.xy));
        float m = 1.0 - smoothstep(0.0, 0.006, d);
        col += r.color.rgb * m;
    }
    OutputUAV[pixel] = float4(saturate(col), 1.0);
}
