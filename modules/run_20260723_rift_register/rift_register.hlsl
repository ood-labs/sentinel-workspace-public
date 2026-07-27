RWTexture2D<float4> OutputUAV : register(u0);

struct RiftRecord
{
    float x;
    float y;
    float strength;
    float polarity;
};

StructuredBuffer<RiftRecord> RiftRecords : register(t1);

static const float RR_TAU = 6.28318530718;

float3 rr_sample(float2 uv)
{
    return _Tex0.SampleLevel(LinearSampler, saturate(uv), 0.0).rgb;
}

float4 rr_route(float x)
{
    uint activeCount = (uint)clamp(route_count, 2, 12);
    RiftRecord firstRecord = RiftRecords[0];
    RiftRecord lastRecord = RiftRecords[activeCount - 1u];

    float routeY = firstRecord.y;
    float routeStrength = firstRecord.strength;
    float routePolarity = firstRecord.polarity;
    float routeSlope = 0.0;

    if (x >= lastRecord.x)
    {
        routeY = lastRecord.y;
        routeStrength = lastRecord.strength;
        routePolarity = lastRecord.polarity;
    }

    [unroll]
    for (uint recordIndex = 1u; recordIndex < 12u; ++recordIndex)
    {
        if (recordIndex >= activeCount) break;

        RiftRecord previousRecord = RiftRecords[recordIndex - 1u];
        RiftRecord currentRecord = RiftRecords[recordIndex];
        float span = max(currentRecord.x - previousRecord.x, 0.0001);
        float segmentT = saturate((x - previousRecord.x) / span);
        float inside = step(previousRecord.x, x) * step(x, currentRecord.x);

        float segmentY = lerp(previousRecord.y, currentRecord.y, segmentT);
        float segmentStrength = lerp(previousRecord.strength, currentRecord.strength, segmentT);
        float segmentPolarity = lerp(previousRecord.polarity, currentRecord.polarity, segmentT);
        float segmentSlope = (currentRecord.y - previousRecord.y) / span;

        routeY = lerp(routeY, segmentY, inside);
        routeStrength = lerp(routeStrength, segmentStrength, inside);
        routePolarity = lerp(routePolarity, segmentPolarity, inside);
        routeSlope = lerp(routeSlope, segmentSlope, inside);
    }

    return float4(routeY, routeStrength, routePolarity, routeSlope);
}

float rr_route_coverage(float x)
{
    uint activeCount = (uint)clamp(route_count, 2, 12);
    float firstX = RiftRecords[0].x;
    float lastX = RiftRecords[activeCount - 1u].x;
    float feather = 0.022;
    float enter = smoothstep(firstX - feather, firstX + feather, x);
    float leave = 1.0 - smoothstep(lastX - feather, lastX + feather, x);
    return saturate(enter * leave);
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;

    float2 extent = max(_Resolution.xy, float2(1.0, 1.0));
    float2 px = 1.0 / extent;
    float2 uv = ((float2)pixel + 0.5) / extent;
    float aspect = extent.x / extent.y;

    float4 route = rr_route(uv.x);
    float routeCoverage = rr_route_coverage(uv.x);
    float metricSlope = route.w / max(aspect, 0.0001);
    float distanceScale = rsqrt(1.0 + metricSlope * metricSlope);
    float signedDistance = (uv.y - route.x) * distanceScale;
    float distanceToRoute = abs(signedDistance);
    float domain = signedDistance >= 0.0 ? 1.0 : -1.0;

    float movingWave = sin(
        RR_TAU * (phase + uv.x * (2.0 + shear * 4.0)) +
        route.z * polarity_influence * 3.14159265
    );
    float pulse = 0.5 + 0.5 * movingWave;
    float liveEnergy = 0.42 + energy * 0.58;
    float gapWidth = rift_width * (0.76 + breath * pulse * liveEnergy);
    float displacement = parallax * liveEnergy * (0.76 + pulse * breath * 0.58);

    float registerSign = 1.0;
    if (rift_mode == 1)
    {
        float registerIndex = floor(uv.x * (float)register_count + phase * 2.0);
        registerSign = frac(registerIndex * 0.5) < 0.5 ? -1.0 : 1.0;
    }
    else if (rift_mode == 2)
    {
        float bandExtent = max(gapWidth * 1.45, px.y * 4.0);
        int bandIndex = (int)floor(distanceToRoute / bandExtent);
        registerSign = (bandIndex % 2) == 0 ? 1.0 : -1.0;
    }

    float tangentY = route.w * 0.12;
    float2 domainOffset = float2(
        domain * displacement * registerSign,
        -domain * displacement * tangentY * registerSign
    );

    if (rift_mode == 2)
    {
        float interleaveFalloff = exp(-distanceToRoute / max(gapWidth * 7.0, px.y * 8.0));
        domainOffset *= 0.45 + interleaveFalloff * 0.85;
    }

    float2 displacedUv = uv + domainOffset;
    float3 baseColor = rr_sample(uv);
    float3 displacedColor = rr_sample(displacedUv);

    float echoBand = 1.0 - smoothstep(
        gapWidth * (2.0 + echo_extent),
        gapWidth * (4.0 + echo_extent * 3.0),
        distanceToRoute
    );
    float2 echoOffset = domainOffset * (1.75 + echo_extent);
    float3 echoColor = rr_sample(uv - echoOffset);
    float echoMix = echo_amount * echoBand * (0.35 + route.y * 1.25);

    float3 composed = lerp(displacedColor, echoColor, saturate(echoMix));

    float gapMask = 1.0 - smoothstep(gapWidth, gapWidth + px.y * 2.2, distanceToRoute);
    composed *= 1.0 - gapMask * void_depth;

    float seamDistance = abs(distanceToRoute - gapWidth * 1.18);
    float seamMask = 1.0 - smoothstep(px.y * 0.9, px.y * 3.0, seamDistance);

    float2 gradientStep = float2(px.x * 1.5, px.y * 1.5);
    float3 gradX = rr_sample(displacedUv + float2(gradientStep.x, 0.0)) -
                   rr_sample(displacedUv - float2(gradientStep.x, 0.0));
    float3 gradY = rr_sample(displacedUv + float2(0.0, gradientStep.y)) -
                   rr_sample(displacedUv - float2(0.0, gradientStep.y));
    float sourceEdge = saturate((length(gradX) + length(gradY)) * 1.8);

    float warmPolarity = saturate(route.z * 0.5 + 0.5);
    float warmAmount = seamMask * edge_weight *
                       (0.32 + route.y * 1.18) *
                       lerp(0.65, 1.0, warmPolarity);
    float paleAmount = seamMask * edge_weight * (1.0 - warmPolarity) * 0.46;
    warmAmount += sourceEdge * echoBand * edge_weight * 0.11;

    composed = lerp(composed, seam_color, saturate(paleAmount));
    composed = lerp(composed, accent_color, saturate(warmAmount));

    float borderDistance = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
    float preserveFrame = smoothstep(0.018, 0.060, borderDistance);
    float effectAmount = preserveFrame * mix_amount * routeCoverage;
    float3 finalColor = lerp(baseColor, composed, effectAmount);

    OutputUAV[pixel] = float4(saturate(finalColor), 1.0);
}
