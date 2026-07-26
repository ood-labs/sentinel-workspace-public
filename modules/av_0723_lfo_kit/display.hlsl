struct LfoState
{
    float phase;
    float sine;
    float triangle_value;
    float pulse;
    float ramp;
    float orbit_x;
    float accent;
    float last_scrub;
};

StructuredBuffer<LfoState> LfoValues : register(t0);
RWTexture2D<float4> OutputUAV : register(u0);

static const float TAU = 6.28318530718;

float segmentDistance(float2 p, float2 a, float2 b)
{
    float2 ab = b - a;
    float h = saturate(dot(p - a, ab) / max(dot(ab, ab), 0.000001));
    return length(p - (a + ab * h));
}

float stroke(float distanceValue, float widthValue, float pixelSize)
{
    return 1.0 - smoothstep(widthValue, widthValue + pixelSize * 1.5, distanceValue);
}

float boxOutline(float2 p, float4 box, float widthValue, float pixelSize)
{
    float2 center = (box.xy + box.zw) * 0.5;
    float2 extent = (box.zw - box.xy) * 0.5;
    float2 d = abs(p - center) - extent;
    float outer = max(d.x, d.y);
    float inner = max(abs(p.x - center.x) - max(extent.x - widthValue, 0.0),
                      abs(p.y - center.y) - max(extent.y - widthValue, 0.0));
    return (1.0 - smoothstep(0.0, pixelSize * 1.5, outer))
         * smoothstep(-pixelSize * 1.5, 0.0, inner);
}

float ring(float2 p, float2 center, float radius, float widthValue, float pixelSize)
{
    return stroke(abs(length(p - center) - radius), widthValue, pixelSize);
}

float waveValue(int kind, float q)
{
    q = frac(q);
    if (kind == 0)
        return 0.5 + 0.5 * sin(q * TAU);
    if (kind == 1)
        return 1.0 - abs(q * 2.0 - 1.0);
    if (kind == 2)
        return q < saturate(pulse_width) ? 1.0 : 0.0;
    return pow(saturate(0.5 + 0.5 * cos(q * TAU)), max(accent_sharpness, 1.0));
}

