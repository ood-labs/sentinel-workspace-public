RWTexture2D<float4> OutputUAV : register(u0);

float luminance(float3 c)
{
    return dot(c, float3(0.2126, 0.7152, 0.0722));
}

float2 resolveBoxCenter(float2 anchor, float phaseValue)
{
    float t = frac(phaseValue);
    if (box_path_mode == 0)
    {
        float segmentPosition = t * 8.0;
        int segment = min((int)floor(segmentPosition), 7);
        float f = smoothstep(0.0, 1.0, frac(segmentPosition));
        float2 p0 = segment == 0 ? float2(0.30, 0.29)
                  : segment == 1 ? float2(0.70, 0.29)
                  : segment == 2 ? float2(0.70, 0.43)
                  : segment == 3 ? float2(0.30, 0.43)
                  : segment == 4 ? float2(0.30, 0.57)
                  : segment == 5 ? float2(0.70, 0.57)
                  : segment == 6 ? float2(0.70, 0.71)
                                 : float2(0.30, 0.71);
        float2 p1 = segment == 0 ? float2(0.70, 0.29)
                  : segment == 1 ? float2(0.70, 0.43)
                  : segment == 2 ? float2(0.30, 0.43)
                  : segment == 3 ? float2(0.30, 0.57)
                  : segment == 4 ? float2(0.70, 0.57)
                  : segment == 5 ? float2(0.70, 0.71)
                  : segment == 6 ? float2(0.30, 0.71)
                                 : float2(0.30, 0.29);
        return lerp(p0, p1, f);
    }
    if (box_path_mode == 1)
    {
        return float2(0.5 + sin(t * 18.8495559) * 0.18,
                      0.5 + sin(t * 12.5663706 + 1.5707963) * 0.20);
    }
    if (box_path_mode == 2)
    {
        float segmentPosition = t * 4.0;
        int segment = min((int)floor(segmentPosition), 3);
        float f = smoothstep(0.0, 1.0, frac(segmentPosition));
        float2 p0 = segment == 0 ? float2(0.33, 0.31)
                  : segment == 1 ? float2(0.67, 0.31)
                  : segment == 2 ? float2(0.67, 0.69)
                                 : float2(0.33, 0.69);
        float2 p1 = segment == 0 ? float2(0.67, 0.31)
                  : segment == 1 ? float2(0.67, 0.69)
                  : segment == 2 ? float2(0.33, 0.69)
                                 : float2(0.33, 0.31);
        return lerp(p0, p1, f);
    }
    float2 target = anchor;
    float totalWeight = 0.0;
    for (uint i = 0u; i < min(_Data0_Count, 64u); ++i)
    {
        if (_Data0[i].active < 0.5) continue;
        float w = 0.35 + _Data0[i].weight;
        target += (_Data0[i].position - 0.5) * w;
        totalWeight += w;
    }
    target = totalWeight > 0.0 ? target / (1.0 + totalWeight) + 0.5 : anchor;
    float jumpPhase = t * max(chase_jump_rate, 0.1);
    float2 wander = float2(sin(jumpPhase * 7.13 + 1.7), cos(jumpPhase * 5.41 + 3.1)) * chase_randomness;
    float2 micro = float2(sin(t * 37.0), cos(t * 31.0)) * chase_randomness * 0.22;
    float2 sporadic = target + wander + micro;
    return lerp(anchor, saturate(sporadic), chase_slew);
}

float sdSegmentHud(float2 p, float2 a, float2 b)
{
    float2 pa = p - a;
    float2 ba = b - a;
    float h = saturate(dot(pa, ba) / max(dot(ba, ba), 1e-6));
    return length(pa - ba * h);
}

