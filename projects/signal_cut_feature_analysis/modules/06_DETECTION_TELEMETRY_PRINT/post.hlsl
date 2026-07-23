RWTexture2D<float4> OutputUAV : register(u0);

static const float2 ANALYSIS_SIZE = float2(480.0, 270.0);
static const uint NETWORK_POINTS = 12u;
static const uint LABELED_POINTS = 4u;

float sdSegment(float2 p, float2 a, float2 b)
{
    float2 pa = p - a;
    float2 ba = b - a;
    float h = saturate(dot(pa, ba) / max(dot(ba, ba), 1e-7));
    return length(pa - ba * h);
}

float boxMask(float2 p, float2 lo, float2 hi)
{
    return step(lo.x, p.x) * step(lo.y, p.y) * step(p.x, hi.x) * step(p.y, hi.y);
}

uint digitBits(int d)
{
    if (d == 0) return 0x3Fu;
    if (d == 1) return 0x06u;
    if (d == 2) return 0x5Bu;
    if (d == 3) return 0x4Fu;
    if (d == 4) return 0x66u;
    if (d == 5) return 0x6Du;
    if (d == 6) return 0x7Du;
    if (d == 7) return 0x07u;
    if (d == 8) return 0x7Fu;
    return 0x6Fu;
}

float digitGlyph(float2 p, int d, float width)
{
    uint bits = digitBits(clamp(d, 0, 9));
    float ink = 0.0;
    if ((bits & 0x01u) != 0u) ink = max(ink, smoothstep(width, width * 0.28, sdSegment(p, float2(1, 1), float2(7, 1))));
    if ((bits & 0x02u) != 0u) ink = max(ink, smoothstep(width, width * 0.28, sdSegment(p, float2(7, 1), float2(7, 7))));
    if ((bits & 0x04u) != 0u) ink = max(ink, smoothstep(width, width * 0.28, sdSegment(p, float2(7, 7), float2(7, 13))));
    if ((bits & 0x08u) != 0u) ink = max(ink, smoothstep(width, width * 0.28, sdSegment(p, float2(1, 13), float2(7, 13))));
    if ((bits & 0x10u) != 0u) ink = max(ink, smoothstep(width, width * 0.28, sdSegment(p, float2(1, 7), float2(1, 13))));
    if ((bits & 0x20u) != 0u) ink = max(ink, smoothstep(width, width * 0.28, sdSegment(p, float2(1, 1), float2(1, 7))));
    if ((bits & 0x40u) != 0u) ink = max(ink, smoothstep(width, width * 0.28, sdSegment(p, float2(1, 7), float2(7, 7))));
    return ink;
}

float letterGlyph(float2 p, int letter, float width)
{
    float ink = 0.0;
    if (letter == 0) // R / response
    {
        ink = max(ink, smoothstep(width, width * 0.28, sdSegment(p, float2(1, 13), float2(1, 1))));
        ink = max(ink, smoothstep(width, width * 0.28, sdSegment(p, float2(1, 1), float2(6, 1))));
        ink = max(ink, smoothstep(width, width * 0.28, sdSegment(p, float2(6, 1), float2(6, 7))));
        ink = max(ink, smoothstep(width, width * 0.28, sdSegment(p, float2(1, 7), float2(6, 7))));
        ink = max(ink, smoothstep(width, width * 0.28, sdSegment(p, float2(4, 7), float2(7, 13))));
    }
    else if (letter == 1) // X
    {
        ink = max(ink, smoothstep(width, width * 0.28, sdSegment(p, float2(1, 1), float2(7, 13))));
        ink = max(ink, smoothstep(width, width * 0.28, sdSegment(p, float2(7, 1), float2(1, 13))));
    }
    else // Y
    {
        ink = max(ink, smoothstep(width, width * 0.28, sdSegment(p, float2(1, 1), float2(4, 7))));
        ink = max(ink, smoothstep(width, width * 0.28, sdSegment(p, float2(7, 1), float2(4, 7))));
        ink = max(ink, smoothstep(width, width * 0.28, sdSegment(p, float2(4, 7), float2(4, 13))));
    }
    return ink;
}

