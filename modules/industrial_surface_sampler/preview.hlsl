// Preview surface sample points.

RWTexture2D<float4> OutputUAV : register(u0);

struct SurfacePoint {
    float3 anchor; float3 normal; float3 tangent; float2 uv;
    float parent_kind; float parent_id; float seed; float weight; float active;
};

StructuredBuffer<SurfacePoint> PreviewSamples : register(t0);

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)pixel + 0.5) / _Resolution.xy;
    float aspect = _Resolution.x / _Resolution.y;
    float2 q = (uv - 0.5) * float2(aspect, 1.0);
    float3 col = float3(0.01, 0.012, 0.014);

    [loop]
    for (uint i = 0u; i < 2048u; i++)
    {
        SurfacePoint s = PreviewSamples[i];
        if (s.active < 0.5) continue;
        float2 p = s.anchor.xz * preview_scale + float2(preview_offset.x, -preview_offset.y);
        float d = length((q - p) * float2(aspect, 1.0));
        float a = 1.0 - smoothstep(0.0, 0.005, d);
        col += lerp(float3(0.2,0.45,0.9), float3(0.9,0.85,0.6), s.weight) * a;
    }

    OutputUAV[pixel] = float4(col, 1.0);
}
