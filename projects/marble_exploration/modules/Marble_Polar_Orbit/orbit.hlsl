RWTexture2D<float4> OutputUAV : register(u0);

float2 rot2(float2 p, float a)
{
    float s = sin(a), c = cos(a);
    return float2(c * p.x - s * p.y, s * p.x + c * p.y);
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)pixel + 0.5) / _Resolution.xy;
    float aspect = _Resolution.x / _Resolution.y;
    float2 p = (uv - 0.5) * float2(aspect, 1.0);
    float r = length(p);
    float a = atan2(p.y, p.x);
    float t = _Time * drift;
    float bandPhase = a / 6.2831853 * bands + t + sin(r * 9.0) * warp;
    float band = frac(bandPhase);
    float seam = smoothstep(0.12, 0.02, min(band, 1.0 - band));
    float radial = saturate(r * 1.35);
    float2 polarUV = float2(frac(r * 1.4 + bandPhase * 0.035), frac(a / 6.2831853 + r * warp + _Time * spin * 0.04));
    polarUV = rot2(polarUV - 0.5, sin(t) * 0.08) + 0.5;
    float3 baseCol = _Tex0.SampleLevel(LinearSampler, uv, 0).rgb;
    float3 orbitCol = _Tex0.SampleLevel(LinearSampler, saturate(polarUV), 0).rgb;
    float ringMask = smoothstep(0.18, 0.32, r) * (1.0 - smoothstep(0.78, 1.05, r));
    float3 col = lerp(baseCol, orbitCol, ringMask * warp * orbit_gain);
    col += orbitCol * seam * ringMask * orbit_gain * 0.22;
    col = lerp(col, baseCol, center_mix * (1.0 - smoothstep(0.05, 0.26, r)));
    OutputUAV[pixel] = float4(max(col, 0.0), 1.0);
}
