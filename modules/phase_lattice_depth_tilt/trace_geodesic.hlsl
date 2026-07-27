struct GeodesicPoint
{
    float2 position;
    float progress;
    float confidence;
};

RWStructuredBuffer<GeodesicPoint> OutputBuffer : register(u0);

float trace_luma(float3 c)
{
    return dot(c, float3(0.299, 0.587, 0.114));
}

float trace_field(float2 p, float aspect, float2 texel)
{
    float2 uv = p / float2(aspect, 1.0) + float2(0.5, 0.5) + tilt_core;
    return trace_luma(_Tex0.SampleLevel(LinearSampler, uv, 0).rgb);
}

[numthreads(1, 1, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint width;
    uint height;
    _Tex0.GetDimensions(width, height);
    float aspect = (float)width / max((float)height, 1.0);
    float2 texel = 1.0 / float2(max(width, 1), max(height, 1));

    float confidence = smoothstep(0.08, 0.48, azimuth_confidence);
    float2 forward = normalize(float2(azimuth_x, azimuth_y) + float2(1e-5, 0.0));
    float2 travel = forward;
    float2 position = forward * geodesic_start;

    [unroll]
    for (uint i = 0; i < 24; ++i)
    {
        GeodesicPoint record;
        record.position = position;
        record.progress = (float)i / 23.0;
        record.confidence = confidence;
        OutputBuffer[i] = record;

        float2 uv = position / float2(aspect, 1.0) + float2(0.5, 0.5) + tilt_core;
        float lx0 = trace_luma(_Tex0.SampleLevel(LinearSampler, uv - float2(texel.x * 2.0, 0.0), 0).rgb);
        float lx1 = trace_luma(_Tex0.SampleLevel(LinearSampler, uv + float2(texel.x * 2.0, 0.0), 0).rgb);
        float ly0 = trace_luma(_Tex0.SampleLevel(LinearSampler, uv - float2(0.0, texel.y * 2.0), 0).rgb);
        float ly1 = trace_luma(_Tex0.SampleLevel(LinearSampler, uv + float2(0.0, texel.y * 2.0), 0).rgb);
        float2 gradient = float2((lx1 - lx0) / max(aspect, 1e-4), ly1 - ly0);
        float edgeStrength = length(gradient);

        float2 tangent = normalize(float2(-gradient.y, gradient.x) + travel * 1e-4);
        tangent *= dot(tangent, travel) < 0.0 ? -1.0 : 1.0;
        float fieldLock = smoothstep(gradient_gate, gradient_gate + 0.16, edgeStrength);
        float steering = contour_follow * fieldLock * turn_rate;
        travel = normalize(lerp(travel, tangent, steering) + forward * forward_bias);
        position += travel * geodesic_step;
    }
}
