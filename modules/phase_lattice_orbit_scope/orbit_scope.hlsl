RWTexture2D<float4> OutputUAV : register(u0);

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y)
        return;

    float2 uv = ((float2)pixel + 0.5) / _Resolution.xy;
    float aspect = _Resolution.x / max(_Resolution.y, 1.0);
    float3 source = _Tex0.SampleLevel(LinearSampler, uv, 0).rgb;

    float stripStart = 1.0 - strip_height;
    float insideStrip = step(stripStart, uv.y);
    float stripY = saturate((uv.y - stripStart) / max(strip_height, 0.001));

    float angleTurns = frac(uv.x + angular_offset);
    float angle = angleTurns * 6.28318530718 - 3.14159265359;
    float radius = sample_radius + (stripY - 0.5) * radial_span;
    float2 radialDirection = float2(cos(angle) / aspect, sin(angle));
    float2 sampleUV = saturate(float2(0.5, 0.5) + scope_core + radialDirection * radius);
    float angleStep = 6.28318530718 * 1.35 / max(_Resolution.x, 1.0);
    float radialStep = radial_span * 1.25 / max(_Resolution.y * strip_height, 1.0);
    float2 directionBefore = float2(cos(angle - angleStep) / aspect, sin(angle - angleStep));
    float2 directionAfter = float2(cos(angle + angleStep) / aspect, sin(angle + angleStep));
    float radiusBefore = radius - radialStep;
    float radiusAfter = radius + radialStep;
    float2 origin = float2(0.5, 0.5) + scope_core;

    float3 annulus = float3(0.0, 0.0, 0.0);
    annulus += _Tex0.SampleLevel(LinearSampler, saturate(origin + directionBefore * radiusBefore), 0).rgb;
    annulus += _Tex0.SampleLevel(LinearSampler, saturate(origin + radialDirection * radiusBefore), 0).rgb * 2.0;
    annulus += _Tex0.SampleLevel(LinearSampler, saturate(origin + directionAfter * radiusBefore), 0).rgb;
    annulus += _Tex0.SampleLevel(LinearSampler, saturate(origin + directionBefore * radius), 0).rgb * 2.0;
    annulus += _Tex0.SampleLevel(LinearSampler, sampleUV, 0).rgb * 4.0;
    annulus += _Tex0.SampleLevel(LinearSampler, saturate(origin + directionAfter * radius), 0).rgb * 2.0;
    annulus += _Tex0.SampleLevel(LinearSampler, saturate(origin + directionBefore * radiusAfter), 0).rgb;
    annulus += _Tex0.SampleLevel(LinearSampler, saturate(origin + radialDirection * radiusAfter), 0).rgb * 2.0;
    annulus += _Tex0.SampleLevel(LinearSampler, saturate(origin + directionAfter * radiusAfter), 0).rgb;
    annulus *= 0.0625;

    float centerRule = 1.0 - smoothstep(0.0, 1.35 / max(_Resolution.y * strip_height, 1.0), abs(stripY - 0.5));
    float divisions = max(4.0, floor(division_count + 0.5));
    float divisionCell = frac(angleTurns * divisions);
    float divisionDistance = min(divisionCell, 1.0 - divisionCell);
    float divisionRule = 1.0 - smoothstep(0.0, 1.15 / max(_Resolution.x / divisions, 1.0), divisionDistance);
    divisionRule *= smoothstep(0.0, 0.14, abs(stripY - 0.5));

    float separator = 1.0 - smoothstep(
        0.0,
        1.5 / max(_Resolution.y, 1.0),
        abs(uv.y - stripStart));

    float3 scope = annulus * scope_gain;
    scope = max(scope, centerRule * float3(0.18, 0.19, 0.18));
    scope = max(scope, divisionRule * float3(0.105, 0.11, 0.105));
    scope *= smoothstep(0.0, 0.06, stripY) * smoothstep(0.0, 0.06, 1.0 - stripY);

    float3 composed = lerp(source, scope, insideStrip * scope_mix);
    composed = max(composed, separator * separator_gain * float3(0.32, 0.33, 0.31));

    OutputUAV[pixel] = float4(saturate(composed), 1.0);
}
