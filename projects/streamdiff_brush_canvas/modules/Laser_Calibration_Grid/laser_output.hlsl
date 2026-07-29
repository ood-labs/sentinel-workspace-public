// Explicit LaserViz calibration masks. No RGB edge extraction.

RWTexture2D<float4> OutputUAV : register(u0);

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;

    float2 uv = ((float2)pixel + 0.5) / _Resolution.xy;
    float3 masks = _Tex0.SampleLevel(PointSampler, uv, 0).rgb;

    float mark = masks.r;
    if (laser_output_mode == 1)
        mark = masks.g;
    else if (laser_output_mode >= 2)
        mark = saturate(masks.r + masks.g);

    // Physical laser output is deliberately hard binary.
    mark = step(0.5, mark);
    OutputUAV[pixel] = float4(mark.xxx, 1.0);
}
