// Open Catmull-Rom thread through Pattern Canvas's chronological spawn history.
// _Tex0 is the Pattern Canvas image. _Data0 is the Spawn Points structured buffer.
struct SpawnPoint
{
    float x;
    float y;
    uint sequence;
    uint active;
};

RWTexture2D<float4> OutputUAV : register(u0);

float ptSdSegment(float2 p, float2 a, float2 b)
{
    float2 pa = p - a;
    float2 ba = b - a;
    float h = saturate(dot(pa, ba) / max(dot(ba, ba), 1e-5));
    return length(pa - ba * h);
}

float2 ptCatmull(float2 p0, float2 p1, float2 p2, float2 p3, float t)
{
    float t2 = t * t;
    float t3 = t2 * t;
    return 0.5 * ((2.0 * p1) + (-p0 + p2) * t
        + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
        + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3);
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;

    float2 resolution = _Resolution.xy;
    float2 uv = ((float2)pixel + 0.5) / resolution;
    float2 pixelPosition = (float2)pixel + 0.5;
    float3 base = _Tex0.SampleLevel(LinearSampler, uv, 0).rgb * base_gain;

    float2 allPoints[64];
    uint activeCount = 0u;
    uint available = min(_Data0_Count, 64u);
    [loop] for (uint i = 0u; i < available; ++i) {
        SpawnPoint record = _Data0[i];
        if (record.active == 0u) continue;
        allPoints[activeCount] = float2(record.x * resolution.x,
                                        record.y * resolution.y);
        ++activeCount;
    }

    uint requested = (uint)clamp(point_count, 2, 32);
    uint count = min(activeCount, requested);
    if (count < 2u) {
        OutputUAV[pixel] = float4(base, 1.0);
        return;
    }

    uint first = activeCount - count;
    int segmentCount = (int)count - 1;
    int segmentSamples = clamp((int)smoothness, 4, 12);
    float nearest = 1e9;
    float nearestU = 0.0;

    [loop] for (int segment = 0; segment < segmentCount; ++segment) {
        int p1Index = (int)first + segment;
        int p0Index = max(p1Index - 1, (int)first);
        int p2Index = min(p1Index + 1, (int)(first + count - 1u));
        int p3Index = min(p1Index + 2, (int)(first + count - 1u));
        float2 p0 = allPoints[p0Index];
        float2 p1 = allPoints[p1Index];
        float2 p2 = allPoints[p2Index];
        float2 p3 = allPoints[p3Index];
        float2 previous = p1;

        [loop] for (int sampleIndex = 1; sampleIndex <= segmentSamples; ++sampleIndex) {
            float t = (float)sampleIndex / (float)segmentSamples;
            float2 current = ptCatmull(p0, p1, p2, p3, t);
            float distanceToCurve = ptSdSegment(pixelPosition, previous, current);
            if (distanceToCurve < nearest) {
                nearest = distanceToCurve;
                nearestU = ((float)segment + t) / (float)segmentCount;
            }
            previous = current;
        }
    }

    float width = max(line_width, 0.1);
    float core = smoothstep(width + 1.5, width, nearest);
    float halo = exp(-nearest / max(glow_radius, 1.0)) * glow;
    float windowStart = trace_offset;
    float windowEnd = trace_offset + trace_length;
    float feather = 0.012;
    float traceWindow = smoothstep(windowStart - feather, windowStart + feather, nearestU)
                      * smoothstep(windowEnd + feather, windowEnd - feather, nearestU);

    float3 color = base;
    color += line_color * (core + halo) * traceWindow * intensity;

    if (show_points != 0) {
        [loop] for (uint markerIndex = 0u; markerIndex < count; ++markerIndex) {
            float markerU = (float)markerIndex / max((float)count - 1.0, 1.0);
            float markerWindow = step(windowStart, markerU) * step(markerU, windowEnd);
            float markerDistance = distance(pixelPosition, allPoints[first + markerIndex]);
            float ring = smoothstep(1.6, 0.0, abs(markerDistance - point_size));
            float dot = smoothstep(1.5, 0.0, markerDistance);
            color += line_color * (ring + dot * 0.6) * intensity * markerWindow;
        }
    }

    OutputUAV[pixel] = float4(color, 1.0);
}