float currentValue(LfoState state, int kind)
{
    if (kind == 0) return state.sine;
    if (kind == 1) return state.triangle_value;
    if (kind == 2) return state.pulse;
    return state.accent;
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    uint2 pixel = tid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y)
        return;

    float2 uv = ((float2)pixel + 0.5) / max(_Resolution.xy, float2(1.0, 1.0));
    float aspect = _Resolution.x / max(_Resolution.y, 1.0);
    float2 p = float2(uv.x * aspect, uv.y);
    float pixelSize = 1.0 / max(_Resolution.y, 1.0);

    LfoState state = LfoValues[0];

    float3 black = float3(0.004, 0.005, 0.005);
    float3 dim = float3(0.10, 0.11, 0.105);
    float3 mid = float3(0.34, 0.36, 0.34);
    float3 white = float3(0.90, 0.92, 0.88);
    float3 warm = float3(1.00, 0.25, 0.055);
    float3 col = black;

    float margin = 0.034;
    float4 frame = float4(margin * aspect, margin, aspect - margin * aspect, 1.0 - margin);
    col = lerp(col, mid, boxOutline(p, frame, pixelSize * 1.25, pixelSize));

    float2 orbitCenter = float2(aspect * 0.185, 0.41);
    float orbitRadius = min(aspect * 0.105, 0.19);
    col = lerp(col, dim, ring(p, orbitCenter, orbitRadius, pixelSize, pixelSize));
    col = lerp(col, mid, ring(p, orbitCenter, orbitRadius * 0.72, pixelSize * 0.75, pixelSize));

    float2 orbitPoint = orbitCenter + float2(cos(state.phase * TAU), sin(state.phase * TAU)) * orbitRadius;
    col = lerp(col, white, stroke(segmentDistance(p, orbitCenter, orbitPoint), pixelSize * 0.65, pixelSize));
    col = lerp(col, warm, 1.0 - smoothstep(pixelSize * 4.0, pixelSize * 7.0, length(p - orbitPoint)));

    for (int tick = 0; tick < 16; ++tick)
    {
        float a = (float)tick / 16.0 * TAU;
        float2 dir = float2(cos(a), sin(a));
        float2 ta = orbitCenter + dir * (orbitRadius * 1.04);
        float2 tb = orbitCenter + dir * (orbitRadius * (tick % 4 == 0 ? 1.14 : 1.09));
        col = lerp(col, tick % 4 == 0 ? white : mid,
                   stroke(segmentDistance(p, ta, tb), pixelSize * 0.55, pixelSize));
    }

    float graphLeft = aspect * 0.34;
    float graphRight = aspect * 0.955;
    float graphTop = 0.09;
    float laneHeight = 0.165;
    float laneGap = 0.018;

    for (int lane = 0; lane < 4; ++lane)
    {
        float y0 = graphTop + lane * (laneHeight + laneGap);
        float y1 = y0 + laneHeight;
        float4 laneBox = float4(graphLeft, y0, graphRight, y1);
        col = lerp(col, dim, boxOutline(p, laneBox, pixelSize * 0.8, pixelSize));

        for (int grid = 1; grid < 4; ++grid)
        {
            float gx = lerp(graphLeft, graphRight, (float)grid / 4.0);
            col = lerp(col, dim, stroke(abs(p.x - gx), pixelSize * 0.35, pixelSize) * 0.6);
        }

        float q = saturate((p.x - graphLeft) / max(graphRight - graphLeft, pixelSize));
        float w = waveValue(lane, q);
        float waveY = lerp(y1 - laneHeight * 0.16, y0 + laneHeight * 0.16, w);
        float trace = stroke(abs(p.y - waveY), pixelSize * 0.95, pixelSize);
        bool inLane = p.x >= graphLeft && p.x <= graphRight && p.y >= y0 && p.y <= y1;
        col = lerp(col, lane == 3 ? warm : white, trace * (inLane ? 1.0 : 0.0));

        float cursorX = lerp(graphLeft, graphRight, state.phase);
        float activeY = lerp(y1 - laneHeight * 0.16, y0 + laneHeight * 0.16, currentValue(state, lane));
        float cursor = stroke(abs(p.x - cursorX), pixelSize * 0.45, pixelSize) * (inLane ? 1.0 : 0.0);
        col = lerp(col, warm, cursor * 0.75);
        col = lerp(col, warm, 1.0 - smoothstep(pixelSize * 3.0, pixelSize * 5.0,
                                               length(p - float2(cursorX, activeY))));
    }

    float transportY0 = 0.865;
    float transportY1 = 0.952;
    float playX0 = aspect * 0.045;
    float playX1 = aspect * 0.125;
    float resetX0 = aspect * 0.135;
    float resetX1 = aspect * 0.215;
    float scrubX0 = aspect * 0.245;
    float scrubX1 = aspect * 0.945;
    float4 playBox = float4(playX0, transportY0, playX1, transportY1);
    float4 resetBox = float4(resetX0, transportY0, resetX1, transportY1);
    float4 scrubBox = float4(scrubX0, transportY0, scrubX1, transportY1);

    col = lerp(col, transport_run != 0 ? white : mid,
               boxOutline(p, playBox, pixelSize, pixelSize));
    col = lerp(col, mid, boxOutline(p, resetBox, pixelSize, pixelSize));
    col = lerp(col, mid, boxOutline(p, scrubBox, pixelSize, pixelSize));

    float2 playCenter = float2((playX0 + playX1) * 0.5, (transportY0 + transportY1) * 0.5);
    if (transport_run != 0)
    {
        float2 a = playCenter + float2(-0.012, -0.020);
        float2 b = playCenter + float2(-0.012, 0.020);
        float2 c = playCenter + float2(0.020, 0.0);
        float edge = min(segmentDistance(p, a, b),
                         min(segmentDistance(p, b, c), segmentDistance(p, c, a)));
        col = lerp(col, warm, stroke(edge, pixelSize, pixelSize));
    }
    else
    {
        float bars = min(abs(p.x - (playCenter.x - 0.010)), abs(p.x - (playCenter.x + 0.010)));
        float inside = p.y > playCenter.y - 0.020 && p.y < playCenter.y + 0.020 ? 1.0 : 0.0;
        col = lerp(col, warm, stroke(bars, pixelSize * 2.0, pixelSize) * inside);
    }

    float2 resetCenter = float2((resetX0 + resetX1) * 0.5, (transportY0 + transportY1) * 0.5);
    col = lerp(col, white, ring(p, resetCenter, 0.020, pixelSize, pixelSize));
    col = lerp(col, warm, 1.0 - smoothstep(pixelSize * 2.0, pixelSize * 4.0,
                                           length(p - resetCenter)));

    float scrubY = (transportY0 + transportY1) * 0.5;
    col = lerp(col, mid, stroke(abs(p.y - scrubY), pixelSize * 0.6, pixelSize)
                               * (p.x >= scrubX0 && p.x <= scrubX1 ? 1.0 : 0.0));
    float phaseX = lerp(scrubX0, scrubX1, state.phase);
    col = lerp(col, warm, stroke(abs(p.x - phaseX), pixelSize * 1.3, pixelSize)
                                * (p.y >= transportY0 && p.y <= transportY1 ? 1.0 : 0.0));

    float runPulse = transport_run != 0 ? state.accent : 0.0;
    col += warm * runPulse * 0.045;
    OutputUAV[pixel] = float4(saturate(col), 1.0);
}
