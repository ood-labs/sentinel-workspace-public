// The faithful part of this stage: geometry is only previewed. The texture
// leaving the node is a byte-exact load of the displaced input.

RWTexture2D<float4> OutputUAV : register(u0);

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    if (tid.x >= (uint)_Resolution.x || tid.y >= (uint)_Resolution.y) return;
    OutputUAV[tid.xy] = _Tex0.Load(int3(tid.xy, 0));
}
