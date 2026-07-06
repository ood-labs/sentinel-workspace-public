// abstract_triangle_render: consumes TriangleRecord data and renders the column.

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
    float3 col = 0.0;
    float alpha = 0.0;

    [loop]
    for (uint i = 0; i < _Data0_Count; ++i)
    {
        TriangleRecord r = Triangles[i];
        if (r.p1.z < 0.5) continue;
        float2 f = (uv - r.p0.xy) / max(r.p0.zw, 1e-4);
        float inCell = step(0.0, f.x) * step(0.0, f.y) * step(f.x, 1.0) * step(f.y, 1.0);
        float tri = (r.p1.x < 0.5) ? step(f.x + f.y, 1.0) : step(1.0, f.x + f.y);
        float m = inCell * tri;
        float edge = 1.0 - smoothstep(0.0, 0.025, min(abs(f.x + f.y - 1.0), min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y))));
        float3 c = r.color.rgb * r.p1.y + edge * 0.035;
        col = lerp(col, c, m * r.color.a * intensity);
        alpha = max(alpha, m * r.color.a * intensity);
    }
    OutputUAV[pixel] = float4(saturate(col), saturate(alpha));
}
