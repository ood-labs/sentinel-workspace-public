RWTexture2D<float4> OutputUAV : register(u0);

float hash21(float2 p) { return frac(sin(dot(p, float2(127.1, 311.7))) * 43758.5453); }

float dirt_blob(float2 p, float2 c, float radius)
{
    float2 q = (p - c) / radius;
    float n = hash21(floor(c * 97.0));
    float d = length(q);
    float irregular = 0.72 + 0.28 * sin(q.x * 5.0 + n * 6.0) * sin(q.y * 4.0 + n * 4.0);
    return smoothstep(1.0, 0.35, d / max(irregular, 0.1));
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)pixel + 0.5) / _Resolution.xy;
    float2 p = uv - 0.5;
    float aspect = _Resolution.x / _Resolution.y;
    p.x *= aspect;
    float r = length(p);
    float t = _Time * drift;

    // Thick glass: radial bend plus a fine off-axis wobble.
    float2 bend = p * (r * r) * distortion;
    bend += float2(sin(p.y * 18.0 + t) * 0.001, cos(p.x * 15.0 - t * 0.7) * 0.001) * distortion * 12.0;
    float2 warped = uv + bend / float2(aspect, 1.0);
    float2 ca = float2(aberration * (0.2 + r), 0.0);

    float3 col;
    col.r = _Tex0.SampleLevel(LinearSampler, warped + ca, 0).r;
    col.g = _Tex0.SampleLevel(LinearSampler, warped, 0).g;
    col.b = _Tex0.SampleLevel(LinearSampler, warped - ca, 0).b;

    // A handful of large, irregular optical deposits and fine etched streaks.
    float dirtMask = 0.0;
    [unroll]
    for (int i = 0; i < 7; ++i)
    {
        float fi = (float)i;
        float2 c = float2(hash21(float2(fi + 3.2, 8.1)), hash21(float2(fi + 11.4, 2.7))) - 0.5;
        c.x *= aspect;
        c += float2(sin(t * (0.3 + fi * 0.04) + fi) * 0.035, cos(t * 0.2 + fi) * 0.018);
        dirtMask += dirt_blob(p, c, 0.035 + hash21(float2(fi, 19.0)) * 0.07);
    }
    dirtMask = saturate(dirtMask) * dirt;
    float etched = pow(abs(sin((p.x * 21.0 + p.y * 7.0 + t * 0.12) * 3.14159)), 28.0);
    etched *= smoothstep(0.15, 0.8, r) * streaks;

    float grainNoise = hash21((float2)pixel + floor(_Time * 2.0)) - 0.5;
    col *= 1.0 - dirtMask * 0.32;
    col += etched.xxx * 0.028;
    col += grainNoise.xxx * grain;
    OutputUAV[pixel] = float4(max(col * lens_gain, 0.0), 1.0);
}
