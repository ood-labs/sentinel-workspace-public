RWTexture2D<float4> OutputUAV : register(u0);

static const float TAU = 6.28318530718;

float lineMask(float distanceValue, float widthValue, float pixelSize)
{
    return 1.0 - smoothstep(widthValue, widthValue + pixelSize * 1.5, distanceValue);
}

float segmentDistance(float2 p, float2 a, float2 b)
{
    float2 ab = b - a;
    float h = saturate(dot(p - a, ab) / max(dot(ab, ab), 0.000001));
    return length(p - (a + ab * h));
}

float cyclicDistance(float a, float b)
{
    return abs(frac(a - b + 0.5) - 0.5);
}

float hashCell(float2 p)
{
    return frac(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    uint2 pixel = tid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y)
        return;

    float2 uv = ((float2)pixel + 0.5) / max(_Resolution.xy, float2(1.0, 1.0));
    float aspect = _Resolution.x / max(_Resolution.y, 1.0);
    float2 p = (uv - 0.5) * float2(aspect, 1.0);
    float pixelSize = 1.0 / max(_Resolution.y, 1.0);

    float phase = frac(max(phase_driver, 0.0));
    float triangleSignal = saturate(triangle_driver);
    float orbitSignal = saturate(orbit_driver);
    float accentSignal = saturate(accent_driver);

    float3 background = float3(0.003, 0.0035, 0.0033);
    float3 whiteInk = saturate(ink_color);
    float3 warmInk = saturate(fault_color);
    float3 col = background;

    float fieldLeft = -aspect * 0.455;
    float fieldRight = aspect * 0.455;
    float fieldTop = -0.43;
    float fieldBottom = 0.43;
    bool insideField = p.x >= fieldLeft && p.x <= fieldRight
                    && p.y >= fieldTop && p.y <= fieldBottom;

    float faultX = sin(phase * TAU) * fault_travel;
    float side = p.x < faultX ? -1.0 : 1.0;
    float rowPitch = (fieldBottom - fieldTop) / max((float)layer_count, 1.0);
    float colPitch = (fieldRight - fieldLeft) / max((float)column_count, 1.0);

    float baseRow = (p.y - fieldTop) / max(rowPitch, pixelSize);
    float rowId = floor(baseRow);
    float rowNorm = (rowId + 0.5) / max((float)layer_count, 1.0);
    float rowWave = sin(TAU * (phase + rowNorm * 1.75));
    float rowShear = side * shear_amount * rowWave;

    float2 q = p;
    q.y += rowShear;
    q.x -= side * (orbitSignal - 0.5) * colPitch * 0.80;

    float rowCoord = (q.y - fieldTop) / max(rowPitch, pixelSize);
    float colCoord = (q.x - fieldLeft) / max(colPitch, pixelSize);
    float rowFrac = frac(rowCoord);
    float colFrac = frac(colCoord);
    float rowEdge = min(rowFrac, 1.0 - rowFrac) * rowPitch;
    float colEdge = min(colFrac, 1.0 - colFrac) * colPitch;

    float gapWidth = fault_gap * (0.72 + 0.45 * triangleSignal);
    float faultDistance = abs(p.x - faultX);
    float gapMask = smoothstep(gapWidth, gapWidth + pixelSize * 2.0, faultDistance);

    float horizontal = lineMask(rowEdge, line_width_px * pixelSize, pixelSize);
    float vertical = lineMask(colEdge, line_width_px * pixelSize * 0.72, pixelSize);
    float gridMask = max(horizontal, vertical * vertical_weight) * gapMask;
    gridMask *= insideField ? 1.0 : 0.0;

    float2 cellId = floor(float2(colCoord, rowCoord));
    float cellTone = hashCell(cellId);
    float plate = step(0.72, cellTone) * (1.0 - gridMask) * gapMask;
    plate *= insideField ? 1.0 : 0.0;
    plate *= 0.025 + 0.035 * orbitSignal;

    float warmGrid = 0.0;
    float activeRow = 1.0 - smoothstep(0.0, 0.060, cyclicDistance(rowNorm, phase));
    float activeColumnNorm = frac((floor(colCoord) + 0.5) / max((float)column_count, 1.0));
    float activeColumn = 1.0 - smoothstep(0.0, 0.050,
                                          cyclicDistance(activeColumnNorm, frac(phase + 0.25)));
    warmGrid = max(horizontal * activeRow, vertical * activeColumn);
    warmGrid *= gapMask * (insideField ? 1.0 : 0.0);
    warmGrid *= 0.32 + 0.68 * accentSignal;

    float bridgeWhite = 0.0;
    float bridgeWarm = 0.0;
    [loop]
    for (int i = 0; i < 64; ++i)
    {
        if (i >= layer_count)
            continue;

        float fi = ((float)i + 0.5) / max((float)layer_count, 1.0);
        float baseY = lerp(fieldTop, fieldBottom, fi);
        float wave = sin(TAU * (phase + fi * 1.75));
        float leftY = baseY - shear_amount * wave;
        float rightY = baseY + shear_amount * wave;
        float2 a = float2(faultX - gapWidth - bridge_length, leftY);
        float2 b = float2(faultX + gapWidth + bridge_length, rightY);

        float bridge = lineMask(segmentDistance(p, a, b), line_width_px * pixelSize * 1.05, pixelSize);
        float useBridge = step(0.78, hashCell(float2((float)i, 19.0)));
        bridge *= useBridge;

        float travel = 1.0 - smoothstep(0.0, 0.11, cyclicDistance(fi, frac(phase + 0.12)));
        bridgeWarm = max(bridgeWarm, bridge * travel * (0.45 + 0.55 * accentSignal));
        bridgeWhite = max(bridgeWhite, bridge * (1.0 - travel * 0.82));
    }

    float faultCore = lineMask(faultDistance, pixelSize * (0.65 + 1.25 * accentSignal), pixelSize);
    faultCore *= (p.y >= fieldTop && p.y <= fieldBottom) ? 1.0 : 0.0;

    float frameX = abs(abs(p.x) - aspect * 0.472);
    float frameY = abs(abs(p.y) - 0.468);
    float frame = max(lineMask(frameX, pixelSize * 0.55, pixelSize),
                      lineMask(frameY, pixelSize * 0.55, pixelSize));
    frame *= (abs(p.x) <= aspect * 0.472 && abs(p.y) <= 0.468) ? 1.0 : 0.0;

    float ticks = 0.0;
    [unroll]
    for (int t = 0; t < 12; ++t)
    {
        float ft = ((float)t + 0.5) / 12.0;
        float tx = lerp(fieldLeft, fieldRight, ft);
        float tickX = lineMask(abs(p.x - tx), pixelSize * 0.65, pixelSize);
        float tickBand = step(0.446, abs(p.y)) * step(abs(p.y), 0.465);
        ticks = max(ticks, tickX * tickBand);
    }

    col += whiteInk * (plate + frame * 0.26 + ticks * 0.50);
    col = lerp(col, whiteInk, saturate(gridMask * 0.72 + bridgeWhite));
    col = lerp(col, warmInk, saturate(warmGrid + bridgeWarm + faultCore * (0.20 + 0.80 * accentSignal)));

    float faultAura = (1.0 - smoothstep(gapWidth, gapWidth * 2.2, faultDistance))
                    * (insideField ? 1.0 : 0.0);
    col += warmInk * faultAura * (0.008 + 0.025 * accentSignal);
    OutputUAV[pixel] = float4(saturate(col), 1.0);
}