float valueRow(float2 pixel, float2 origin, int letter, int value, float scale)
{
    float2 p = (pixel - origin) / scale;
    float ink = letterGlyph(p, letter, 0.68 / scale);
    int divisor = 100;
    [unroll]
    for (int i = 0; i < 3; ++i)
    {
        int d = (value / divisor) % 10;
        ink = max(ink, digitGlyph(p - float2(11.0 + i * 9.0, 0.0), d, 0.68 / scale));
        divisor /= 10;
    }
    return ink;
}

float asciiGlyph(float2 cell, float lum)
{
    float2 p = cell - 0.5;
    float px = 0.070;
    float dotGlyph = smoothstep(0.105, 0.035, length(p - float2(0.0, 0.27)));
    float colonGlyph = max(
        smoothstep(0.085, 0.025, length(p - float2(0.0, -0.18))),
        smoothstep(0.085, 0.025, length(p - float2(0.0, 0.22)))
    );
    float plusGlyph = max(
        smoothstep(px, px * 0.28, abs(p.x)) * step(abs(p.y), 0.33),
        smoothstep(px, px * 0.28, abs(p.y)) * step(abs(p.x), 0.33)
    );
    float hashGlyph = max(
        max(
            smoothstep(px, px * 0.28, abs(p.x - 0.15)),
            smoothstep(px, px * 0.28, abs(p.x + 0.15))
        ) * step(abs(p.y), 0.40),
        max(
            smoothstep(px, px * 0.28, abs(p.y - 0.14)),
            smoothstep(px, px * 0.28, abs(p.y + 0.14))
        ) * step(abs(p.x), 0.39)
    );
    float atRing = smoothstep(0.055, 0.015, abs(length(p) - 0.31));
    float atCore = smoothstep(px, px * 0.28, abs(p.x - 0.08)) * step(abs(p.y + 0.01), 0.20);
    float atBar = smoothstep(px, px * 0.28, abs(p.y - 0.18)) * step(abs(p.x - 0.16), 0.22);
    float atGlyph = max(atRing, max(atCore, atBar));

    if (lum < 0.17) return 0.0;
    if (lum < 0.31) return dotGlyph;
    if (lum < 0.47) return colonGlyph;
    if (lum < 0.64) return plusGlyph;
    if (lum < 0.82) return hashGlyph;
    return atGlyph;
}

