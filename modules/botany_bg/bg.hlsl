// botany_bg — flat violet ground plate for the bouquet scene (opaque).
RWTexture2D<float4> OutputUAV : register(u0);

[numthreads(8,8,1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 px = DTid.xy;
    if (px.x >= (uint)_Resolution.x || px.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)px + 0.5) / _Resolution.xy;
    float3 violet = float3(0.42, 0.28, 0.75);
    float vig = 1.0 - vignette * 0.25 * length(uv - 0.5);
    OutputUAV[px] = float4(violet * vig, 1.0);
}
