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
        float rowPosition = t * 4.0;
        float row = min(floor(rowPosition), 3.0);
        float rowT = frac(rowPosition);
        float direction = fmod(row, 2.0) < 0.5 ? rowT : 1.0 - rowT;
        return float2(lerp(0.30, 0.70, direction), lerp(0.29, 0.71, row / 3.0));
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
    return anchor;
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
    float maskValue = luminance(_Tex2.SampleLevel(LinearSampler, cellCenter, 0).rgb);
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
    uint sourceWidth, sourceHeight;
    _Tex0.GetDimensions(sourceWidth, sourceHeight);
    float2 px = 1.0 / max(float2(sourceWidth, sourceHeight), 1.0);
    float2 stepUv = px * edge_width;

    float c = luminance(_Tex0.SampleLevel(LinearSampler, warpedUv, 0).rgb);
    float l = luminance(_Tex0.SampleLevel(LinearSampler, warpedUv - float2(stepUv.x, 0.0), 0).rgb);
    float r = luminance(_Tex0.SampleLevel(LinearSampler, warpedUv + float2(stepUv.x, 0.0), 0).rgb);
    float u = luminance(_Tex0.SampleLevel(LinearSampler, warpedUv - float2(0.0, stepUv.y), 0).rgb);
    float d = luminance(_Tex0.SampleLevel(LinearSampler, warpedUv + float2(0.0, stepUv.y), 0).rgb);
    float diagonalA = luminance(_Tex0.SampleLevel(LinearSampler, warpedUv + stepUv, 0).rgb);
    float diagonalB = luminance(_Tex0.SampleLevel(LinearSampler, warpedUv - stepUv, 0).rgb);

    float gradient = saturate(length(float2(r - l, d - u)) * 4.5);
    float cut = saturate((max(max(l, r), max(u, d)) - min(min(l, r), min(u, d))) * 3.2);
    float contourEcho = saturate(abs(diagonalA - diagonalB) * 3.0);

    float breakupNoise = fbm2D(uv * 8.4 - orbit * 0.31 + 12.8, 4);
    float breakup = lerp(1.0, smoothstep(0.24, 0.72, breakupNoise), organic_breakup);
    gradient *= breakup;
    cut *= lerp(1.0, breakup, 0.74);

    float3 feature = _Tex1.SampleLevel(LinearSampler, warpedUv, 0).rgb;
    float featureLuma = luminance(feature);
    float featureEdge = smoothstep(0.10, 0.72, featureLuma);
    float plateMask = smoothstep(0.08, 0.34, c);

    OutputUAV[tid.xy] = float4(saturate(max(gradient, cut)),
                               saturate(contourEcho),
                               saturate(featureEdge),
                               plateMask);
}
