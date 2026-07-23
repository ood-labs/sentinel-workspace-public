struct DeckState
{
    float energy;
    float warp;
    float topology;
    float relief;
    float memory;
    float archive;
    float glyphs;
    float signal_rate;
    float pulse_density;
    float quality;
    float focus_x;
    float focus_y;
    float active_pad;
    float generation;
    float initialized;
    float reserved;
};

float4 energyPadRect()    { return float4(0.752, 0.130, 0.968, 0.335); }
float4 structurePadRect() { return float4(0.752, 0.398, 0.968, 0.603); }
float4 memoryPadRect()    { return float4(0.752, 0.666, 0.968, 0.871); }

bool insideRect(float2 p, float4 r)
{
    return all(p >= r.xy) && all(p <= r.zw);
}

float2 padValue(float2 p, float4 r)
{
    float2 v = saturate((p - r.xy) / max(r.zw - r.xy, 1e-5));
    return float2(v.x, 1.0 - v.y);
}

float2 padHandle(float2 value, float4 r)
{
    return r.xy + float2(value.x, 1.0 - value.y) * (r.zw - r.xy);
}

float4 programStageRect(float2 resolution)
{
    float2 availableMin = float2(0.025, 0.082);
    float2 availableMax = float2(0.715, 0.925);
    float2 availablePx = (availableMax - availableMin) * resolution;
    float targetAspect = 16.0 / 9.0;
    float fittedWidth = min(availablePx.x, availablePx.y * targetAspect);
    float fittedHeight = fittedWidth / targetAspect;
    float2 fittedUv = float2(fittedWidth, fittedHeight) / resolution;
    float2 center = (availableMin + availableMax) * 0.5;
    return float4(center - fittedUv * 0.5, center + fittedUv * 0.5);
}
