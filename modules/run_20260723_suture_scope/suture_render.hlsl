RWTexture2D<float4> OutputUAV : register(u0);

struct SutureRecord
{
    float x;
    float y;
    float strength;
    float polarity;
};

StructuredBuffer<SutureRecord> SutureRecords : register(t1);

float3 ss_source(float2 uv)
{
    uint width;
    uint height;
    _Tex0.GetDimensions(width, height);
    float2 extent = float2(max(width, 1u), max(height, 1u));
    int2 coord = int2(saturate(uv) * max(extent - 1.0, float2(1.0, 1.0)));
    return _Tex0.Load(int3(coord, 0)).rgb;
}

float ss_segment_distance(float2 p, float2 a, float2 b)
{
    float2 ab = b - a;
    float denominator = max(dot(ab, ab), 0.000001);
    float t = saturate(dot(p - a, ab) / denominator);
    return length(p - (a + ab * t));
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;

    float2 uv = ((float2)pixel + 0.5) / max(_Resolution.xy, float2(1.0, 1.0));
    float aspect = _Resolution.x / max(_Resolution.y, 1.0);
    float2 p = float2(uv.x * aspect, uv.y);
    float px = 1.0 / max(_Resolution.y, 1.0);
    uint activeCount = (uint)clamp(scan_count, 1, 12);

    float2 focalPoint = float2(scan_center.x * aspect, scan_center.y);
    float focalWeight = 0.0;
    float2 focalSum = 0.0;

    [unroll]
    for (uint centroidIndex = 0u; centroidIndex < 12u; ++centroidIndex)
    {
        if (centroidIndex >= activeCount) break;
        SutureRecord centroidRecord = SutureRecords[centroidIndex];
        float active = smoothstep(record_threshold * 0.55, record_threshold, centroidRecord.strength);
        float weight = centroidRecord.strength * active;
        focalSum += float2(centroidRecord.x * aspect, centroidRecord.y) * weight;
        focalWeight += weight;
    }

    if (focalWeight > 0.0001)
    {
        focalPoint = focalSum / focalWeight;
    }

    float wireMask = 0.0;
    float accentMask = 0.0;
    float markerMask = 0.0;

    [unroll]
    for (uint recordIndex = 0u; recordIndex < 12u; ++recordIndex)
    {
        if (recordIndex >= activeCount) break;

        SutureRecord record = SutureRecords[recordIndex];
        float active = smoothstep(record_threshold * 0.55, record_threshold, record.strength);
        float2 anchor = float2(record.x * aspect, record.y);
        float signalRadius = marker_radius * px * (0.68 + record.strength * 0.82);
        float anchorDistance = length(p - anchor);
        float ring = 1.0 - smoothstep(px * 0.8, px * 2.2, abs(anchorDistance - signalRadius));
        float crossHorizontal = (1.0 - smoothstep(path_width * px, path_width * px * 2.4, abs(p.y - anchor.y))) *
                                (1.0 - smoothstep(signalRadius * 0.78, signalRadius * 1.28, abs(p.x - anchor.x)));
        float crossVertical = (1.0 - smoothstep(path_width * px, path_width * px * 2.4, abs(p.x - anchor.x))) *
                              (1.0 - smoothstep(signalRadius * 0.78, signalRadius * 1.28, abs(p.y - anchor.y)));
        markerMask = max(markerMask, max(ring, max(crossHorizontal, crossVertical)) * active);

        float pathSignal = 0.0;
        if (render_mode == 0 && recordIndex > 0u)
        {
            SutureRecord previous = SutureRecords[recordIndex - 1u];
            float previousActive = smoothstep(record_threshold * 0.55, record_threshold, previous.strength);
            float2 previousAnchor = float2(previous.x * aspect, previous.y);
            float distanceToPath = ss_segment_distance(p, previousAnchor, anchor);
            pathSignal = 1.0 - smoothstep(path_width * px, path_width * px * 2.8, distanceToPath);
            float segmentStrength = sqrt(saturate(min(record.strength, previous.strength)));
            pathSignal *= active * previousActive * (0.28 + segmentStrength * 0.72);
        }
        else if (render_mode == 1)
        {
            float2 baselineAnchor = float2(anchor.x, scan_center.y);
            float distanceToNeedle = ss_segment_distance(p, anchor, baselineAnchor);
            pathSignal = 1.0 - smoothstep(path_width * px, path_width * px * 2.6, distanceToNeedle);
            pathSignal *= active * (0.25 + sqrt(saturate(record.strength)) * 0.75);
        }
        else if (render_mode == 2)
        {
            float distanceToCentroid = ss_segment_distance(p, anchor, focalPoint);
            pathSignal = 1.0 - smoothstep(path_width * px, path_width * px * 2.8, distanceToCentroid);
            pathSignal *= active * (0.25 + sqrt(saturate(record.strength)) * 0.75);
        }

        float warmPolarity = saturate(record.polarity * 0.5 + 0.5);
        float warmSignal = max(markerMask * record.strength, pathSignal) * warmPolarity;
        wireMask = max(wireMask, pathSignal);
        accentMask = max(accentMask, warmSignal);
    }

    if (render_mode == 2)
    {
        float centroidDistance = length(p - focalPoint);
        float centroidRing = 1.0 - smoothstep(px, px * 2.4, abs(centroidDistance - marker_radius * px * 1.45));
        markerMask = max(markerMask, centroidRing);
    }

    float3 col = ss_source(uv);
    float wireAmount = saturate(max(wireMask * wire_weight, markerMask * marker_weight) * scope_mix);
    float liveAccent = accent_weight * (0.38 + energy * 0.62);
    float accentAmount = saturate(accentMask * liveAccent * scope_mix);
    col = lerp(col, wire_color, wireAmount);
    col = lerp(col, accent_color, accentAmount);

    OutputUAV[pixel] = float4(saturate(col), 1.0);
}
