RWStructuredBuffer<float4> OutputBuffer : register(u0);

float4 smPreviewRect(float2 resolution)
{
    float2 safeResolution = max(resolution, float2(1.0, 1.0));
    float railPx = min(clamp(safeResolution.x * 0.27, 180.0, 250.0), safeResolution.x * 0.38);
    float2 areaMin = float2(railPx + 22.0, 16.0);
    float2 areaMax = safeResolution - float2(16.0, 16.0);
    float side = max(min(areaMax.x - areaMin.x, areaMax.y - areaMin.y), 32.0);
    float2 centerPx = (areaMin + areaMax) * 0.5;
    float2 minPx = centerPx - side * 0.5;
    float2 maxPx = centerPx + side * 0.5;
    return float4(minPx / safeResolution, maxPx / safeResolution);
}

[numthreads(1, 1, 1)]
void main(uint3 id : SV_DispatchThreadID)
{
    float4 state = OutputBuffer[0];
    float4 previous = OutputBuffer[1];
    if (state.z <= 0.0 || !isfinite(state.z)) {
        state = float4(center, size, 0.0);
        previous = float4(center, size, max(_Time, 0.0001));
    }

    bool dragActive = previous.w < 0.0;
    float previousTime = abs(previous.w);
    float deltaTime = clamp(_Time - previousTime, 0.0, 0.25);
    // motion_speed is signed cycles per second: zero stops, negative reverses.
    state.w = frac(state.w + motion_speed * deltaTime);

    if (any(abs(center - previous.xy) > 0.00001)) state.xy = center;
    if (abs(size - previous.z) > 0.00001) state.z = size;

    float4 preview = smPreviewRect(_Resolution.xy);
    uint count = min(_ViewportEventCount, 64u);
    [loop] for (uint i = 0u; i < count; ++i) {
        ViewportEvent e = _ViewportEvents[i];
        if ((e.flags & VIEWPORT_EVENT_FLAG_HOST_CONSUMED) != 0u) continue;

        bool insidePreview = all(e.position >= preview.xy) && all(e.position <= preview.zw);
        if (e.type == 3u && insidePreview) {
            float notches = abs(e.value) > 0.001 ? e.value : e.delta.y;
            state.z = clamp(state.z * pow(1.12, notches), 0.08, 0.48);
        }

        bool click = e.type == 5u && e.code == 1u && e.phase == 7u;
        bool drag = e.type == 5u && e.code == 3u;
        if (click && insidePreview)
            state.xy = saturate((e.position - preview.xy) / max(preview.zw - preview.xy, 0.0001));

        if (drag && e.phase == 5u && insidePreview) dragActive = true;
        if (drag && dragActive && (e.phase == 5u || e.phase == 6u || e.phase == 7u))
            state.xy = saturate((e.position - preview.xy) / max(preview.zw - preview.xy, 0.0001));
        if (drag && (e.phase == 7u || e.phase == 8u)) dragActive = false;
    }

    previous.xyz = float3(center, size);
    previous.w = (dragActive ? -1.0 : 1.0) * max(_Time, 0.0001);
    OutputBuffer[0] = state;
    OutputBuffer[1] = previous;
}
