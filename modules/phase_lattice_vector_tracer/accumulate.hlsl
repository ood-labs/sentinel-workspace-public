RWTexture2D<float4> OutputUAV : register(u0);

float tracer_luma(float3 c)
{
    return dot(c, float3(0.299, 0.587, 0.114));
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint outputWidth;
    uint outputHeight;
    OutputUAV.GetDimensions(outputWidth, outputHeight);
    if (DTid.x >= outputWidth || DTid.y >= outputHeight)
        return;

    float2 uv = ((float2)DTid.xy + 0.5) / float2(outputWidth, outputHeight);
    uint sourceWidth;
    uint sourceHeight;
    _Tex0.GetDimensions(sourceWidth, sourceHeight);
    float2 sourceTexel = 1.0 / max(float2(sourceWidth, sourceHeight), float2(1.0, 1.0));
    float aspect = sourceWidth / max((float)sourceHeight, 1.0);

    float3 engraved = _Tex0.SampleLevel(LinearSampler, uv, 0).rgb;
    float lumL = tracer_luma(_Tex0.SampleLevel(LinearSampler, uv - float2(sourceTexel.x, 0.0), 0).rgb);
    float lumR = tracer_luma(_Tex0.SampleLevel(LinearSampler, uv + float2(sourceTexel.x, 0.0), 0).rgb);
    float lumU = tracer_luma(_Tex0.SampleLevel(LinearSampler, uv - float2(0.0, sourceTexel.y), 0).rgb);
    float lumD = tracer_luma(_Tex0.SampleLevel(LinearSampler, uv + float2(0.0, sourceTexel.y), 0).rgb);
    float2 gradient = float2((lumR - lumL) * aspect, lumD - lumU);
    float edgeStrength = length(gradient);

    float2 globalDirection = normalize(float2(azimuth_x, azimuth_y) + float2(1e-5, 0.0));
    float2 tangent = edgeStrength > 1e-5
        ? normalize(float2(-gradient.y, gradient.x))
        : globalDirection;
    tangent *= dot(tangent, globalDirection) < 0.0 ? -1.0 : 1.0;
    float2 flowDirection = normalize(lerp(globalDirection, tangent, flow_alignment));
    float2 flowUV = flowDirection * float2(1.0 / aspect, 1.0);

    float dt = min(max(_DeltaTime, 0.0), 0.05);
    float2 historyUV = uv - flowUV * drift_speed * dt;
    float4 previous = _Tex1.SampleLevel(LinearSampler, historyUV, 0);
    float decay = pow(retention, dt * 60.0);

    float2 p = (uv - float2(0.5, 0.5) - tracer_core) * float2(aspect, 1.0);
    float radius = length(p);
    float orbitDistance = (radius - trace_radius) / max(orbit_width, 0.001);
    float orbitGate = exp(-orbitDistance * orbitDistance);
    float coreGate = smoothstep(core_clear * 0.55, core_clear, radius);

    float redDominance = max(0.0, engraved.r - max(engraved.g, engraved.b));
    float redDeposit = smoothstep(deposit_gate, deposit_gate + 0.16, redDominance);
    float edgeGate = smoothstep(0.012, 0.095, edgeStrength);
    float confidenceGate = smoothstep(0.08, 0.48, azimuth_confidence);
    float deposit = redDeposit * edgeGate * orbitGate * coreGate * confidenceGate;

    float trail = max(previous.r * decay, deposit);
    float fresh = max(previous.g * pow(0.78, dt * 60.0), deposit);
    OutputUAV[DTid.xy] = float4(saturate(trail), saturate(fresh), azimuth_confidence, 1.0);
}
