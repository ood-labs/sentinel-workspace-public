RWTexture2D<float4> OutputUAV : register(u0);

float laneActive(float timer)
{
    float visibleTime = max(latest_outline_hold, 0.01);
    return step(0.0001, timer) * step(timer, visibleTime);
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;

    float2 uv = ((float2)pixel + 0.5) / _Resolution.xy;
    float4 timers = _Tex0.SampleLevel(PointSampler, uv, 0);
    float mask = max(max(laneActive(timers.x), laneActive(timers.y)),
                     max(laneActive(timers.z), laneActive(timers.w)));
    OutputUAV[pixel] = float4(mask, mask, 0.0, 1.0);
}
