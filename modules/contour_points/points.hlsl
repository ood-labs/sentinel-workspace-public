RWTexture2D<float4> OutputUAV : register(u0);

float hash21(float2 p) { return frac(sin(dot(p, float2(41.7, 113.9))) * 43758.5453); }

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)pixel + 0.5) / _Resolution.xy;
    float2 texel = 1.0 / _Resolution.xy;
    float3 baseCol = _Tex0.SampleLevel(LinearSampler, uv, 0).rgb;
    float3 x0 = _Tex0.SampleLevel(LinearSampler, uv - float2(texel.x, 0), 0).rgb;
    float3 x1 = _Tex0.SampleLevel(LinearSampler, uv + float2(texel.x, 0), 0).rgb;
    float3 y0 = _Tex0.SampleLevel(LinearSampler, uv - float2(0, texel.y), 0).rgb;
    float3 y1 = _Tex0.SampleLevel(LinearSampler, uv + float2(0, texel.y), 0).rgb;
    float edge = length(float2(length(x1 - x0), length(y1 - y0)));
    float rnd = hash21((float2)pixel + floor(_Time * drift * 3.0));
    float2 p = (uv - 0.5) * float2(_Resolution.x / _Resolution.y, 1.0);
    float wobble = sin(_Time * drift + p.y * 20.0) * jitter;
    float d = length(frac((p + wobble) / max(point_size * 7.0, 0.001)) - 0.5) * point_size * 7.0;
    float dotMask = smoothstep(point_size, point_size * 0.15, d);
    float active = step(1.0 - density, rnd) * smoothstep(0.012, 0.07, edge);
    float3 points = float3(0.52, 0.72, 0.86) * dotMask * active * point_gain;
    OutputUAV[pixel] = float4(max(points + baseCol * base_mix, 0.0), 1.0);
}