[numthreads(8, 8, 1)]
void main(uint3 id : SV_DispatchThreadID)
{
    if (id.x >= (uint)_Resolution.x || id.y >= (uint)_Resolution.y) return;

    float2 pixel = (float2)id.xy + 0.5;
    float2 uv = pixel / _Resolution.xy;
    float aspect = _Resolution.x / _Resolution.y;
    float3 source = _Tex0.SampleLevel(LinearSampler, uv, 0).rgb;
    float sourceLum = dot(source, float3(0.2126, 0.7152, 0.0722));

    float levels = max(print_levels, 2.0);
    float quantized = floor(saturate(sourceLum) * levels + 0.5) / levels;
    float chroma = smoothstep(0.12, 0.55, max(source.r, max(source.g, source.b)) - min(source.r, min(source.g, source.b)));
    float3 col = lerp(quantized.xxx, source, chroma * 0.72);

    uint count = min(_Data2_Count, NETWORK_POINTS);
    uint selected = 0u;
    float strongestResponse = -1.0;
    [loop]
    for (uint i = 0u; i < NETWORK_POINTS; ++i)
    {
        if (i >= count) break;
        if (_Data2[i].response > strongestResponse)
        {
            strongestResponse = _Data2[i].response;
            selected = i;
        }
    }

    float connectionLimit = lerp(0.085, 0.34, network_tension);
    float networkInk = 0.0;
    [loop]
    for (uint a = 0u; a < NETWORK_POINTS; ++a)
    {
        if (a >= count) break;
        float2 ap = float2(_Data2[a].x, _Data2[a].y) / ANALYSIS_SIZE;
        float ar = saturate(_Data2[a].response / 4.5);
        [loop]
        for (uint b = a + 1u; b < NETWORK_POINTS; ++b)
        {
            if (b >= count) break;
            float2 bp = float2(_Data2[b].x, _Data2[b].y) / ANALYSIS_SIZE;
            float br = saturate(_Data2[b].response / 4.5);
            float2 aa = ap * float2(aspect, 1.0);
            float2 bb = bp * float2(aspect, 1.0);
            float lengthAB = length(bb - aa);
            if (lengthAB < 0.003 || lengthAB > connectionLimit) continue;
            float distanceToLine = sdSegment(uv * float2(aspect, 1.0), aa, bb);
            float proximity = smoothstep(connectionLimit, connectionLimit * 0.48, lengthAB);
            float responseWeight = sqrt(max(ar * br, 0.0));
            float thinLine = smoothstep(network_width, network_width * 0.22, distanceToLine);
            networkInk = max(networkInk, thinLine * proximity * responseWeight);
        }
    }
    col = lerp(col, network_ink, saturate(networkInk * network_opacity));

    float asciiOn = step(0.5, ascii_mode);
    float cellPx = lerp(25.0, 9.0, ascii_density);
    float2 cellCoord = pixel / cellPx;
    float2 cellIndex = floor(cellCoord);
    float2 cellLocal = frac(cellCoord);
    float2 sampleUv = (cellIndex + 0.5) * cellPx / _Resolution.xy;
    float cellLum = dot(_Tex0.SampleLevel(LinearSampler, sampleUv, 0).rgb, float3(0.2126, 0.7152, 0.0722));

    float blockField = 0.0;
    [loop]
    for (uint f = 0u; f < NETWORK_POINTS; ++f)
    {
        if (f >= count) break;
        float2 cp = float2(_Data2[f].x, _Data2[f].y) / ANALYSIS_SIZE;
        float responseWeight = saturate(_Data2[f].response / 2.8);
        float distanceToCorner = length((sampleUv - cp) * float2(aspect, 1.0));
        float localRadius = ascii_radius * (f == selected ? 1.38 : 1.0);
        float radial = saturate((localRadius - distanceToCorner) / max(localRadius * 0.78, 1e-5));
        float steppedRadial = floor(radial * 5.0 + 0.999) / 5.0;
        blockField = max(blockField, steppedRadial * responseWeight);
    }

    blockField = floor(saturate(blockField) * 5.0 + 0.5) / 5.0;
    float transition = step(0.01, blockField) * asciiOn;
    float cellEdgeDistance = min(min(cellLocal.x, 1.0 - cellLocal.x), min(cellLocal.y, 1.0 - cellLocal.y));
    float tileBody = step(0.055, cellEdgeDistance);
    float tileCore = step(0.105, cellEdgeDistance);
    float tileRule = saturate(tileBody - tileCore);
    float quantizedCellLum = floor(saturate(cellLum) * 6.0 + 0.5) / 6.0;
    float occupiedCell = step(0.08, quantizedCellLum);
    float conversionDepth = smoothstep(0.18, 0.82, blockField);
    float3 digitalTile = quantizedCellLum.xxx * lerp(0.78, 0.12, conversionDepth);
    float tileCoverage = transition * tileBody * occupiedCell;
    col = lerp(col, digitalTile, tileCoverage * 0.98);
    col = max(col, tileRule * transition * occupiedCell * lerp(0.28, 0.10, conversionDepth));

    float glyphField = step(0.32, blockField) * occupiedCell;
    float glyph = asciiGlyph(cellLocal, cellLum) * glyphField * ascii_amount * asciiOn;
    float3 asciiColor = lerp(0.88.xxx, corner_accent, smoothstep(0.58, 0.92, cellLum));
    col = lerp(col, asciiColor, saturate(glyph));

    float3 whiteInk = label_ink;
    float uiScale = max(_Resolution.y / 720.0, 0.65);
    [loop]
    for (uint p = 0u; p < NETWORK_POINTS; ++p)
    {
        if (p >= count) break;
        float2 cpUv = float2(_Data2[p].x, _Data2[p].y) / ANALYSIS_SIZE;
        float2 cpPixel = cpUv * _Resolution.xy;
        float responseWeight = saturate(_Data2[p].response / 4.5);
        float pointDistance = length(pixel - cpPixel);
        float pointRing = smoothstep(1.25 * uiScale, 0.25 * uiScale, abs(pointDistance - (3.0 + 2.5 * responseWeight) * uiScale));
        float pointCore = smoothstep(1.3 * uiScale, 0.18 * uiScale, pointDistance);
        col = lerp(col, p == selected ? corner_accent : whiteInk, saturate(pointRing * 0.90 + pointCore * 0.65));
        if (p == selected)
        {
            float2 selectedDelta = abs(pixel - cpPixel);
            float selectedBracket = max(
                smoothstep(1.15 * uiScale, 0.22 * uiScale, abs(selectedDelta.x - 11.0 * uiScale)) * step(selectedDelta.y, 4.0 * uiScale),
                smoothstep(1.15 * uiScale, 0.22 * uiScale, abs(selectedDelta.y - 11.0 * uiScale)) * step(selectedDelta.x, 4.0 * uiScale)
            );
            col = lerp(col, corner_accent, selectedBracket);
        }

        bool shouldLabel = p < min(count, LABELED_POINTS) || p == selected;
        if (!shouldLabel) continue;

        float side = cpUv.x > 0.69 ? -1.0 : 1.0;
        float vertical = cpUv.y < 0.18 ? 1.0 : -1.0;
        float2 labelOrigin = cpPixel + float2(side > 0.0 ? 13.0 : -51.0, vertical > 0.0 ? 13.0 : -49.0) * uiScale;
        float2 plateMin = labelOrigin + float2(-4.0, -3.0) * uiScale;
        float2 plateMax = labelOrigin + float2(40.0, 45.0) * uiScale;
        float plate = boxMask(pixel, plateMin, plateMax);
        float edgeDistance = min(
            min(abs(pixel.x - plateMin.x), abs(pixel.x - plateMax.x)),
            min(abs(pixel.y - plateMin.y), abs(pixel.y - plateMax.y))
        );
        float plateBorder = smoothstep(1.05 * uiScale, 0.22 * uiScale, edgeDistance) * plate;
        col = lerp(col, 0.004.xxx, plate * label_opacity * 0.88);
        col = lerp(col, p == selected ? corner_accent : whiteInk * 0.42, plateBorder * label_opacity);
        if (p == selected)
        {
            float selectedStrip = boxMask(
                pixel,
                plateMin,
                float2(plateMax.x, plateMin.y + 2.5 * uiScale)
            );
            col = lerp(col, corner_accent, selectedStrip * label_opacity);
        }

        float2 anchor = float2(side > 0.0 ? plateMin.x : plateMax.x, vertical > 0.0 ? plateMin.y : plateMax.y);
        float leader = smoothstep(1.0 * uiScale, 0.18 * uiScale, sdSegment(pixel, cpPixel, anchor));
        col = lerp(col, p == selected ? corner_accent : whiteInk, leader * label_opacity * (p == selected ? 0.88 : 0.36));

        int responseValue = min((int)round(max(_Data2[p].response, 0.0) * 100.0), 999);
        int xValue = min((int)round(max(_Data2[p].x, 0.0)), 999);
        int yValue = min((int)round(max(_Data2[p].y, 0.0)), 999);
        float text = 0.0;
        text = max(text, valueRow(pixel, labelOrigin, 0, responseValue, uiScale));
        text = max(text, valueRow(pixel, labelOrigin + float2(0.0, 15.0) * uiScale, 1, xValue, uiScale));
        text = max(text, valueRow(pixel, labelOrigin + float2(0.0, 30.0) * uiScale, 2, yValue, uiScale));
        col = lerp(col, p == selected ? corner_accent : whiteInk, text * label_opacity);
    }

    float edgeDistance = min(min(pixel.x, _Resolution.x - pixel.x), min(pixel.y, _Resolution.y - pixel.y));
    float frame = smoothstep(1.3, 0.22, edgeDistance);
    float ticks = max(
        step(0.88, frac(pixel.x / 31.0)) * step(pixel.y, 4.5),
        step(0.88, frac(pixel.y / 31.0)) * step(pixel.x, 4.5)
    );
    col = max(col, (frame * 0.25 + ticks * 0.48) * border_ticks);

    OutputUAV[id.xy] = float4(saturate(col), 1.0);
}
