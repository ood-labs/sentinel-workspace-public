// Preview for the Y-up ribbon path records.

RWTexture2D<float4> OutputUAV : register(u0);

struct PNode {
    float2 pos; float2 dir;
    float depth; float u; float v; float weight; float group; float kind; float seed; float active;
};

StructuredBuffer<PNode> Path : register(t0);

float2 worldToUv(float2 p)
{
    float aspect = _Resolution.x / _Resolution.y;
    return float2(0.5 + p.x / max(aspect, 1e-4), 0.5 - p.y);
}

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
    float3 col = float3(0.025, 0.023, 0.024);

    [loop]
    for (uint i = 0; i < 159u; ++i)
    {
        PNode a = Path[i];
        PNode b = Path[i + 1u];
        if (a.active < 0.5 || b.active < 0.5) continue;
        float2 au = worldToUv(a.pos);
        float2 bu = worldToUv(b.pos);
        float d = segDist(uv, au, bu);
        float m = 1.0 - smoothstep(0.0, 0.004, d);
        float3 ramp = lerp(float3(1.0, 0.34, 0.05), float3(0.04, 0.02, 0.50), a.kind);
        col += ramp * m;

        float node = 1.0 - smoothstep(0.0, 0.006, length(uv - au));
        col += float3(0.8, 0.95, 0.8) * node * 0.45;
    }

    OutputUAV[pixel] = float4(saturate(col), 1.0);
}
