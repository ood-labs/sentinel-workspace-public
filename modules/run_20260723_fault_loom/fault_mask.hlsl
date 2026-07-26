RWTexture2D<float4> OutputUAV : register(u0);

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;

    float4 field = _Tex0.Load(int3(pixel, 0));
    float band = smoothstep(0.46 - band_width * 0.12, 0.51 - band_width * 0.06, field.r);
    float incision = smoothstep(0.72, 0.93, field.g);
    float mask = saturate(max(band, incision * mask_fault_weight));
    OutputUAV[pixel] = float4(mask.xxx, 1.0);
}
