RWTexture2D<float4> OutputUAV : register(u0);

struct ExchangeState
{
    float2 focus;
    float divergence;
    float cameraFollow;
    float printPressure;
    float marginCall;
    float activeDebt;
    float macroMass;
    float generation;
    float initialized;
    float owner;
    float pad;
};

StructuredBuffer<ExchangeState> DurableState : register(t1);

float4 pdStageRect(float2 resolution)
{
    float4 area = float4(0.018, 0.075, 0.755, 0.935);
    float2 areaPixels = (area.zw - area.xy) * resolution;
    float targetAspect = 16.0 / 9.0;
    float areaAspect = areaPixels.x / max(areaPixels.y, 1.0);
    float2 size = areaPixels;
    if (areaAspect > targetAspect)
        size.x = size.y * targetAspect;
    else
        size.y = size.x / targetAspect;
    float2 center = (area.xy + area.zw) * 0.5;
    float2 normalizedSize = size / max(resolution, float2(1.0, 1.0));
    return float4(center - normalizedSize * 0.5, center + normalizedSize * 0.5);
}

bool pdInside(float2 position, float4 rect)
{
    return all(position >= rect.xy) && all(position <= rect.zw);
}

float pdOwnerAt(float2 position, float4 stageRect)
{
    if (pdInside(position, float4(0.785, 0.180, 0.970, 0.545))) return 2.0;
    if (pdInside(position, float4(0.785, 0.610, 0.970, 0.685))) return 3.0;
    if (pdInside(position, float4(0.785, 0.755, 0.970, 0.845))) return 4.0;
    if (pdInside(position, stageRect)) return 1.0;
    return 0.0;
}

void pdApplyPosition(
    inout float4 spatial,
    inout float4 performance,
    float2 position,
    float owner,
    float4 stageRect)
{
    if (owner == 1.0)
    {
        float2 stageUv = saturate((position - stageRect.xy) / max(stageRect.zw - stageRect.xy, float2(1e-5, 1e-5)));
        spatial.xy = stageUv * 2.0 - 1.0;
    }
    else if (owner == 2.0)
    {
        float2 padUv = saturate((position - float2(0.785, 0.180)) / float2(0.185, 0.365));
        spatial.z = padUv.x;
        spatial.w = lerp(0.05, 0.85, 1.0 - padUv.y);
    }
    else if (owner == 3.0)
    {
        float rail = saturate((position.x - 0.785) / 0.185);
        performance.x = lerp(0.20, 2.20, rail);
    }
    else if (owner == 4.0)
    {
        performance.y = 1.0;
    }
}

[numthreads(1, 1, 1)]
void main(uint3 id : SV_DispatchThreadID)
{
    float4 spatial = _Tex0.Load(int3(0, 0, 0));
    float4 performance = _Tex0.Load(int3(1, 0, 0));
    float4 capture = _Tex0.Load(int3(2, 0, 0));

    if (performance.w < 0.5)
    {
        ExchangeState durable = DurableState[0];
        if (durable.initialized > 0.5)
        {
            spatial = float4(durable.focus, durable.divergence, durable.cameraFollow);
            performance = float4(durable.printPressure, durable.marginCall, max(1.0, durable.generation), 1.0);
        }
        else
        {
            spatial = float4(0.18, -0.10, 0.0, 0.34);
            performance = float4(1.0, 0.0, 1.0, 1.0);
        }
        capture = 0.0;
    }

    performance.y = max(0.0, performance.y - max(_DeltaTime, 0.004) * 2.2);
    float4 stageRect = pdStageRect(_Resolution.xy);
    bool changed = false;

    uint count = min(_ViewportEventCount, 64u);
    [loop]
    for (uint eventIndex = 0u; eventIndex < count; ++eventIndex)
    {
        ViewportEvent eventItem = _ViewportEvents[eventIndex];
        capture.y = (float)(eventItem.type * 10000u + eventItem.phase * 100u + eventItem.code);

        bool press = eventItem.type == 2u && eventItem.phase == 1u && eventItem.code == 0u;
        bool click = eventItem.type == 5u && eventItem.code == 1u;
        bool dragBegin = eventItem.type == 5u && eventItem.code == 3u && eventItem.phase == 5u;
        bool drag = eventItem.type == 5u && eventItem.code == 3u && eventItem.phase != 8u;
        bool dragEnd = eventItem.type == 5u && eventItem.code == 3u && eventItem.phase == 7u;
        bool dragCancel = eventItem.type == 5u && eventItem.code == 3u && eventItem.phase == 8u;

        if (press || click)
        {
            float owner = pdOwnerAt(eventItem.position, stageRect);
            if (owner > 0.0)
            {
                pdApplyPosition(spatial, performance, eventItem.position, owner, stageRect);
                changed = true;
            }
        }
        if (dragBegin)
            capture.x = pdOwnerAt(eventItem.position, stageRect);
        if (drag && capture.x > 0.0)
        {
            pdApplyPosition(spatial, performance, eventItem.position, capture.x, stageRect);
            changed = true;
        }
        if (dragEnd || dragCancel)
            capture.x = 0.0;
    }

    if (changed) performance.z += 1.0;
    if (performance.z > 100000.0) performance.z = 1.0;

    OutputUAV[uint2(0, 0)] = spatial;
    OutputUAV[uint2(1, 0)] = performance;
    OutputUAV[uint2(2, 0)] = capture;
}
