RWTexture2D<float4> OutputUAV : register(u0);

struct GreeblePart {
    float3 anchor; float3 normal; float3 tangent; float2 uv; float3 size;
    float kind; float material; float parent_id; float seed; float active; float spare;
};

StructuredBuffer<GreeblePart> PreviewGreebles : register(t0);

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)pixel + 0.5) / _Resolution.xy;
    float aspect = _Resolution.x / _Resolution.y;
    float2 q = (uv - 0.5) * float2(aspect, 1.0);
    float3 col = float3(0.006,0.007,0.009);
    [loop]
    for (uint i = 0u; i < 4096u; i++)
    {
        GreeblePart g = PreviewGreebles[i];
        if (g.active < 0.5) continue;
        float2 pp = g.anchor.xz * preview_scale + preview_offset;
        float d = length((q - pp) * float2(aspect, 1.0));
        float a = 1.0 - smoothstep(0.0, 0.0035 + max(g.size.x, g.size.y) * preview_scale, d);
        col += float3(0.74,0.78,0.82) * a;
    }
    OutputUAV[pixel] = float4(col, 1.0);
}
