RWTexture2D<float4> OutputUAV : register(u0);

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)pixel + 0.5) / _Resolution.xy;
    float2 texel = 1.0 / _Resolution.xy;
    float3 nowCol = _Tex0.SampleLevel(LinearSampler, uv, 0).rgb;
    float3 oldCol = _Tex1.SampleLevel(LinearSampler, uv, 0).rgb;
    float3 bleedCol = 0.25 * (_Tex1.SampleLevel(LinearSampler, uv + texel * float2(1, 0), 0).rgb
                            + _Tex1.SampleLevel(LinearSampler, uv + texel * float2(-1, 0), 0).rgb
                            + _Tex1.SampleLevel(LinearSampler, uv + texel * float2(0, 1), 0).rgb
                            + _Tex1.SampleLevel(LinearSampler, uv + texel * float2(0, -1), 0).rgb);
    float3 memory = lerp(oldCol, bleedCol, bleed);
    float2 p = (uv - 0.5) * float2(_Resolution.x / _Resolution.y, 1.0);
    float vignetteMask = 1.0 - vignette * smoothstep(0.42, 0.95, length(p));
    float3 outCol = nowCol * current_gain + memory * feedback * memory_gain;
    OutputUAV[pixel] = float4(max(outCol * vignetteMask, 0.0), 1.0);
}
