// link_gen preview — thin strokes so the link buffer is provable on its own.

struct LinkRecord
{
    float2 a; float2 b; float2 c; float2 d;
    float width; float group_id; float style; float intensity;
    float progress; float active; float curve; float pad0;
};

StructuredBuffer<LinkRecord> Links : register(t0);
RWTexture2D<float4> OutputUAV : register(u0);

float sdSeg(float2 p, float2 a, float2 b)
{
    float2 pa = p - a, ba = b - a;
    float h = saturate(dot(pa, ba) / max(dot(ba, ba), 1e-6));
    return length(pa - ba * h);
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;

    float asp = _Resolution.x / _Resolution.y;
    float2 P = (((float2)pixel + 0.5) / _Resolution.xy) * float2(asp, 1.0);

    float m = 0.0;
    [loop]
    for (uint i = 0u; i < 192u; i++)
    {
        LinkRecord L = Links[i];
        if (L.active < 0.5) continue;
        float d = sdSeg(P, L.a * float2(asp, 1.0), L.b * float2(asp, 1.0));
        m = max(m, 1.0 - smoothstep(0.0, 0.004, d));
    }
    float3 col = lerp(float3(0.6, 0.8, 1.0), float3(1.0, 0.5, 0.15), 0.0) * m;
    OutputUAV[pixel] = float4(col, m);
}
