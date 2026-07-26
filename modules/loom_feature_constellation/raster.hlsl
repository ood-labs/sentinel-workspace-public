RWTexture2D<float4> OutputUAV : register(u0);

float lineDistance(float2 p, float2 a, float2 b) {
    float2 ab = b - a;
    float t = saturate(dot(p - a, ab) / max(dot(ab, ab), 1e-6));
    return length(p - (a + ab * t));
}

[numthreads(8, 8, 1)]
void main(uint3 id : SV_DispatchThreadID) {
    if (id.x >= (uint)_Resolution.x || id.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)id.xy + 0.5) / _Resolution.xy;
    float aspect = _Resolution.x / max(_Resolution.y, 1.0);
    float2 p = (uv - 0.5) * float2(aspect, 1.0) - center_bias * 0.20;

    float3 src = _Tex0.SampleLevel(LinearSampler, uv, 0).rgb;
    float luma = dot(src, float3(0.2126, 0.7152, 0.0722));
    float3 col = lerp(src, src * float3(0.62, 0.78, 0.94), 0.22) * base_gain;
    col += float3(0.006, 0.010, 0.020) * (1.0 - luma);

    uint blobCount = min(_Data1_Count, 8u);
    float blobMist = 0.0;
    float blobLinks = 0.0;
    for (uint b = 0u; b < blobCount; ++b) {
        float2 buv = float2(_Data1[b].centroidX, _Data1[b].centroidY) / max(analysis_size, float2(1.0, 1.0));
        float2 bp = (buv - 0.5) * float2(aspect, 1.0) - center_bias * 0.20;
        float areaNorm = saturate(_Data1[b].area / max(analysis_size.x * analysis_size.y, 1.0));
        float radius = 0.035 + sqrt(areaNorm) * 0.22;
        float d = length(p - bp);
        float weight = 0.35 + 0.65 * (1.0 - smoothstep(0.34, 0.82, areaNorm));
        blobMist += exp(-d * d / max(radius * radius * 1.8, 1e-5)) * weight;
        if (blobCount > 1u) {
            uint bj = (b + 1u) % blobCount;
            float2 buv2 = float2(_Data1[bj].centroidX, _Data1[bj].centroidY) / max(analysis_size, float2(1.0, 1.0));
            float2 bp2 = (buv2 - 0.5) * float2(aspect, 1.0) - center_bias * 0.20;
            blobLinks += exp(-lineDistance(p, bp, bp2) * 520.0) * weight;
        }
    }

    uint cornerCount = min(_Data0_Count, 24u);
    float cornerPoints = 0.0;
    float cornerThreads = 0.0;
    for (uint i = 0u; i < cornerCount; ++i) {
        float2 cuv = float2(_Data0[i].x, _Data0[i].y) / max(analysis_size, float2(1.0, 1.0));
        float2 cp = (cuv - 0.5) * float2(aspect, 1.0) - center_bias * 0.20;
        float response = saturate(_Data0[i].response * response_gain * 58.0);
        float radius = (1.1 + point_radius * 0.35) / max(_Resolution.y, 1.0);
        float d = length(p - cp);
        cornerPoints += pow(max(0.0, 1.0 - d / max(radius * 3.0, 1e-5)), 2.0) * response;

        // Corners stay granular; only a sparse subset may form a hairline to
        // the blob field. This prevents high corner counts becoming spokes.
        if (blobCount > 0u && (i % 4u) == 0u) {
            uint target = i % blobCount;
            float2 buv = float2(_Data1[target].centroidX, _Data1[target].centroidY) / max(analysis_size, float2(1.0, 1.0));
            float2 bp = (buv - 0.5) * float2(aspect, 1.0) - center_bias * 0.20;
            float ld = lineDistance(p, cp, bp);
            float along = dot(p - cp, normalize(bp - cp + float2(1e-5, 0.0)));
            float dash = smoothstep(0.62, 0.90, 0.5 + 0.5 * sin(along * dash_density * 120.0 - _Time * flow_speed * 2.0 + (float)i));
            cornerThreads += exp(-ld * link_sharpness * 2.4) * dash * response * 0.42;
        }
    }

    float3 cool = lerp(float3(0.025, 0.18, 0.26), palette_a, 0.32);
    float3 warm = lerp(float3(1.0, 0.72, 0.56), palette_b, 0.28);
    col += cool * min(blobMist, 1.4) * 0.16;
    col += palette_a * blobLinks * 0.20;
    col += warm * cornerPoints * point_gain * 0.48;
    col += lerp(cool, warm, 0.42) * cornerThreads * link_gain * 0.16;
    OutputUAV[id.xy] = float4(min(col, 3.0), 1.0);
}
