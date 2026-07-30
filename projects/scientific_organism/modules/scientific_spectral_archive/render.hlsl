RWTexture2D<float4> OutputUAV : register(u0);

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    if (tid.x >= (uint)_Resolution.x || tid.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)tid.xy + 0.5) / _Resolution.xy;
    float3 current = _Tex0.SampleLevel(LinearSampler, uv, 0).rgb;
    float3 archive = _Tex1.SampleLevel(LinearSampler, uv, 0).rgb;
    float high = archive.r;
    float mid = archive.g;
    float low = archive.b;
    float spectralContour = 1.0 - smoothstep(0.025, 0.10, abs(frac((high + mid * 0.5) * spectral_bands) - 0.5));
    float3 mapped = high_ink * high + mid_ink * mid + low_ink * low;
    mapped += contour_ink * spectralContour * max(high, mid) * contour_mix;
    float amberOriginal = saturate(current.r - max(current.g, current.b) * 1.55);
    float3 col = current + mapped * archive_mix;
    col = lerp(col, max(col, current), amberOriginal);
    OutputUAV[tid.xy] = float4(saturate(col), 1.0);
}
