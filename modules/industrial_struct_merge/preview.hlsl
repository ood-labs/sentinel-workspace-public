RWTexture2D<float4> OutputUAV : register(u0);

struct StructPart {
    float3 center; float3 axis; float3 up; float3 half_extents;
    float length; float radius; float kind; float material;
    float seed; float group; float active; float spare;
};

StructuredBuffer<StructPart> PreviewParts : register(t0);

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)pixel + 0.5) / _Resolution.xy;
    float aspect = _Resolution.x / _Resolution.y;
    float2 q = (uv - 0.5) * float2(aspect, 1.0);
    float3 col = float3(0.01,0.012,0.014);
    [loop]
    for (uint i = 0u; i < 1024u; i++)
    {
        StructPart p = PreviewParts[i];
        if (p.active < 0.5) continue;
        float2 pp = p.center.xz * preview_scale + float2(preview_offset.x, -preview_offset.y);
        float d = length((q - pp) * float2(aspect, 1.0));
        float a = 1.0 - smoothstep(0.0, 0.006 + p.radius * preview_scale * 0.02, d);
        col += lerp(float3(0.25,0.35,0.5), float3(0.9,0.8,0.55), p.material / 5.0) * a;
    }
    OutputUAV[pixel] = float4(col, 1.0);
}
