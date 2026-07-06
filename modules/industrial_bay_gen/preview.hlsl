// Cheap top/side preview for industrial_bay_gen records.

RWTexture2D<float4> OutputUAV : register(u0);

struct StructPart {
    float3 center;
    float3 axis;
    float3 up;
    float3 half_extents;
    float length;
    float radius;
    float kind;
    float material;
    float seed;
    float group;
    float active;
    float spare;
};

StructuredBuffer<StructPart> PreviewParts : register(t0);

float2 projectPart(StructPart p, int viewMode)
{
    if (viewMode == 0) return p.center.xz * preview_scale + 0.5;
    return float2(p.center.x, p.center.y) * preview_scale + 0.5;
}

float hash(float x)
{
    x = frac(x * 0.1031);
    x *= x + 33.33;
    x *= x + x;
    return frac(x);
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)pixel + 0.5) / _Resolution.xy;
    float aspect = _Resolution.x / _Resolution.y;
    float2 q = (uv - 0.5) * float2(aspect, 1.0) + 0.5;

    float3 col = float3(0.015, 0.017, 0.019);
    float glow = 0.0;
    [loop]
    for (uint i = 0u; i < 512u; i++)
    {
        StructPart p = PreviewParts[i];
        if (p.active < 0.5) continue;
        float2 pp = projectPart(p, preview_mode);
        float d = length((q - pp) * float2(aspect, 1.0));
        float s = 1.0 - smoothstep(0.0, 0.008 + p.radius * preview_scale * 0.045, d);
        float k = p.kind / 12.0;
        float3 tint = lerp(float3(0.35,0.40,0.45), float3(0.85,0.78,0.58), hash(k + 0.1));
        col += tint * s * 0.75;
        glow = max(glow, s);
    }

    OutputUAV[pixel] = float4(col + glow * 0.08, 1.0);
}
