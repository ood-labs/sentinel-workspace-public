// TP_Render / program.hlsl: clean output from the shared marched image.
//
// The Scope output reads the same image and camera. Keeping the march in one
// named buffer avoids paying for the renderer twice.
RWTexture2D<float4> OutputUAV : register(u0);

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    uint width, height;
    OutputUAV.GetDimensions(width, height);
    if (tid.x >= width || tid.y >= height) return;

    float2 uv = ((float2)tid.xy + 0.5) / float2(width, height);
    OutputUAV[tid.xy] = _Tex0.SampleLevel(PointSampler, uv, 0);
}
