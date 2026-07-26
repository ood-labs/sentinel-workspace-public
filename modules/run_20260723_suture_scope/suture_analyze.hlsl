struct SutureRecord
{
    float x;
    float y;
    float strength;
    float polarity;
};

RWStructuredBuffer<SutureRecord> OutputBuffer : register(u0);

float ss_luma(float3 c)
{
    return dot(c, float3(0.2126, 0.7152, 0.0722));
}

float ss_luma_at(float2 uv, uint width, uint height)
{
    if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0)
    {
        return 0.0;
    }

    float2 extent = float2(max(width, 1u), max(height, 1u));
    int2 coord = int2(saturate(uv) * max(extent - 1.0, float2(1.0, 1.0)));
    return ss_luma(_Tex0.Load(int3(coord, 0)).rgb);
}

[numthreads(1, 1, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint recordIndex = DTid.x;
    if (recordIndex >= 12u) return;

    uint activeCount = (uint)clamp(scan_count, 1, 12);
    SutureRecord record;
    record.x = 0.0;
    record.y = 0.0;
    record.strength = 0.0;
    record.polarity = 0.0;

    if (recordIndex >= activeCount)
    {
        OutputBuffer[recordIndex] = record;
        return;
    }

    uint width;
    uint height;
    _Tex0.GetDimensions(width, height);
    float2 texel = 1.0 / float2(max(width, 1u), max(height, 1u));

    float lane = ((float)recordIndex + 0.5) / max((float)activeCount, 1.0);
    float roamAngle = phase * 6.28318530718 + (float)recordIndex * 0.713;
    float x = scan_center.x + (lane - 0.5) * scan_span.x;
    x += sin(roamAngle) * roam * 0.032;

    float yMin = scan_center.y - scan_span.y * 0.5;
    float yMax = scan_center.y + scan_span.y * 0.5;
    float weightedY = 0.0;
    float weightedPolarity = 0.0;
    float totalWeight = 0.0;
    float totalRawSignal = 0.0;

    [unroll]
    for (uint sampleIndex = 0u; sampleIndex < 64u; ++sampleIndex)
    {
        float sampleT = ((float)sampleIndex + 0.5) / 64.0;
        float y = lerp(yMin, yMax, sampleT);
        float2 sampleUv = float2(x, y);

        float upValue = ss_luma_at(sampleUv - float2(0.0, texel.y * 2.0), width, height);
        float downValue = ss_luma_at(sampleUv + float2(0.0, texel.y * 2.0), width, height);
        float leftValue = ss_luma_at(sampleUv - float2(texel.x * 2.0, 0.0), width, height);
        float rightValue = ss_luma_at(sampleUv + float2(texel.x * 2.0, 0.0), width, height);

        float verticalGradient = downValue - upValue;
        float horizontalGradient = rightValue - leftValue;
        float rawSignal = abs(verticalGradient) + abs(horizontalGradient) * 0.62;
        float gatedSignal = saturate((rawSignal - edge_floor) * signal_gain);
        float weight = pow(gatedSignal, anchor_sharpness);

        weightedY += y * weight;
        weightedPolarity += sign(verticalGradient + horizontalGradient * 0.35) * weight;
        totalWeight += weight;
        totalRawSignal += max(rawSignal - edge_floor, 0.0);
    }

    record.x = saturate(x);
    record.y = totalWeight > 0.0001 ? saturate(weightedY / totalWeight) : saturate(scan_center.y);
    record.strength = saturate(totalRawSignal * signal_gain / 64.0);
    record.polarity = totalWeight > 0.0001 ? clamp(weightedPolarity / totalWeight, -1.0, 1.0) : 0.0;
    OutputBuffer[recordIndex] = record;
}
