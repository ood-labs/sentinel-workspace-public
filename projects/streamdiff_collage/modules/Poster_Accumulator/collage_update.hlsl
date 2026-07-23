RWTexture2D<float4> OutputUAV : register(u0);

uint hashU32(uint x)
{
    x ^= x >> 16;
    x *= 0x7feb352du;
    x ^= x >> 15;
    x *= 0x846ca68bu;
    x ^= x >> 16;
    return x;
}

float eventRandom(uint hit, uint salt)
{
    uint seeded = hit ^ salt ^ asuint(layout_seed + 0.12345);
    return (hashU32(seeded) & 0x00ffffffu) / 16777216.0;
}

float hash21(float2 p)
{
    p = frac(p * float2(123.34, 345.45));
    p += dot(p, p + 34.345 + layout_seed);
    return frac(p.x * p.y);
}

void regionLayout(uint index, out float2 center, out float size, out float angle)
{
    uint i = index % 14u;
    if (i == 0u) { center = float2(0.22, 0.16); size = 0.35; angle = -0.10; }
    else if (i == 1u) { center = float2(0.69, 0.15); size = 0.40; angle = 0.08; }
    else if (i == 2u) { center = float2(0.48, 0.34); size = 0.44; angle = -0.04; }
    else if (i == 3u) { center = float2(0.16, 0.43); size = 0.34; angle = 0.11; }
    else if (i == 4u) { center = float2(0.82, 0.43); size = 0.39; angle = -0.12; }
    else if (i == 5u) { center = float2(0.42, 0.57); size = 0.47; angle = 0.06; }
    else if (i == 6u) { center = float2(0.15, 0.69); size = 0.36; angle = -0.09; }
    else if (i == 7u) { center = float2(0.77, 0.68); size = 0.43; angle = 0.12; }
    else if (i == 8u) { center = float2(0.45, 0.80); size = 0.37; angle = -0.08; }
    else if (i == 9u) { center = float2(0.82, 0.89); size = 0.32; angle = 0.06; }
    else if (i == 10u) { center = float2(0.18, 0.91); size = 0.39; angle = 0.14; }
    else if (i == 11u) { center = float2(0.50, 0.10); size = 0.25; angle = -0.16; }
    else if (i == 12u) { center = float2(0.57, 0.69); size = 0.29; angle = 0.15; }
    else { center = float2(0.31, 0.45); size = 0.27; angle = -0.18; }

    center += float2(eventRandom(index, 71u) - 0.5, eventRandom(index, 113u) - 0.5) * 0.055;
    size *= collage_scale * lerp(0.88, 1.12, eventRandom(index, 197u));
    angle += (eventRandom(index, 251u) - 0.5) * rotation_jitter;
}

float3 paperBackground(float2 uv)
{
    uint style = (uint)clamp(paper, 0, 2);
    float3 color = style == 0u ? float3(0.66, 0.55, 0.43) :
                   style == 1u ? float3(0.86, 0.82, 0.72) : float3(0.055, 0.045, 0.042);
    float fiber = hash21(floor(uv * float2(540.0, 675.0)));
    float broad = sin(uv.y * 93.0 + sin(uv.x * 17.0) * 2.0) * 0.5 + 0.5;
    color *= 0.94 + fiber * 0.08 + broad * 0.025;
    return color;
}

