RWTexture2D<float4> OutputUAV : register(u0);

[numthreads(8,8,1)]
void main(uint3 id : SV_DispatchThreadID)
{
    uint2 px = id.xy;
    if (px.x >= (uint)_Resolution.x || px.y >= (uint)_Resolution.y) return;
    float depth = saturate(_Tex0.Load(int3(px, 0)).a);
    OutputUAV[px] = float4(depth, depth, depth, 1.0);
}
