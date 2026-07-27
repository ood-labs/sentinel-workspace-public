RWTexture2D<float4> OutputUAV : register(u0);

float registration_luma(float3 c)
{
    return dot(c, float3(0.299, 0.587, 0.114));
}

float segment_distance(float2 p, float2 a, float2 b)
{
    float2 ab = b - a;
    float t = saturate(dot(p - a, ab) / max(dot(ab, ab), 1e-7));
    return length(p - (a + ab * t));
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y)
        return;

    float2 uv = ((float2)pixel + 0.5) / _Resolution.xy;
    float aspect = _Resolution.x / max(_Resolution.y, 1.0);
    float2 p = (uv - float2(0.5, 0.5) - registration_core) * float2(aspect, 1.0);
    float radius = length(p);
    float px = 1.0 / max(_Resolution.y, 1.0);

    float3 source = _Tex0.SampleLevel(LinearSampler, uv, 0).rgb;
    float localLum = registration_luma(source);

    float4 orientationState = _Tex1.SampleLevel(LinearSampler, float2(0.5, 0.5), 0);
    float2 needleDirection = normalize(orientationState.rg * 2.0 - 1.0);
    float gradientMagnitude = orientationState.b;

    float ringDistance = abs(radius - measure_radius);
    float ringLine = 1.0 - smoothstep(ring_width * px, (ring_width + 1.25) * px, ringDistance);

    float turns = atan2(p.y, p.x) / 6.28318530718 + 0.5;
    float tickCell = frac(turns * max(4.0, floor(tick_count + 0.5)));
    float tickPhase = min(tickCell, 1.0 - tickCell);
    float tickAngular = 1.0 - smoothstep(0.012, 0.055, tickPhase);
    float tickRadial = 1.0 - smoothstep(
        tick_length + ring_width * px,
        tick_length + (ring_width + 1.5) * px,
        abs(radius - measure_radius));
    float ticks = tickAngular * tickRadial;

    float fieldGate = lerp(0.55, 1.0, ring_continuity);
    float registration = max(ringLine * 0.62, ticks) * fieldGate * overlay_gain;

    float needleDistance = segment_distance(
        p,
        needleDirection * 0.055,
        needleDirection * needle_length);
    float needle = 1.0 - smoothstep(needle_width * px, (needle_width + 1.5) * px, needleDistance);
    needle *= smoothstep(0.002, 0.045, gradientMagnitude) * overlay_gain;

    float2 perpendicular = float2(-needleDirection.y, needleDirection.x);
    float transverse = abs(dot(p, perpendicular));
    float longitudinal = dot(p, needleDirection);
    float arrowHead =
        (1.0 - smoothstep(0.0, 2.2 * px, abs(longitudinal - needle_length + transverse * 1.35))) *
        step(transverse, 0.028) * step(longitudinal, needle_length + 0.006);
    arrowHead *= smoothstep(0.002, 0.045, gradientMagnitude) * overlay_gain;

    float coreCross =
        (1.0 - smoothstep(0.0, 0.70 * px, abs(p.x))) * step(abs(p.y), 0.016) +
        (1.0 - smoothstep(0.0, 0.70 * px, abs(p.y))) * step(abs(p.x), 0.016);
    coreCross = saturate(coreCross) * overlay_gain;

    float3 color = source;
    color = max(color, registration * float3(0.19, 0.20, 0.19));
    color = max(color, coreCross * float3(0.40, 0.41, 0.39));
    float warmInstrument = saturate(max(needle, arrowHead) * needle_gain);
    color = lerp(color, float3(1.0, 0.105, 0.018), warmInstrument);

    OutputUAV[pixel] = float4(saturate(color), 1.0);
}
