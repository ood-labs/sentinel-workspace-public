RWTexture2D<float4> OutputUAV : register(u0);

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    uint width, height;
    OutputUAV.GetDimensions(width, height);
    if (tid.x >= width || tid.y >= height) return;

    uint sourceWidth, sourceHeight;
    _Tex0.GetDimensions(sourceWidth, sourceHeight);
    uint2 sourcePixel = min(
        uint2((float2(tid.xy) + 0.5) / float2(width, height)
              * float2(sourceWidth, sourceHeight)),
        uint2(sourceWidth - 1, sourceHeight - 1));
    OutputUAV[tid.xy] = _Tex0.Load(int3(sourcePixel, 0));
}
