RWTexture2D<float4> OutputUAV : register(u0);

float luminance(float3 c) { return dot(c, float3(0.2126, 0.7152, 0.0722)); }

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)pixel + 0.5) / _Resolution.xy;
    float2 texel = 1.0 / _Resolution.xy;
    float3 baseCol = _Tex0.SampleLevel(LinearSampler, uv, 0).rgb;
    float l = luminance(baseCol);
    float gx = luminance(_Tex0.SampleLevel(LinearSampler, uv + float2(texel.x, 0), 0).rgb)
             - luminance(_Tex0.SampleLevel(LinearSampler, uv - float2(texel.x, 0), 0).rgb);
    float gy = luminance(_Tex0.SampleLevel(LinearSampler, uv + float2(0, texel.y), 0).rgb)
             - luminance(_Tex0.SampleLevel(LinearSampler, uv - float2(0, texel.y), 0).rgb);
    float edge = length(float2(gx, gy));
    float contour = smoothstep(threshold * 0.5, threshold, edge) * edge_gain;
    float2 p = (uv - 0.5) * float2(_Resolution.x / _Resolution.y, 1.0);
    float r = length(p);
    float band = abs(frac(l * quantize + _Time * drift) - 0.5) * 2.0;
    float registration = pow(saturate(1.0 - band), 18.0) * smoothstep(0.2, 0.85, r) * scan;
    float3 lineCol = float3(0.45, 0.68, 0.82) * (contour + registration * 0.42);
    float3 col = lerp(lineCol, baseCol, base_mix);
    OutputUAV[pixel] = float4(max(col, 0.0), 1.0);
}
