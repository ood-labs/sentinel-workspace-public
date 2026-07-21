// Pattern Tracer topology renderer. Mode 0 preserves the original chronological
// open Catmull-Rom thread; the remaining modes expose alternate point connections.
struct SpawnPoint
{
    float x;
    float y;
    uint sequence;
    uint active;
};

RWTexture2D<float4> OutputUAV : register(u0);
StructuredBuffer<float4> DisplacementClock : register(t2);

static const uint PT_MAX_POINTS = 32u;

float ptSdSegmentField(float2 p, float2 a, float2 b, out float segmentT, out float2 fieldVector)
{
    float2 pa = p - a;
    float2 ba = b - a;
    segmentT = saturate(dot(pa, ba) / max(dot(ba, ba), 1e-5));
    fieldVector = pa - ba * segmentT;
    return length(fieldVector);
}

float ptSdSegment(float2 p, float2 a, float2 b, out float segmentT)
{
    float2 fieldVector;
    return ptSdSegmentField(p, a, b, segmentT, fieldVector);
}

float2 ptCatmull(float2 p0, float2 p1, float2 p2, float2 p3, float t)
{
    float t2 = t * t;
    float t3 = t2 * t;
    return 0.5 * ((2.0 * p1) + (-p0 + p2) * t
        + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
        + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3);
}

float ptTraceWindow(float u)
{
    float windowStart = trace_offset;
    float windowEnd = trace_offset + trace_length;
    float feather = 0.012;
    return smoothstep(windowStart - feather, windowStart + feather, u)
         * smoothstep(windowEnd + feather, windowEnd - feather, u);
}

float ptStroke(float distanceToPath, float u)
{
    float width = max(line_width, 0.1);
    float core = smoothstep(width + 1.5, width, distanceToPath);
    float halo = exp(-distanceToPath / max(glow_radius, 1.0)) * glow;
    return (core + halo) * ptTraceWindow(u);
}

float ptPointMask(float markerDistance)
{
    int style = clamp((int)point_style, 0, 2);
    float solid = smoothstep(point_size + 1.0, max(point_size - 1.0, 0.0), markerDistance);
    float ring = smoothstep(1.6, 0.0, abs(markerDistance - point_size));
    float core = smoothstep(max(point_size * 0.38, 1.0), 0.0, markerDistance);
    return style == 0 ? solid : (style == 1 ? ring : max(ring, core));
}

