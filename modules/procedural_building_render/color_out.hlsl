RWTexture2D<float4> OutputUAV : register(u0);

[numthreads(8,8,1)]
void main(uint3 id : SV_DispatchThreadID)
{
    uint2 px = id.xy;
    if (px.x >= (uint)_Resolution.x || px.y >= (uint)_Resolution.y) return;
    // The ray marcher stays linear RGBA16F. Publish a display-referred texture
    // for ordinary video consumers and StreamDiff: ACES-like tone map, then
    // encode to sRGB before the RGBA8 output quantization.
    float3 linearColor = max(_Tex0.Load(int3(px, 0)).rgb, 0.0) * 0.42;
    float3 mapped = (linearColor * (2.51 * linearColor + 0.03)) /
                    max(linearColor * (2.43 * linearColor + 0.59) + 0.14, 1e-5);
    float3 srgb = pow(saturate(mapped), 1.0 / 2.2);
    OutputUAV[px] = float4(srgb, 1.0);
}
