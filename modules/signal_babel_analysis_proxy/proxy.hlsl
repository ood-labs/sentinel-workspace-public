RWTexture2D<float4> OutputUAV : register(u0);

float luminance(float3 c)
{
    return dot(c, float3(0.299, 0.587, 0.114));
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 px = DTid.xy;
    if (px.x >= (uint)_Resolution.x || px.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)px + 0.5) / _Resolution.xy;
    float2 texel = 1.0 / _Resolution.xy;
    float radius = max(0.5, sample_radius);

    float tl = luminance(_Tex0.SampleLevel(LinearSampler, uv + texel * float2(-radius, -radius), 0).rgb);
    float tc = luminance(_Tex0.SampleLevel(LinearSampler, uv + texel * float2(0, -radius), 0).rgb);
    float tr = luminance(_Tex0.SampleLevel(LinearSampler, uv + texel * float2(radius, -radius), 0).rgb);
    float ml = luminance(_Tex0.SampleLevel(LinearSampler, uv + texel * float2(-radius, 0), 0).rgb);
    float mc = luminance(_Tex0.SampleLevel(LinearSampler, uv, 0).rgb);
    float mr = luminance(_Tex0.SampleLevel(LinearSampler, uv + texel * float2(radius, 0), 0).rgb);
    float bl = luminance(_Tex0.SampleLevel(LinearSampler, uv + texel * float2(-radius, radius), 0).rgb);
    float bc = luminance(_Tex0.SampleLevel(LinearSampler, uv + texel * float2(0, radius), 0).rgb);
    float br = luminance(_Tex0.SampleLevel(LinearSampler, uv + texel * float2(radius, radius), 0).rgb);

    float gx = -tl - 2.0 * ml - bl + tr + 2.0 * mr + br;
    float gy = -tl - 2.0 * tc - tr + bl + 2.0 * bc + br;
    float edge = saturate(length(float2(gx, gy)) * edge_gain);
    float plate = smoothstep(luma_low, luma_high, mc);
    float signal = saturate(lerp(plate, edge, edge_mix));
    signal = pow(signal, analysis_gamma);

    float gridX = step(0.96, frac(uv.x * 16.0));
    float gridY = step(0.96, frac(uv.y * 9.0));
    float3 col = signal.xxx;
    col = lerp(col, float3(0.95, 0.08, 0.04), (gridX + gridY) * grid_preview);
    OutputUAV[px] = float4(col, 1.0);
}
