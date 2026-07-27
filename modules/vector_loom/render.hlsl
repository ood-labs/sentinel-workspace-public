RWTexture2D<float4> OutputUAV : register(u0);

static const float2 ANALYSIS_SIZE = float2(480.0, 270.0);

float luminance(float3 c)
{
    return dot(c, float3(0.2126, 0.7152, 0.0722));
}

float segmentDistance(float2 p, float2 a, float2 b)
{
    float2 ab = b - a;
    float h = saturate(dot(p - a, ab) / max(dot(ab, ab), 1e-6));
    return length(p - (a + ab * h));
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;

    float2 uv = ((float2)pixel + 0.5) / _Resolution.xy;
    float aspect = _Resolution.x / max(_Resolution.y, 1.0);
    float2 p = (uv - 0.5) * float2(aspect, 1.0);
    float px = 1.0 / max(_Resolution.y, 1.0);

    float3 program = _Tex0.SampleLevel(LinearSampler, uv, 0).rgb;
    float programLum = luminance(program);
    float3 col = program * substrate_gain;
    col = lerp(col, programLum.xxx * substrate_gain, 0.65);

    uint count = min(_Data0_Count, 24);
    float3 whiteAccum = 0.0;
    float warmAccum = 0.0;
    float intersectionEnergy = 0.0;

    for (uint i = 0; i < count; ++i)
    {
        float2 aUv = float2(_Data0[i].x1, _Data0[i].y1) / ANALYSIS_SIZE;
        float2 bUv = float2(_Data0[i].x2, _Data0[i].y2) / ANALYSIS_SIZE;
        float2 a = (aUv - 0.5) * float2(aspect, 1.0);
        float2 b = (bUv - 0.5) * float2(aspect, 1.0);
        float2 ab = b - a;
        float segLen = max(length(ab), 1e-5);
        float2 dir = ab / segLen;
        float2 normal = float2(-dir.y, dir.x);
        float2 mid = (a + b) * 0.5;

        float along = dot(p - mid, dir);
        float across = abs(dot(p - mid, normal));
        float halfLen = segLen * 0.5;
        float width = px * beam_width * (1.0 + saturate(_Data0[i].length / 100.0) * 0.65);

        float segmentInk = 1.0 - smoothstep(width, width * 2.2, segmentDistance(p, a, b));

        float reach = halfLen + extension * (0.28 + segLen * 1.8);
        float reachMask = 1.0 - smoothstep(reach * 0.82, reach, abs(along));
        float beamInk = 1.0 - smoothstep(width * 0.26, width * 0.72, across);
        float dashPhase = frac((along + _Time * 0.028) * dash_density + (float)i * 0.173);
        float dashes = smoothstep(0.46, 0.52, dashPhase) * (1.0 - smoothstep(0.88, 0.95, dashPhase));
        float extensionInk = beamInk * reachMask * dashes * extension;

        float endpointA = 1.0 - smoothstep(width * 3.5, width * 7.0, length(p - a));
        float endpointB = 1.0 - smoothstep(width * 3.5, width * 7.0, length(p - b));
        float midpoint = 1.0 - smoothstep(width * 2.0, width * 5.5, length(p - mid));

        float angleWeight = 0.45 + 0.55 * abs(sin(radians(_Data0[i].angle)));
        float beamSignal = segmentInk * (0.62 + angleWeight * 0.38) + extensionInk * 0.58;
        whiteAccum += beamSignal * float3(0.72, 0.75, 0.73);
        whiteAccum += (endpointA + endpointB) * float3(0.42, 0.44, 0.43);

        float strongest = (i == 0) ? 1.0 : 0.0;
        float travelingNode = 0.5 + 0.5 * sin(_Time * 0.83 + along * 17.0 + (float)i);
        warmAccum += strongest * (midpoint * 1.3 + extensionInk * travelingNode * 0.22);
        intersectionEnergy += saturate(beamInk * reachMask);
    }

    float crossing = smoothstep(1.65, 3.4, intersectionEnergy);
    col *= 1.0 - crossing * void_cut;
    col += whiteAccum * tension_gain;
    col += warm_signal * warmAccum * signal_gain;
    col += crossing * float3(0.18, 0.19, 0.18);

    float vignette = 1.0 - smoothstep(0.46, 0.92, length(p));
    col *= 0.72 + 0.28 * vignette;
    col = col / (1.0 + col);
    col = pow(saturate(col), 1.0 / 1.25);
    col += float3(0.0015, 0.0018, 0.0020);

    OutputUAV[pixel] = float4(saturate(col), 1.0);
}