uint sevenMask(int digit)
{
    if (digit == 0) return 0x3Fu;
    if (digit == 1) return 0x06u;
    if (digit == 2) return 0x5Bu;
    if (digit == 3) return 0x4Fu;
    if (digit == 4) return 0x66u;
    if (digit == 5) return 0x6Du;
    if (digit == 6) return 0x7Du;
    if (digit == 7) return 0x07u;
    if (digit == 8) return 0x7Fu;
    return 0x6Fu;
}

float drawDigit(float2 p, int digit)
{
    if (p.x < -0.1 || p.x > 1.1 || p.y < -0.1 || p.y > 1.1) return 0.0;
    float d[7];
    d[0] = sdSegmentHud(p, float2(0.20, 0.10), float2(0.80, 0.10));
    d[1] = sdSegmentHud(p, float2(0.85, 0.15), float2(0.85, 0.46));
    d[2] = sdSegmentHud(p, float2(0.85, 0.54), float2(0.85, 0.85));
    d[3] = sdSegmentHud(p, float2(0.20, 0.90), float2(0.80, 0.90));
    d[4] = sdSegmentHud(p, float2(0.15, 0.54), float2(0.15, 0.85));
    d[5] = sdSegmentHud(p, float2(0.15, 0.15), float2(0.15, 0.46));
    d[6] = sdSegmentHud(p, float2(0.20, 0.50), float2(0.80, 0.50));
    uint mask = sevenMask(digit);
    float distanceToSegment = 10.0;
    [unroll]
    for (uint i = 0u; i < 7u; ++i)
    {
        if ((mask & (1u << i)) != 0u) distanceToSegment = min(distanceToSegment, d[i]);
    }
    return smoothstep(0.074, 0.018, distanceToSegment);
}

