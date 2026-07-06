RWTexture2D<float4> OutputUAV : register(u0);

struct TriangleRecord {
    float4 p0;
    float4 p1;
    float4 color;
    float4 aux;
};

StructuredBuffer<TriangleRecord> Triangles : register(t0);

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)pixel + 0.5) / _Resolution.xy;
    float3 col = float3(0.025, 0.025, 0.025);
    [loop]
    for (uint i = 0; i < 128; ++i)
    {
        TriangleRecord r = Triangles[i];
        if (r.p1.z < 0.5) continue;
        float2 f = (uv - r.p0.xy) / max(r.p0.zw, 1e-4);
        float inside = step(0.0, f.x) * step(0.0, f.y) * step(f.x, 1.0) * step(f.y, 1.0);
        if (inside > 0.5) col = lerp(col, r.color.rgb * r.p1.y, 0.8);
    }
    OutputUAV[pixel] = float4(col, 1.0);
}
