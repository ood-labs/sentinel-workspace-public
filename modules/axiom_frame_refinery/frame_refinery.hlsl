RWTexture2D<float4> OutputUAV : register(u0);

float refineryRect(float2 uv, float2 minimumCorner, float2 maximumCorner, float feather)
{
    float2 insideDistance = min(uv - minimumCorner, maximumCorner - uv);
    return smoothstep(-feather, feather, min(insideDistance.x, insideDistance.y));
}

float refinerySegment(float2 p, float2 a, float2 b)
{
    float2 pa = p - a;
    float2 ba = b - a;
    float h = saturate(dot(pa, ba) / max(dot(ba, ba), 1e-6));
    return length(pa - ba * h);
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    if (tid.x >= (uint)_Resolution.x || tid.y >= (uint)_Resolution.y) return;

    float2 uv = ((float2)tid.xy + 0.5) / _Resolution.xy;
    float3 color = _Tex0.SampleLevel(LinearSampler, uv, 0).rgb;
    float pixelLine = 1.0 / max(_Resolution.y, 1.0);
    float feather = 5.0 / max(_Resolution.y, 1.0);

    float leftQuiet = 1.0 - smoothstep(left_quiet_width,
                                       left_quiet_width + feather, uv.x);
    float rightQuiet = smoothstep(1.0 - right_quiet_width - feather,
                                  1.0 - right_quiet_width, uv.x);
    float bottomQuiet = smoothstep(1.0 - bottom_quiet_height - feather,
                                   1.0 - bottom_quiet_height, uv.y);
    float topQuiet = 1.0 - smoothstep(top_quiet_height,
                                     top_quiet_height + feather, uv.y);

    float telemetryPreserve = refineryRect(uv,
                                           float2(0.025, 0.055),
                                           float2(0.148, 0.255),
                                           feather * 1.5);
    float perimeterCleanup = max(max(leftQuiet, rightQuiet),
                                 max(bottomQuiet, topQuiet));
    perimeterCleanup *= 1.0 - telemetryPreserve * 0.96;
    color *= 1.0 - perimeterCleanup * cleanup_strength;

    float leftDatum = smoothstep(pixelLine * 1.35, pixelLine * 0.12,
                                 abs(uv.x - left_quiet_width))
                    * step(top_quiet_height, uv.y)
                    * step(uv.y, 1.0 - bottom_quiet_height);
    color = max(color, paper_color * leftDatum * datum_gain * 0.32);

    float inset = frame_inset;
    float horizontalTop = smoothstep(pixelLine * 1.25, pixelLine * 0.12,
                                     abs(uv.y - inset))
                        * step(inset, uv.x) * step(uv.x, 1.0 - inset);
    float horizontalBottom = smoothstep(pixelLine * 1.25, pixelLine * 0.12,
                                        abs(uv.y - (1.0 - inset)))
                           * step(inset, uv.x) * step(uv.x, 1.0 - inset);
    float verticalLeft = smoothstep(pixelLine * 1.25, pixelLine * 0.12,
                                    abs(uv.x - inset))
                       * step(inset, uv.y) * step(uv.y, 1.0 - inset);
    float verticalRight = smoothstep(pixelLine * 1.25, pixelLine * 0.12,
                                     abs(uv.x - (1.0 - inset)))
                        * step(inset, uv.y) * step(uv.y, 1.0 - inset);

    float frameInk = 0.0;
    if (frame_mode == 0)
    {
        frameInk = horizontalTop * 0.64 + horizontalBottom * 0.28
                 + verticalLeft * 0.46 + verticalRight * 0.24;
    }
    else if (frame_mode == 1)
    {
        float topGate = step(uv.x, 0.78);
        float bottomGate = step(0.24, uv.x) * step(uv.x, 0.88);
        frameInk = horizontalTop * topGate * 0.72
                 + horizontalBottom * bottomGate * 0.34
                 + verticalLeft * 0.66 + verticalRight * 0.18;
    }
    else
    {
        float innerInset = inset + 0.010;
        float innerTop = smoothstep(pixelLine * 1.15, pixelLine * 0.12,
                                    abs(uv.y - innerInset))
                       * step(innerInset, uv.x) * step(uv.x, 1.0 - innerInset);
        float innerBottom = smoothstep(pixelLine * 1.15, pixelLine * 0.12,
                                       abs(uv.y - (1.0 - innerInset)))
                          * step(innerInset, uv.x) * step(uv.x, 1.0 - innerInset);
        float innerLeft = smoothstep(pixelLine * 1.15, pixelLine * 0.12,
                                     abs(uv.x - innerInset))
                        * step(innerInset, uv.y) * step(uv.y, 1.0 - innerInset);
        float innerRight = smoothstep(pixelLine * 1.15, pixelLine * 0.12,
                                      abs(uv.x - (1.0 - innerInset)))
                         * step(innerInset, uv.y) * step(uv.y, 1.0 - innerInset);
        frameInk = (horizontalTop + horizontalBottom
                  + verticalLeft + verticalRight) * 0.42
                 + (innerTop + innerBottom + innerLeft + innerRight) * 0.24;
    }

    float cornerLengthX = 0.038;
    float cornerLengthY = 0.052;
    float2 absoluteFrameDelta = abs(uv - 0.5);
    float horizontalCornerReach = step(0.5 - inset - cornerLengthX,
                                       absoluteFrameDelta.x);
    float verticalCornerReach = step(0.5 - inset - cornerLengthY,
                                     absoluteFrameDelta.y);
    float cornerBrackets = horizontalTop * horizontalCornerReach
                         + horizontalBottom * horizontalCornerReach
                         + verticalLeft * verticalCornerReach
                         + verticalRight * verticalCornerReach;
    frameInk = max(frameInk, cornerBrackets * 0.76);

    float tickInk = 0.0;
    int safeTickCount = max(tick_count, 5);
    [loop]
    for (int tickIndex = 0; tickIndex < 24; ++tickIndex)
    {
        if (tickIndex >= safeTickCount) break;
        float tickT = ((float)tickIndex + 0.5) / (float)safeTickCount;
        float tickX = lerp(inset + 0.06, 1.0 - inset - 0.06, tickT);
        float tickLength = (tickIndex % 4 == 0) ? 0.012 : 0.006;
        float topTick = smoothstep(pixelLine * 1.1, pixelLine * 0.10,
                                   abs(uv.x - tickX))
                      * step(inset, uv.y) * step(uv.y, inset + tickLength);
        float bottomTick = smoothstep(pixelLine * 1.1, pixelLine * 0.10,
                                      abs(uv.x - tickX))
                         * step(1.0 - inset - tickLength, uv.y)
                         * step(uv.y, 1.0 - inset);
        tickInk = max(tickInk, max(topTick, bottomTick));
    }

    float verticalTickInk = 0.0;
    [unroll]
    for (int verticalIndex = 0; verticalIndex < 7; ++verticalIndex)
    {
        float tickY = lerp(inset + 0.08, 1.0 - inset - 0.08,
                           ((float)verticalIndex + 0.5) / 7.0);
        float tickLength = (verticalIndex == 3) ? 0.014 : 0.008;
        float leftTick = smoothstep(pixelLine * 1.1, pixelLine * 0.10,
                                    abs(uv.y - tickY))
                       * step(inset, uv.x) * step(uv.x, inset + tickLength);
        float rightTick = smoothstep(pixelLine * 1.1, pixelLine * 0.10,
                                     abs(uv.y - tickY))
                        * step(1.0 - inset - tickLength, uv.x)
                        * step(uv.x, 1.0 - inset);
        verticalTickInk = max(verticalTickInk, max(leftTick, rightTick));
    }

    float paperInk = saturate(frameInk * frame_gain
                            + tickInk * tick_gain
                            + verticalTickInk * tick_gain * 0.72);
    color = max(color, paper_color * paperInk);

    float activityPosition = lerp(inset + 0.06, 1.0 - inset - 0.06,
                                  frac(frame_phase));
    float activeNotch = smoothstep(pixelLine * 1.25, pixelLine * 0.10,
                                   abs(uv.x - activityPosition))
                      * step(inset, uv.y)
                      * step(uv.y, inset + 0.014);
    color = lerp(color, accent_color,
                 activeNotch * saturate(activity) * accent_gain);

    OutputUAV[tid.xy] = float4(saturate(color), 1.0);
}
