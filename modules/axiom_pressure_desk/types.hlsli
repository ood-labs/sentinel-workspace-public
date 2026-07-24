struct GestureField
{
    float2 position;
    float2 direction;
    float radius;
    float strength;
    float mode;
    float active;
};

struct PressureStats
{
    float active_fields;
    float current_mode;
    float current_radius;
    float gesture_energy;
};

float4 pressureStageRect(float2 resolution)
{
    float4 available = float4(0.025, 0.105, 0.735, 0.895);
    float2 availablePixels = (available.zw - available.xy) * resolution;
    float availableAspect = availablePixels.x / max(availablePixels.y, 1.0);
    float programAspect = 16.0 / 9.0;
    float2 size = available.zw - available.xy;
    if (availableAspect > programAspect)
    {
        float fittedWidth = size.y * resolution.y * programAspect / resolution.x;
        float pad = (size.x - fittedWidth) * 0.5;
        available.x += pad;
        available.z -= pad;
    }
    else
    {
        float fittedHeight = size.x * resolution.x / programAspect / resolution.y;
        float pad = (size.y - fittedHeight) * 0.5;
        available.y += pad;
        available.w -= pad;
    }
    return available;
}

bool insidePressureStage(float2 p, float4 stage)
{
    return all(p >= stage.xy) && all(p <= stage.zw);
}

float2 panelToStage(float2 p, float4 stage)
{
    return saturate((p - stage.xy) / max(stage.zw - stage.xy, 1e-5));
}

float2 stageToPanel(float2 p, float4 stage)
{
    return lerp(stage.xy, stage.zw, p);
}
