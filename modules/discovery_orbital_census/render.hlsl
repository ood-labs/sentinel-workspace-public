RWTexture2D<float4> OutputUAV : register(u0);

float ringStroke(float radius, float target, float width)
{
    return 1.0 - smoothstep(width, width * 2.0, abs(radius - target));
}

float disc(float2 p, float2 center, float radius)
{
    return 1.0 - smoothstep(radius, radius * 1.45, length(p - center));
}

float segment(float2 p, float2 a, float2 b, float width)
{
    float2 pa = p - a;
    float2 ba = b - a;
    float h = saturate(dot(pa, ba) / max(dot(ba, ba), 0.00001));
    return 1.0 - smoothstep(width, width * 1.8, length(pa - ba * h));
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    if (DTid.x >= (uint)_Resolution.x || DTid.y >= (uint)_Resolution.y)
        return;

    float2 uv = ((float2)DTid.xy + 0.5) / _Resolution.xy;
    float aspect = _Resolution.x / _Resolution.y;
    float2 p = (uv - 0.5) * float2(aspect, 1.0);
    float phase = master_phase * 6.2831853;

    float3 black = float3(0.004, 0.004, 0.005);
    float3 gray = float3(0.19, 0.195, 0.205);
    float3 white = float3(0.91, 0.92, 0.93);
    float3 warm = float3(0.98, 0.44, 0.11);
    float3 color = black;

    float whiteInk = 0.0;
    float grayInk = 0.0;
    float warmInk = 0.0;

    float2 origin = float2(0.0, 0.0);
    if (layout_family == 1)
        origin = float2(-0.18, 0.02);

    [loop] for (int i = 0; i < 14; ++i)
    {
        if (i >= ring_count)
            break;

        float fi = (float)i;
        float normalized = (fi + 1.0) / max((float)ring_count, 1.0);
        float orbitRadius = lerp(0.075, 0.46, normalized);
        float eccentricity = 1.0 + orbit_eccentricity * sin(fi * 1.73 + phase * 0.18);
        float2 local = p - origin;

        if (layout_family == 2)
        {
            float twist = fi * 0.21;
            float ct = cos(twist);
            float st = sin(twist);
            local = float2(ct * local.x - st * local.y, st * local.x + ct * local.y);
        }

        float2 elliptical = local * float2(1.0 / eccentricity, eccentricity);
        float radial = length(elliptical);
        float angle = atan2(elliptical.y, elliptical.x);
        float ring = ringStroke(radial, orbitRadius, 0.0014 + 0.0008 * normalized);
        float dash = step(0.27, frac((angle / 6.2831853 + 0.5) * (5.0 + fi * 0.65) + fi * 0.13));
        grayInk = max(grayInk, ring * lerp(0.32, 0.72, dash));

        float direction = fmod(fi, 2.0) < 1.0 ? 1.0 : -1.0;
        float satelliteAngle = phase * direction * (0.38 + normalized * 0.9) + fi * 2.39996;
        float2 satellite = origin + float2(cos(satelliteAngle), sin(satelliteAngle)) * orbitRadius
            * float2(eccentricity, 1.0 / eccentricity);

        float satelliteSize = marker_scale * lerp(0.0045, 0.011, normalized);
        float marker = disc(p, satellite, satelliteSize);
        whiteInk = max(whiteInk, marker);

        float active = 1.0 - smoothstep(0.0, 0.18, abs(normalized - master_envelope));
        warmInk = max(warmInk, marker * active * (0.45 + master_pulse));

        if (fmod(fi, 3.0) < 0.5)
        {
            float tether = segment(p, origin, satellite, 0.00075);
            grayInk = max(grayInk, tether * 0.42);
        }
    }

    float centerCore = disc(p, origin, 0.018 + master_pulse * 0.012);
    float centerRing = ringStroke(length(p - origin), 0.038 + master_envelope * 0.018, 0.0017);
    whiteInk = max(whiteInk, centerRing);
    warmInk = max(warmInk, centerCore);

    float border = 1.0 - smoothstep(0.001, 0.003, min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y)));
    grayInk = max(grayInk, border * 0.75);

    color = lerp(color, gray, saturate(grayInk));
    color = lerp(color, white, saturate(whiteInk));
    color = lerp(color, warm, saturate(warmInk * accent_gain));

    OutputUAV[DTid.xy] = float4(saturate(color), 1.0);
}
