RWTexture2D<float4> OutputUAV : register(u0);

float2 rot2(float2 p, float a)
{
    float s = sin(a), c = cos(a);
    return float2(c * p.x - s * p.y, s * p.x + c * p.y);
}

float hash12(float2 p) { return frac(sin(dot(p, float2(41.7, 113.9))) * 43758.5453); }

float3 sample_scene(float2 q)
{
    return _Tex0.SampleLevel(LinearSampler, saturate(q), 0).rgb;
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)pixel + 0.5) / _Resolution.xy;
    float aspect = _Resolution.x / _Resolution.y;
    float2 p = (uv - 0.5) * float2(aspect, 1.0);
    float radius = length(p);
    float ang = atan2(p.y, p.x) + rotation + sin(_Time * drift) * 0.08;
    float sector = 6.2831853 / 4.0;
    float local = (frac((ang + 3.1415926) / sector) - 0.5) * sector;
    float seamMask = smoothstep(seam, seam * 0.18, abs(local));

    // Reflect each outer sector toward its nearest radial seam, creating four
    // coherent glass shards while leaving the hero aperture readable.
    float folded = abs(local) * fold;
    float2 q = float2(cos(ang + folded), sin(ang + folded)) * radius;
    q += float2(sin(_Time * drift * 1.7 + radius * 8.0), cos(_Time * drift * 1.3 + radius * 7.0)) * 0.008 * fold;
    float2 shardUV = q / float2(aspect, 1.0) + 0.5;

    float3 baseCol = sample_scene(uv);
    float3 shardCol = sample_scene(shardUV);
    float outer = smoothstep(0.20, 0.62, radius);
    float shardMask = outer * (0.35 + 0.65 * seamMask) * shards;
    float glint = pow(saturate(1.0 - abs(local) / max(sector * 0.5, 0.001)), 18.0);
    float3 col = lerp(baseCol, shardCol, saturate(shardMask * output_mix));
    col += glint.xxx * edge_glint * outer * 0.055;
    col *= 1.0 + (hash12((float2)pixel + floor(_Time * 3.0)) - 0.5) * 0.012 * outer;
    OutputUAV[pixel] = float4(max(col, 0.0), 1.0);
}
