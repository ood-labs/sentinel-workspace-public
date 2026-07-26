RWTexture2D<float4> OutputUAV : register(u0);

[numthreads(8, 8, 1)]
void main(uint3 id : SV_DispatchThreadID)
{
    if (id.x >= (uint)_Resolution.x || id.y >= (uint)_Resolution.y) return;

    float2 uv = ((float2)id.xy + 0.5) / _Resolution.xy;
    uint srcW;
    uint srcH;
    _Tex0.GetDimensions(srcW, srcH);
    float2 px = 1.0 / max(float2(srcW, srcH), 1.0);

    float3 c = _Tex0.SampleLevel(LinearSampler, uv, 0).rgb;
    float3 n = _Tex0.SampleLevel(LinearSampler, uv + float2(0.0, -px.y), 0).rgb;
    float3 s = _Tex0.SampleLevel(LinearSampler, uv + float2(0.0,  px.y), 0).rgb;
    float3 e = _Tex0.SampleLevel(LinearSampler, uv + float2( px.x, 0.0), 0).rgb;
    float3 w = _Tex0.SampleLevel(LinearSampler, uv + float2(-px.x, 0.0), 0).rgb;

    float3 localMean = (n + s + e + w) * 0.25;
    float3 detail = c - localMean;
    float3 sharpened = c + detail * edge_focus;
    float luma = dot(sharpened, float3(0.2126, 0.7152, 0.0722));
    float shaped = pow(saturate(luma * luma_gain), luma_gamma);
    float3 chroma = sharpened / max(luma, 0.02);
    float3 outColor = lerp(shaped.xxx, chroma * shaped, color_keep);

    float2 q = abs(frac(uv * float2(16.0, 9.0)) - 0.5);
    float guide = smoothstep(0.495, 0.475, max(q.x, q.y)) * show_analysis_grid;
    outColor += guide * float3(0.02, 0.06, 0.08);

    OutputUAV[id.xy] = float4(saturate(outColor), 1.0);
}