float drawNumber3(float2 uv, float2 origin, float value)
{
    int number = (int)clamp(round(value), 0.0, 999.0);
    int digits[3];
    digits[0] = number / 100;
    digits[1] = (number / 10) % 10;
    digits[2] = number % 10;
    float ink = 0.0;
    [unroll]
    for (int i = 0; i < 3; ++i)
    {
        float2 digitOrigin = origin + float2((float)i * 0.0155, 0.0);
        float2 local = (uv - digitOrigin) / float2(0.0125, 0.024);
        ink = max(ink, drawDigit(local, digits[i]));
    }
    return ink;
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    if (tid.x >= (uint)_Resolution.x || tid.y >= (uint)_Resolution.y) return;

    float2 uv = ((float2)tid.xy + 0.5) / _Resolution.xy;
    float tau = frac(phase) * 6.28318530718;
    float2 orbit = float2(cos(tau), sin(tau));
    float n0 = fbm2D(uv * 4.2 + orbit * 0.46, 4);
    float n1 = fbm2D(uv.yx * 4.7 - orbit.yx * 0.39 + 7.3, 4);
    float2 flow = (float2(n0, n1) - 0.5) * carrier_warp;
    float2 grid = max(float2((float)block_columns, (float)block_rows), 1.0);
    float2 cell = floor(uv * grid);
    float2 cellCenter = (cell + 0.5) / grid;
    float maskValue = luminance(_Tex3.SampleLevel(LinearSampler, cellCenter, 0).rgb);
    float cellGate = smoothstep(block_mask_threshold - block_mask_softness,
                                block_mask_threshold + block_mask_softness,
                                maskValue);
    float2 movingBoxCenter = resolveBoxCenter(box_center, phase);
    float2 boxHalfSize = max(box_size * 0.5, 0.01);
    float2 boxQ = abs(uv - movingBoxCenter) - boxHalfSize;
    float boxDistance = max(boxQ.x, boxQ.y);
    float boxGate = 1.0 - smoothstep(-box_softness, box_softness, boxDistance);
    float distortionGate = (0.22 + cellGate * 0.78) * boxGate;
    float cellHash = hash21(cell + 0.37);
    float cellHashB = hash21(cell.yx + 7.91);
    float axis = step(0.5, cellHash);
    float direction = cellHashB > 0.5 ? 1.0 : -1.0;
    float pulse = 0.38 + 0.62 * (0.5 + 0.5 * sin(tau + cellHash * 6.28318530718));
    float2 blockOffset = lerp(float2(direction, 0.0), float2(0.0, direction), axis)
                       * block_displacement * distortionGate * pulse;
    float2 displacedUv = uv + flow + blockOffset;
    float2 local = displacedUv - movingBoxCenter;
    float localFalloff = saturate(1.0 - length(local / boxHalfSize) * 0.58);
    float localAngle = box_twist * distortionGate * localFalloff;
    float localCos = cos(localAngle);
    float localSin = sin(localAngle);
    float2 twistedLocal = float2(localCos * local.x - localSin * local.y,
                                 localSin * local.x + localCos * local.y);
    float2 warpedUv = lerp(displacedUv, movingBoxCenter + twistedLocal, distortionGate);

    float2 operationUv = warpedUv;
    float safeRepeats = max((float)operation_repeats, 2.0);
    if (box_operation == 1)
    {
        float2 normalizedBox = (warpedUv - movingBoxCenter) / max(box_size, 0.02) + 0.5;
        float2 folded = abs(frac(normalizedBox * safeRepeats) - 0.5) * 2.0;
        float2 foldedUv = movingBoxCenter + (folded - 0.5) * box_size;
        operationUv = lerp(warpedUv, foldedUv + flow * 0.32,
                           distortionGate * operation_depth);
    }
    else if (box_operation == 2)
    {
        float normalizedY = (uv.y - (movingBoxCenter.y - boxHalfSize.y))
                          / max(box_size.y, 0.02);
        float slice = floor(normalizedY * safeRepeats);
        float sliceShift = (hash21(float2(slice, 19.7)) * 2.0 - 1.0)
                         * block_displacement * 3.4;
        float2 sliceUv = warpedUv + float2(sliceShift, 0.0);
        operationUv = lerp(warpedUv, sliceUv, distortionGate * operation_depth);
    }
    warpedUv = operationUv;
    float2 fault = float2(registration_fault, -registration_fault * 0.61);
    float3 sourceOriginal = _Tex0.SampleLevel(LinearSampler, uv, 0).rgb;
    float3 source = _Tex0.SampleLevel(LinearSampler, warpedUv, 0).rgb;
    float operationDifference = abs(luminance(source) - luminance(sourceOriginal))
                              * distortionGate;
    float4 edges = _Tex1.SampleLevel(LinearSampler, uv, 0);
    float4 edgeEchoA = _Tex1.SampleLevel(LinearSampler, uv + float2(edge_echo, 0.0), 0);
    float4 edgeEchoB = _Tex1.SampleLevel(LinearSampler, uv - float2(0.0, edge_echo), 0);
    float4 impressions = _Tex2.SampleLevel(LinearSampler, uv, 0);
    float4 impressionFault = _Tex2.SampleLevel(LinearSampler, uv + fault, 0);

    float cutEdge = saturate(edges.r + edgeEchoA.g * 0.52 + edgeEchoB.r * 0.28);
    float featureEtch = saturate(edges.b * feature_edge_gain);
    float topologyPlate = saturate(impressions.r + impressionFault.r * 0.34);
    float pressurePlate = saturate(impressions.g + impressionFault.g * 0.45);
    float rhythmPlate = saturate(impressions.b + impressionFault.b * 0.38);

    float3 col = source;
    float plateLuma = luminance(source);
    float insidePlate = smoothstep(0.08, 0.24, plateLuma);
    float breakupNoise = fbm2D(uv * 7.1 - orbit * 0.27 + 18.2, 4);
    float breakupVeil = smoothstep(0.22, 0.78, breakupNoise + topologyPlate * 0.18);
    float brightTopology = smoothstep(0.66, 0.91, plateLuma);
    float carrierBand = insidePlate * (1.0 - brightTopology);
    float curvedCut = 0.08 * sin((uv.x * 4.0 + uv.y * 2.7 + breakupNoise) * 6.28318530718);
    float porosity = smoothstep(0.34, 0.67, breakupNoise + curvedCut);
    float porousCarrier = lerp(0.16, 1.06, porosity);
    col *= lerp(1.0, porousCarrier, carrierBand * organic_breakup * 0.88);

    float contourCoordinate = plateLuma * 7.0 + breakupNoise * 2.6 + topologyPlate * 0.9;
    float contourDistance = abs(frac(contourCoordinate) - 0.5);
    float contourRibs = smoothstep(0.12, 0.025, contourDistance)
                      * carrierBand * contour_gain * (0.46 + breakupVeil * 0.54);
    col = max(col, paper_color * contourRibs * 0.52);
    float outerCut = cutEdge * (0.55 + (1.0 - insidePlate) * 0.45);
    col = max(col, paper_color * outerCut * edge_gain);
    col = max(col, paper_color * featureEtch * (0.28 + insidePlate * 0.48));

    float topologyInk = topologyPlate * topology_preview_gain;
    float pressureInk = pressurePlate * pressure_preview_gain;
    float rhythmInk = rhythmPlate * rhythm_preview_gain;
    if (press_mode == 1)
    {
        col = max(col, paper_color * saturate(topologyInk + pressureInk * 0.72 + rhythmInk * 0.58));
    }
    else if (press_mode == 2)
    {
        col = lerp(col, paper_color, saturate(topologyInk * 0.46 + rhythmInk * 0.38));
        col = lerp(col, accent_color, saturate(pressureInk * 0.64 + featureEtch * 0.18));
    }
    else
    {
        col = max(col, paper_color * topologyInk * 0.36);
        col = max(col, paper_color * pressureInk * 0.72);
        col = max(col, paper_color * rhythmInk * 0.62);
    }

    float checker = step(0.52, frac(uv.x * _Resolution.x * 0.5 + uv.y * _Resolution.y * 0.5));
    float grainGate = saturate((topologyInk + pressureInk + rhythmInk) * halftone_gain);
    col = lerp(col, col * lerp(0.72, 1.08, checker), grainGate);

    float border = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
    float frame = smoothstep(0.0055, 0.0014, border) * frame_gain;
    float innerFrame = smoothstep(0.0008, 0.0001, abs(border - preview_inset)) * frame_gain * 0.42;
    col = max(col, paper_color * saturate(frame + innerFrame));

    float hairlineWidth = 1.15 / _Resolution.y;
    float boxHairline = smoothstep(hairlineWidth * 1.8, hairlineWidth * 0.18,
                                   abs(boxDistance)) * box_outline_gain;
    col = lerp(col, accent_color, boxHairline * 0.62);

    float2 operationCoord = (uv - movingBoxCenter) / max(box_size, 0.02) + 0.5;
    float insideOperation = step(0.0, operationCoord.x) * step(operationCoord.x, 1.0)
                          * step(0.0, operationCoord.y) * step(operationCoord.y, 1.0);
    float2 subdivision = abs(frac(operationCoord * safeRepeats) - 0.5);
    float gridDistance = min(subdivision.x, subdivision.y);
    float processGrid = smoothstep(hairlineWidth * 1.35, hairlineWidth * 0.18,
                                   gridDistance / safeRepeats)
                      * insideOperation * 0.22;
    float scanPosition = frac(phase * 2.0 + 0.17);
    float scanLine = smoothstep(hairlineWidth * 2.4, hairlineWidth * 0.22,
                                abs(operationCoord.y - scanPosition))
                   * insideOperation;
    float indexedLanePhase = frac(operationCoord.y * safeRepeats * 2.0
                                + floor(operationCoord.x * safeRepeats) * 0.5);
    float indexedLane = smoothstep(0.16, 0.035, abs(indexedLanePhase - 0.5))
                      * insideOperation;
    float indexedDifference = operationDifference * (0.12 + indexedLane * 0.88);
    col = max(col, paper_color * processGrid * operation_ink);
    col = lerp(col, accent_color,
               saturate(indexedDifference * operation_ink * 2.05 + scanLine * 0.30));

    float aspect = _Resolution.x / max(_Resolution.y, 1.0);
    float nodeTargets = 0.0;
    float nodeCores = 0.0;
    float kineticTargets = 0.0;
    float activeNodes = 0.0;
    float activeEmitters = 0.0;
    float insideNodes = 0.0;
    float insideEmitters = 0.0;
    float peakSpeed = 0.0;
    float meanEnergy = 0.0;

    [loop]
    for (uint i = 0u; i < min(_Data0_Count, 64u); ++i)
    {
        if (_Data0[i].active < 0.5) continue;
        activeNodes += 1.0;
        float2 nodePosition = _Data0[i].position;
        float2 nodeBox = abs(nodePosition - movingBoxCenter) - boxHalfSize;
        float nodeInside = step(max(nodeBox.x, nodeBox.y), 0.0);
        insideNodes += nodeInside;
        float nodeDistance = length((uv - nodePosition) * float2(aspect, 1.0));
        float radius = (1.6 + _Data0[i].weight * 2.2) / _Resolution.y;
        float target = smoothstep(hairlineWidth * 0.82, hairlineWidth * 0.12,
                                  abs(nodeDistance - radius));
        nodeTargets = max(nodeTargets, target * nodeInside);
        nodeCores = max(nodeCores,
                        smoothstep(radius * 0.58, radius * 0.08, nodeDistance)
                        * nodeInside);
    }

    [loop]
    for (uint i = 0u; i < min(_Data1_Count, 64u); ++i)
    {
        if (_Data1[i].active < 0.5) continue;
        activeEmitters += 1.0;
        peakSpeed = max(peakSpeed, _Data1[i].speed);
        meanEnergy += _Data1[i].energy;
        float2 eventPosition = _Data1[i].position;
        float2 eventBox = abs(eventPosition - movingBoxCenter) - boxHalfSize;
        float eventInside = step(max(eventBox.x, eventBox.y), 0.0);
        insideEmitters += eventInside;
        float eventDistance = length((uv - eventPosition) * float2(aspect, 1.0));
        float radius = (2.0 + _Data1[i].energy * 4.0) / _Resolution.y;
        float target = smoothstep(radius * 1.35, radius * 0.16, eventDistance);
        kineticTargets = max(kineticTargets, target * eventInside * _Data1[i].energy);
    }
    meanEnergy = activeEmitters > 0.0 ? meanEnergy / activeEmitters : 0.0;

    // Four corner registration targets and short orthogonal brackets.
    float2 absoluteBoxDelta = abs(uv - movingBoxCenter);
    float cornerDistance = length((absoluteBoxDelta - boxHalfSize) * float2(aspect, 1.0));
    float cornerDot = smoothstep(hairlineWidth * 3.8, hairlineWidth * 0.35, cornerDistance);
    float cornerRing = smoothstep(hairlineWidth * 1.25, hairlineWidth * 0.12,
                                  abs(cornerDistance - 0.0085));
    float nearHorizontalEdge = smoothstep(hairlineWidth * 1.35, hairlineWidth * 0.16,
                                          abs(absoluteBoxDelta.y - boxHalfSize.y));
    float nearVerticalEdge = smoothstep(hairlineWidth * 1.35, hairlineWidth * 0.16,
                                        abs(absoluteBoxDelta.x - boxHalfSize.x));
    float cornerReachX = step(boxHalfSize.x - 0.032, absoluteBoxDelta.x);
    float cornerReachY = step(boxHalfSize.y - 0.032, absoluteBoxDelta.y);
    float cornerBrackets = max(nearHorizontalEdge * cornerReachX,
                               nearVerticalEdge * cornerReachY);
    col = max(col, paper_color * saturate((nodeTargets * 0.74 + cornerBrackets * 0.58
                                          + cornerRing * 0.74 + cornerDot) * hud_gain));
    col = lerp(col, accent_color,
               saturate((kineticTargets * 0.88 + nodeCores * 0.62) * hud_gain));

    // The processing head carries its own live instrument strip. Counts are
    // spatially filtered to the current box so the attached numbers describe
    // the exact region being operated on.
    float2 stripMin = movingBoxCenter - boxHalfSize + float2(0.011, 0.012);
    float2 stripMax = stripMin + float2(0.128, 0.047);
    float2 stripOutside = max(stripMin - uv, uv - stripMax);
    float stripInside = step(max(stripOutside.x, stripOutside.y), 0.0);
    col *= 1.0 - stripInside * 0.64 * hud_gain;

    float stripBorderDistance = min(min(abs(uv.x - stripMin.x), abs(uv.x - stripMax.x)),
                                    min(abs(uv.y - stripMin.y), abs(uv.y - stripMax.y)));
    float stripFrame = smoothstep(hairlineWidth * 1.35, hairlineWidth * 0.14,
                                  stripBorderDistance) * stripInside;
    float stripDivider = smoothstep(hairlineWidth * 1.2, hairlineWidth * 0.14,
                                    abs(uv.x - (stripMin.x + 0.064)))
                       * step(stripMin.y + 0.005, uv.y)
                       * step(uv.y, stripMax.y - 0.005);
    float stripNodes = drawNumber3(uv, stripMin + float2(0.015, 0.006), insideNodes);
    float stripEmitters = drawNumber3(uv, stripMin + float2(0.079, 0.006), insideEmitters);
    float stripNodeIcon = smoothstep(hairlineWidth * 1.25, hairlineWidth * 0.14,
                                    abs(length((uv - (stripMin + float2(0.008, 0.018)))
                                               * float2(aspect, 1.0)) - 0.0038));
    float stripEmitterIcon = smoothstep(hairlineWidth * 1.8, hairlineWidth * 0.12,
                                       length((uv - (stripMin + float2(0.072, 0.018)))
                                              * float2(aspect, 1.0)));
    float meterStart = stripMin.x + 0.008;
    float meterEnd = stripMax.x - 0.008;
    float meterY = stripMax.y - 0.006;
    float meterRail = smoothstep(hairlineWidth * 1.1, hairlineWidth * 0.14,
                                 abs(uv.y - meterY))
                    * step(meterStart, uv.x) * step(uv.x, meterEnd);
    float meterFill = meterRail
                    * step(uv.x, lerp(meterStart, meterEnd, saturate(peakSpeed * 32.0)));
    float stripInk = saturate(stripFrame * 0.72 + stripDivider * 0.34
                            + stripNodes * 0.74 + stripEmitters * 0.74
                            + stripNodeIcon * 0.72 + meterRail * 0.22);
    col = max(col, paper_color * stripInk * hud_gain);
    col = lerp(col, accent_color,
               saturate((stripEmitterIcon * 0.86 + meterFill * 0.72) * hud_gain));

    // Fine calibration ticks lock the HUD to the moving head rather than the frame.
    float boxTicks = 0.0;
    [unroll]
    for (int tickIndex = 0; tickIndex < 9; ++tickIndex)
    {
        float tickX = movingBoxCenter.x - boxHalfSize.x
                    + box_size.x * ((float)tickIndex + 0.5) / 9.0;
        float tickLength = (tickIndex == 4) ? 0.012 : 0.007;
        float tickLine = smoothstep(hairlineWidth * 1.15, hairlineWidth * 0.12,
                                    abs(uv.x - tickX))
                       * step(movingBoxCenter.y - boxHalfSize.y, uv.y)
                       * step(uv.y, movingBoxCenter.y - boxHalfSize.y + tickLength);
        boxTicks = max(boxTicks, tickLine);
    }
    col = max(col, paper_color * boxTicks * hud_gain * 0.62);

    // Fixed top-left live readout plate:
    // row glyphs are node target, emitter burst, velocity arrow, edge bars.
    float readoutNode = drawNumber3(uv, float2(0.060, 0.105), activeNodes);
    float readoutEmitters = drawNumber3(uv, float2(0.060, 0.139), activeEmitters);
    float readoutSpeed = drawNumber3(uv, float2(0.060, 0.173), peakSpeed * 1000.0);
    float readoutEdges = drawNumber3(uv, float2(0.060, 0.207), hud_edge_density * 1000.0);
    float2 iconCenter0 = float2(0.046, 0.117);
    float2 iconCenter1 = float2(0.046, 0.151);
    float2 iconCenter2 = float2(0.046, 0.185);
    float2 iconCenter3 = float2(0.046, 0.219);
    float iconNode = smoothstep(hairlineWidth * 1.2, hairlineWidth * 0.18,
                                abs(length((uv - iconCenter0) * float2(aspect, 1.0)) - 0.0055));
    float iconEmitter = smoothstep(hairlineWidth * 1.4, hairlineWidth * 0.18,
                                   length((uv - iconCenter1) * float2(aspect, 1.0)));
    float iconVelocity = smoothstep(hairlineWidth * 1.2, hairlineWidth * 0.16,
                                    sdSegmentHud(uv, iconCenter2 - float2(0.006, 0.0),
                                                iconCenter2 + float2(0.006, 0.0)));
    float edgeBars = 0.0;
    [unroll]
    for (int b = 0; b < 3; ++b)
    {
        float barX = iconCenter3.x - 0.006 + (float)b * 0.006;
        edgeBars = max(edgeBars,
                       smoothstep(hairlineWidth * 1.1, hairlineWidth * 0.15,
                                  abs(uv.x - barX))
                       * step(abs(uv.y - iconCenter3.y), 0.005));
    }
    float readoutInk = saturate(readoutNode + readoutEmitters + readoutSpeed + readoutEdges
                              + iconNode + iconEmitter + iconVelocity + edgeBars);
    float readoutBorderX = min(abs(uv.x - 0.036), abs(uv.x - 0.128));
    float readoutBorderY = min(abs(uv.y - 0.092), abs(uv.y - 0.238));
    float readoutBounds = step(0.036, uv.x) * step(uv.x, 0.128)
                        * step(0.092, uv.y) * step(uv.y, 0.238);
    float readoutFrame = smoothstep(hairlineWidth * 1.25, hairlineWidth * 0.15,
                                    min(readoutBorderX, readoutBorderY)) * readoutBounds;
    float readoutRule = smoothstep(hairlineWidth * 1.15, hairlineWidth * 0.14,
                                   abs(uv.x - 0.116))
                      * step(0.099, uv.y) * step(uv.y, 0.231);
    float readoutPulse = smoothstep(hairlineWidth * 1.2, hairlineWidth * 0.12,
                                    abs(uv.y - lerp(0.226, 0.104, saturate(peakSpeed * 32.0))))
                       * step(0.116, uv.x) * step(uv.x, 0.124);
    col = max(col, paper_color * saturate((readoutInk * 0.74 + readoutFrame * 0.42
                                         + readoutRule * 0.22) * hud_gain));
    col = lerp(col, accent_color, readoutPulse * hud_gain * 0.68);
    col = lerp(col, accent_color, readoutEmitters * saturate(meanEnergy) * 0.34);

    float faultMark = saturate(abs(impressions.r - impressionFault.r) * registration_fault * 12.0
                             + featureEtch * edgeEchoA.g * 0.065);
    col = lerp(col, accent_color, faultMark);
    OutputUAV[tid.xy] = float4(saturate(col * exposure), 1.0);
}
