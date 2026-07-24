RWTexture2D<float4> OutputUAV : register(u0);

float hash11(float n) { return frac(sin(n * 127.1) * 43758.5453); }
float hash21(float2 p) { return frac(sin(dot(p, float2(41.7, 113.9))) * 43758.5453); }

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)pixel + 0.5) / _Resolution.xy;
    float aspect = _Resolution.x / _Resolution.y;
    float2 p = (uv - 0.5) * float2(aspect, 1.0);
    float3 col = 0.0;
    const int count = 72;
    [unroll]
    for (int i = 0; i < count; ++i)
    {
        float fi = (float)i;
        float u = hash11(fi * 2.31 + 1.7);
        float v = hash11(fi * 3.77 + 8.4);
        float z = v * 2.0 - 1.0;
        float a = u * 6.2831853 + _Time * orbit * (0.55 + hash11(fi + 4.0) * 0.45);
        float rr = sqrt(max(1.0 - z * z, 0.0)) * radius;
        float3 pos3 = float3(cos(a) * rr, z * radius, sin(a) * rr);
        float2 pos = pos3.xy;
        pos.x *= 1.0 + pos3.z * 0.16;
        float d = length(p - pos);
        float depthFade = 0.35 + 0.65 * saturate(0.5 + pos3.z * depth);
        float seed = hash11(fi * 9.1 + floor(_Time * 0.35));
        float active = step(1.0 - density, hash11(fi * 5.19));
        float dotMask = smoothstep(point_size, point_size * 0.18, d);
        col += dotMask * active * depthFade * tint * brightness;
    }
    // Keep the shell at the edge so it frames rather than occludes the sculpture.
    float edge = smoothstep(0.38, 0.82, length(p));
    OutputUAV[pixel] = float4(col * edge, 1.0);
}
