RWTexture2D<float4> OutputUAV : register(u0);

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    uint width;
    uint height;
    _Tex0.GetDimensions(width, height);
    if (pixel.x >= width || pixel.y >= height) return;

    float2 uv = ((float2)pixel + 0.5) / float2((float)width, (float)height);
    float3 specimen = _Tex0.SampleLevel(LinearSampler, uv, 0).rgb;
    float shutter = saturate(_Tex1.SampleLevel(LinearSampler, uv, 0).r);

    // The shutter is an opaque layer placed over the image. It does not alter
    // or classify the source signal underneath.
    float3 col = specimen * (1.0 - shutter * cut_depth);
    OutputUAV[pixel] = float4(saturate(col), 1.0);
}
