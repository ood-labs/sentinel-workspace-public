// node_gen preview — cheap glow dots so the node buffer is independently provable.

struct NodeRecord
{
    float2 pos; float radius; float intensity;
    float color_mix; float kind; float seed; float active;
};

StructuredBuffer<NodeRecord> Nodes : register(t0);
RWTexture2D<float4> OutputUAV : register(u0);

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;

    float2 uv = ((float2)pixel + 0.5) / _Resolution.xy;
    float asp = _Resolution.x / _Resolution.y;

    float3 col = float3(0.0, 0.0, 0.0);
    [loop]
    for (uint i = 0u; i < 128u; i++)
    {
        NodeRecord n = Nodes[i];
        if (n.active < 0.5) continue;
        float2 d = (uv - n.pos) * float2(asp, 1.0);
        float dist = length(d);
        float core = exp(-dist * dist / max(n.radius * n.radius * 0.02, 1e-5));
        col += lerp(float3(0.8, 0.9, 1.0), float3(1.0, 0.55, 0.2), n.color_mix) * core * n.intensity;
    }
    OutputUAV[pixel] = float4(col, 1.0);
}