float4 liveCutout(float2 uv, uint placementRegion, uint effectRegion, float2 placementOffset)
{
    float2 center;
    float size;
    float angle;
    regionLayout(placementRegion, center, size, angle);
    center += placementOffset;

    float canvasAspect = _Resolution.x / max(_Resolution.y, 1.0);
    float2 p = float2((uv.x - center.x) * canvasAspect, uv.y - center.y);
    float cs = cos(angle), sn = sin(angle);
    float2 q = float2(cs * p.x + sn * p.y, -sn * p.x + cs * p.y);

    float sourceAspect;
    float sourceW, sourceH;
    _Tex0.GetDimensions(sourceW, sourceH);
    sourceAspect = sourceW / max(sourceH, 1.0);
    float2 halfSize = float2(size * sourceAspect, size) * 0.5;
    float2 localUv = q / max(halfSize * 2.0, 1e-4.xx) + 0.5;
    float inside = step(0.0, localUv.x) * step(localUv.x, 1.0) * step(0.0, localUv.y) * step(localUv.y, 1.0);

    float3 matteSample = _Tex1.SampleLevel(LinearSampler, saturate(localUv), 0).rgb;
    float mask = dot(matteSample, float3(0.299, 0.587, 0.114)) * inside;
    mask = smoothstep(cutout_threshold - cutout_feather, cutout_threshold + cutout_feather, mask);

    float ripPick = eventRandom(effectRegion, 307u);
    if (ripPick < rip_chance) {
        float ripNoise = hash21(float2(floor(localUv.x * 53.0), floor(localUv.y * 9.0)) + effectRegion * 2.7);
        float bands = abs(frac(localUv.y * 4.0 + ripNoise * 0.34) - 0.5);
        float rippedGap = 1.0 - smoothstep(0.025, 0.065, bands);
        mask *= 1.0 - rippedGap * saturate(effect_intensity);
    }

    float3 source = _Tex0.SampleLevel(LinearSampler, saturate(localUv), 0).rgb;
    float colorPick = eventRandom(effectRegion, 401u);
    if (colorPick < color_fx_chance) {
        uint fx = effectRegion % 5u;
        if (fx == 0u) source = floor(saturate(source) * 5.0 + 0.5) / 5.0;
        if (fx == 1u) {
            float l = dot(source, float3(0.299, 0.587, 0.114));
            source = lerp(float3(0.04, 0.12, 0.20), float3(0.96, 0.32, 0.08), smoothstep(0.18, 0.72, l));
        }
        if (fx == 2u) source = source.brg;
        if (fx == 3u) source = smoothstep(0.18, 0.78, source);
        if (fx == 4u) source = lerp(source, 1.0 - source, 0.42);
    }

    float halfPick = eventRandom(effectRegion, 503u);
    if (halfPick < halftone_chance) {
        float l = dot(source, float3(0.299, 0.587, 0.114));
        float2 cell = frac(localUv * float2(34.0, 52.0)) - 0.5;
        float radius = lerp(0.10, 0.47, sqrt(saturate(l)));
        float dots = 1.0 - smoothstep(radius, radius + 0.08, length(cell));
        float3 ink = source * lerp(0.12, 1.0, dots);
        source = lerp(source, ink, saturate(effect_intensity));
    }
    float shadowMask = _Tex1.SampleLevel(LinearSampler, saturate(localUv + float2(-0.025, -0.018)), 0).r * inside;
    shadowMask = smoothstep(0.12, 0.48, shadowMask) * (1.0 - mask) * drop_shadow;

    float frameMask = 0.0;
    float3 frameColor = float3(0.88, 0.80, 0.64);
    if (eventRandom(effectRegion, 601u) < frame_chance) {
        float frameWidth = lerp(0.032, 0.075, eventRandom(effectRegion, 607u));
        float edgeDistance = min(min(localUv.x, 1.0 - localUv.x), min(localUv.y, 1.0 - localUv.y));
        frameMask = inside * (1.0 - smoothstep(frameWidth, frameWidth + 0.012, edgeDistance));
        uint frameStyle = hashU32(effectRegion ^ 613u) % 4u;
        if (frameStyle == 1u) frameColor = float3(0.75, 0.07, 0.035);
        if (frameStyle == 2u) frameColor = float3(0.025, 0.10, 0.33);
        if (frameStyle == 3u) frameColor = float3(0.035, 0.28, 0.18);
    }

    float3 underLayer = lerp(float3(0.035, 0.025, 0.02), frameColor, frameMask);
    float3 layer = lerp(underLayer, source, mask);
    return float4(layer, saturate(mask + shadowMask * 0.55 + frameMask));
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 px = DTid.xy;
    if (px.x >= (uint)_Resolution.x || px.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)px + 0.5) / _Resolution;
    float4 previous = _Tex2.SampleLevel(LinearSampler, uv, 0);

    bool initialize = previous.a < 0.5 || reset_canvas;
    float3 color = initialize ? paperBackground(uv) : previous.rgb;

    float seconds = max(update_seconds, 0.05);
    float cycleF = floor(_Time / seconds + layout_seed * 0.31);
    float cycleCode = fmod(max(cycleF, 0.0), 65534.0) / 65534.0;
    float4 metadata = _Tex2.Load(int3(0, 0, 0));
    bool firstEvent = abs(metadata.g - 0.314159) > 0.001 || abs(metadata.r - cycleCode) > 0.000005;

    if (evolve && firstEvent && !reset_canvas) {
        uint count = (uint)clamp(region_count, 6, 14);
        uint cycle = (uint)max(cycleF, 0.0);
        float4 cutout = liveCutout(uv, cycle, cycle, 0.0.xx);
        float displacePick = eventRandom(cycle, 701u);
        bool disturbHistory = displacePick < displace_chance;
        if (disturbHistory) {
            float n = hash21(floor(uv * float2(73.0, 91.0)) + cycle * 1.3) * 2.0 - 1.0;
            float angle = eventRandom(cycle, 709u) * 6.2831853 + n * 1.4;
            float2 offset = float2(cos(angle), sin(angle)) * displace_strength * (0.35 + abs(n));
            float3 warpedHistory = _Tex2.SampleLevel(LinearSampler, saturate(uv + offset), 0).rgb;
            color = lerp(color, warpedHistory, cutout.a * saturate(effect_intensity));
        }
        // A rare registration echo lays three or four identical copies along
        // one short, regular vector. Farthest copies go down first so the
        // unshifted original remains crisp and on top.
        float repeatPick = eventRandom(cycle, 809u);
        bool repeatEvent = repeatPick < repeat_chance;
        if (repeatEvent) {
            float echoAngle = eventRandom(cycle, 811u) * 6.2831853;
            float echoSpacing = lerp(0.035, 0.062, eventRandom(cycle, 821u));
            float2 echoStep = float2(cos(echoAngle), sin(echoAngle)) * echoSpacing;
            bool fourCopies = eventRandom(cycle, 823u) < 0.42;
            if (fourCopies) {
                float4 echoC = liveCutout(uv, cycle, cycle, echoStep * 3.0);
                color = lerp(color, echoC.rgb, echoC.a);
            }
            float4 echoB = liveCutout(uv, cycle, cycle, echoStep * 2.0);
            float4 echoA = liveCutout(uv, cycle, cycle, echoStep);
            color = lerp(color, echoB.rgb, echoB.a);
            color = lerp(color, echoA.rgb, echoA.a);
        }
        float pasteAmount = disturbHistory && !repeatEvent ? 0.16 : 1.0;
        color = lerp(color, cutout.rgb, cutout.a * pasteAmount);

        // Occasionally paste a large paper/ink rectangle over the accumulated
        // poster. This deliberately removes visual information and restores
        // negative space instead of adding another object-shaped layer.
        if (eventRandom(cycle, 907u) < block_chance) {
            float2 blockCenter = float2(lerp(0.18, 0.82, eventRandom(cycle, 911u)),
                                        lerp(0.16, 0.84, eventRandom(cycle, 919u)));
            float2 blockHalf = float2(lerp(0.18, 0.34, eventRandom(cycle, 929u)),
                                      lerp(0.055, 0.15, eventRandom(cycle, 937u)));
            if (eventRandom(cycle, 941u) < 0.32) blockHalf = blockHalf.yx;
            float blockAngle = (eventRandom(cycle, 947u) - 0.5) * 0.34;
            float bc = cos(blockAngle), bs = sin(blockAngle);
            float2 bp = uv - blockCenter;
            float2 bq = float2(bc * bp.x + bs * bp.y, -bs * bp.x + bc * bp.y);
            float blockEdge = max(abs(bq.x) / max(blockHalf.x, 1e-4), abs(bq.y) / max(blockHalf.y, 1e-4));
            float blockMask = 1.0 - smoothstep(0.985, 1.015, blockEdge);

            float paperTone = eventRandom(cycle, 951u) < 0.5 ? 0.78 : 1.16;
            float3 blockColor = saturate(paperBackground(uv) * paperTone);
            float blockStyle = eventRandom(cycle, 953u);
            if (blockStyle > 0.74 && blockStyle <= 0.88) blockColor = float3(0.91, 0.84, 0.68);
            if (blockStyle > 0.88 && blockStyle <= 0.95) blockColor = float3(0.025, 0.09, 0.30);
            if (blockStyle > 0.95) blockColor = float3(0.72, 0.055, 0.025);
            color = lerp(color, blockColor, blockMask * 0.97);
            float blockBorder = blockMask * smoothstep(0.90, 0.975, blockEdge);
            float3 borderColor = blockStyle > 0.88 ? float3(0.91, 0.84, 0.68) : float3(0.10, 0.075, 0.055);
            color = lerp(color, borderColor, blockBorder * 0.48);
        }
    }

    OutputUAV[px] = float4(color, 1.0);
    if (px.x == 0u && px.y == 0u) OutputUAV[px] = float4(cycleCode, 0.314159, 0.271828, 1.0);
}