void ptUpdateDisplacementField(float candidateDistance, float2 candidateVector, float u,
                               inout float nearestDistance, inout float2 nearestVector)
{
    // The displacement follows the visible trace window, not every hidden
    // connection in the topology. The soft threshold retains its feathered ends.
    if (ptTraceWindow(u) <= 0.001 || candidateDistance >= nearestDistance) return;
    nearestDistance = candidateDistance;
    nearestVector = candidateVector;
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;

    float2 resolution = _Resolution.xy;
    float2 uv = ((float2)pixel + 0.5) / resolution;
    float2 pixelPosition = (float2)pixel + 0.5;
    float3 color = _Tex0.SampleLevel(LinearSampler, uv, 0).rgb * base_gain;

    float2 allPoints[64];
    uint activeCount = 0u;
    uint available = min(_Data0_Count, 64u);
    [loop] for (uint inputIndex = 0u; inputIndex < available; ++inputIndex) {
        SpawnPoint record = _Data0[inputIndex];
        if (record.active == 0u) continue;
        allPoints[activeCount] = float2(record.x * resolution.x,
                                        record.y * resolution.y);
        ++activeCount;
    }

    uint requested = (uint)clamp(point_count, 2, (int)PT_MAX_POINTS);
    uint count = min(activeCount, requested);
    if (count == 0u) {
        OutputUAV[pixel] = float4(color, 1.0);
        return;
    }

    uint first = activeCount - count;
    float2 points[32];
    [loop] for (uint pointIndex = 0u; pointIndex < count; ++pointIndex)
        points[pointIndex] = allPoints[first + pointIndex];

    if (count == 1u) {
        if (show_points != 0) {
            float markerMask = ptPointMask(distance(pixelPosition, points[0]));
            color = lerp(color, point_color, saturate(markerMask * point_opacity));
        }
        OutputUAV[pixel] = float4(color, 1.0);
        return;
    }

    int mode = clamp((int)trace_mode, 0, 5);
    float traceMask = 0.0;
    float displacementDistance = 1e9;
    float2 displacementVector = 0.0;

    if (mode == 0 || mode == 2) {
        // Original chronological Spline / centroid-sorted closed Loop.
        int order[32];
        [loop] for (uint orderIndex = 0u; orderIndex < count; ++orderIndex)
            order[orderIndex] = (int)orderIndex;

        bool closeLoop = mode == 2;
        if (closeLoop) {
            float2 centerPoint = 0.0;
            [loop] for (uint centroidIndex = 0u; centroidIndex < count; ++centroidIndex)
                centerPoint += points[centroidIndex];
            centerPoint /= (float)count;

            float angles[32];
            [loop] for (uint angleIndex = 0u; angleIndex < count; ++angleIndex)
                angles[angleIndex] = atan2(points[angleIndex].y - centerPoint.y,
                                           points[angleIndex].x - centerPoint.x);

            [loop] for (uint sortIndex = 1u; sortIndex < count; ++sortIndex) {
                int key = order[sortIndex];
                float keyAngle = angles[key];
                int previousIndex = (int)sortIndex - 1;
                [loop] while (previousIndex >= 0 && angles[order[previousIndex]] > keyAngle) {
                    order[previousIndex + 1] = order[previousIndex];
                    --previousIndex;
                }
                order[previousIndex + 1] = key;
            }
        }

        int pointTotal = (int)count;
        int segmentCount = closeLoop ? pointTotal : pointTotal - 1;
        int segmentSamples = clamp((int)smoothness, 4, 12);
        float nearest = 1e9;
        float nearestU = 0.0;

        [loop] for (int segment = 0; segment < segmentCount; ++segment) {
            int currentIndex;
            int previousPointIndex;
            int nextIndex;
            int followingIndex;
            if (closeLoop) {
                currentIndex = order[segment];
                previousPointIndex = order[(segment - 1 + pointTotal) % pointTotal];
                nextIndex = order[(segment + 1) % pointTotal];
                followingIndex = order[(segment + 2) % pointTotal];
            }
            else {
                currentIndex = order[segment];
                previousPointIndex = order[max(segment - 1, 0)];
                nextIndex = order[min(segment + 1, pointTotal - 1)];
                followingIndex = order[min(segment + 2, pointTotal - 1)];
            }

            float2 p0 = points[previousPointIndex];
            float2 p1 = points[currentIndex];
            float2 p2 = points[nextIndex];
            float2 p3 = points[followingIndex];
            float2 previous = p1;

            [loop] for (int sampleIndex = 1; sampleIndex <= segmentSamples; ++sampleIndex) {
                float t = (float)sampleIndex / (float)segmentSamples;
                float2 current = ptCatmull(p0, p1, p2, p3, t);
                float segmentT;
                float2 fieldVector;
                float distanceToCurve = ptSdSegmentField(pixelPosition, previous, current, segmentT, fieldVector);
                float curveU = ((float)segment + ((float)(sampleIndex - 1) + segmentT) / (float)segmentSamples)
                             / (float)segmentCount;
                ptUpdateDisplacementField(distanceToCurve, fieldVector, curveU,
                                          displacementDistance, displacementVector);
                if (distanceToCurve < nearest) {
                    nearest = distanceToCurve;
                    nearestU = ((float)segment + t) / (float)segmentCount;
                }
                previous = current;
            }
        }
        traceMask = ptStroke(nearest, nearestU);
    }
    else if (mode == 1) {
        // Straight chronological Chain with one continuous trim coordinate.
        float nearest = 1e9;
        float nearestU = 0.0;
        uint segmentCount = count - 1u;
        [loop] for (uint segment = 0u; segment < segmentCount; ++segment) {
            float segmentT;
            float2 fieldVector;
            float distanceToSegment = ptSdSegmentField(pixelPosition, points[segment], points[segment + 1u], segmentT, fieldVector);
            float segmentU = ((float)segment + segmentT) / (float)segmentCount;
            ptUpdateDisplacementField(distanceToSegment, fieldVector, segmentU,
                                      displacementDistance, displacementVector);
            if (distanceToSegment < nearest) {
                nearest = distanceToSegment;
                nearestU = segmentU;
            }
        }
        traceMask = ptStroke(nearest, nearestU);
    }
    else if (mode == 3) {
        // Distance-based Proximity web: every pair inside the normalized radius.
        float radiusPixels = link_distance * resolution.y;
        [loop] for (uint a = 0u; a < count; ++a) {
            [loop] for (uint b = a + 1u; b < count; ++b) {
                if (distance(points[a], points[b]) > radiusPixels) continue;
                float segmentT;
                float2 fieldVector;
                float distanceToSegment = ptSdSegmentField(pixelPosition, points[a], points[b], segmentT, fieldVector);
                ptUpdateDisplacementField(distanceToSegment, fieldVector, segmentT,
                                          displacementDistance, displacementVector);
                traceMask = max(traceMask, ptStroke(distanceToSegment, segmentT));
            }
        }
    }
    else if (mode == 4) {
        // Nearest-neighbour graph: each point reaches its spatially closest peer.
        [loop] for (uint a = 0u; a < count; ++a) {
            float bestDistance = 1e9;
            uint nearestIndex = a;
            [loop] for (uint b = 0u; b < count; ++b) {
                if (a == b) continue;
                float candidateDistance = distance(points[a], points[b]);
                if (candidateDistance < bestDistance) {
                    bestDistance = candidateDistance;
                    nearestIndex = b;
                }
            }
            float segmentT;
            float2 fieldVector;
            float distanceToSegment = ptSdSegmentField(pixelPosition, points[a], points[nearestIndex], segmentT, fieldVector);
            ptUpdateDisplacementField(distanceToSegment, fieldVector, segmentT,
                                      displacementDistance, displacementVector);
            traceMask = max(traceMask, ptStroke(distanceToSegment, segmentT));
        }
    }
    else {
        // Cage: cross-link each point to the next K chronological neighbours.
        uint links = (uint)clamp(links_per_point, 1, 6);
        [loop] for (uint a = 0u; a < count; ++a) {
            [loop] for (uint linkIndex = 1u; linkIndex <= links; ++linkIndex) {
                uint b = (a + linkIndex) % count;
                float segmentT;
                float2 fieldVector;
                float distanceToSegment = ptSdSegmentField(pixelPosition, points[a], points[b], segmentT, fieldVector);
                ptUpdateDisplacementField(distanceToSegment, fieldVector, segmentT,
                                          displacementDistance, displacementVector);
                traceMask = max(traceMask, ptStroke(distanceToSegment, segmentT));
            }
        }
    }

    // Warp the underlying canvas along the local line normal. Alternating bands
    // travel away from the trace as the persistent phase advances, while the
    // finite envelope keeps the displacement localized like a glow halo.
    float radius = max(displace_radius, 1.0);
    if (abs(displace_amount) > 0.001 && displacementDistance < radius) {
        float envelope = pow(saturate(1.0 - displacementDistance / radius), 2.0);
        float phase = frac(displace_phase + DisplacementClock[0].x);
        float rippleWave = sin((displacementDistance / radius) * displace_frequency * 6.2831853
                             - phase * 6.2831853);
        float displacementWave = lerp(1.0, rippleWave, saturate(displace_ripple));
        float2 normal = displacementVector / max(displacementDistance, 0.001);
        float offsetPixels = displace_amount * envelope * displacementWave;
        float2 displacedUv = saturate(uv - normal * offsetPixels / resolution);
        color = _Tex0.SampleLevel(LinearSampler, displacedUv, 0).rgb * base_gain;
    }

    color += line_color * traceMask * intensity;

    // Main spawn anchors are independent from the trace window, so they remain
    // legible even when only a short section of the path is being drawn.
    if (show_points != 0) {
        [loop] for (uint markerIndex = 0u; markerIndex < count; ++markerIndex) {
            float markerDistance = distance(pixelPosition, points[markerIndex]);
            float markerMask = ptPointMask(markerDistance);
            color = lerp(color, point_color, saturate(markerMask * point_opacity));
        }
    }

    OutputUAV[pixel] = float4(color, 1.0);
}
