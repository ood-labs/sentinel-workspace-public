RWTexture2D<float4> OutputUAV : register(u0);

float hash21_local(float2 p)
{
    p = frac(p * float2(123.34, 345.45));
    p += dot(p, p + 34.345);
    return frac(p.x * p.y);
}

float value_noise(float2 p)
{
    float2 cell = floor(p);
    float2 f = frac(p);
    f = f * f * (3.0 - 2.0 * f);

    float a = hash21_local(cell);
    float b = hash21_local(cell + float2(1.0, 0.0));
    float c = hash21_local(cell + float2(0.0, 1.0));
    float d = hash21_local(cell + float2(1.0, 1.0));
    return lerp(lerp(a, b, f.x), lerp(c, d, f.x), f.y);
}

float2 rotate2(float2 p, float angle)
{
    float s = sin(angle);
    float c = cos(angle);
    return float2(c * p.x - s * p.y, s * p.x + c * p.y);
}

float contour(float value, float count, float width)
{
    float ridge = abs(frac(value * count + 0.5) - 0.5);
    return 1.0 - smoothstep(0.018 * width, 0.070 * width, ridge);
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y)
        return;

    float2 uv = ((float2)pixel + 0.5) / _Resolution.xy;
    float aspect = _Resolution.x / max(_Resolution.y, 1.0);
    float2 p = (uv - 0.5) * float2(aspect, 1.0);
    p -= core * float2(aspect, 1.0);

    float t = _Time;
    float2 slowOrbit = float2(cos(t * 0.137), sin(t * 0.113));
    float n0 = value_noise(p * 3.7 + slowOrbit);
    float n1 = value_noise(rotate2(p, 0.78) * 7.1 - slowOrbit.yx);
    float2 warped = p + fracture * 0.085 * float2(n0 - 0.5, n1 - 0.5);

    float field = 0.0;
    if (topology == 0)
    {
        float radius = length(warped);
        float angle = atan2(warped.y, warped.x);
        field =
            sin(radius * density - t * 0.71 + sin(angle * 5.0 - t * 0.19) * 1.8) * 0.55 +
            cos((warped.x * 0.83 - warped.y * 0.56) * density * 0.82 + t * 0.31) * 0.30 +
            sin(angle * 9.0 + radius * density * 0.34) * 0.15;
    }
    else if (topology == 1)
    {
        float2 q = rotate2(warped, 0.29 + sin(t * 0.11) * 0.06);
        q.x += sin(q.y * density * 0.52 - t * 0.43) * (0.09 + fracture * 0.11);
        field =
            sin(q.x * density + t * 0.37) * 0.54 +
            cos((q.x + q.y * 1.73) * density * 0.57 - t * 0.23) * 0.31 +
            sin(q.y * density * 1.19 + n0 * 3.0) * 0.15;
    }
    else
    {
        float2 q = rotate2(warped, -0.63);
        float folded = abs(frac(q.x * 3.15 + sin(t * 0.17) * 0.08 + 0.5) - 0.5);
        float foldedY = abs(frac(q.y * 3.85 - cos(t * 0.13) * 0.06 - 0.5) - 0.5);
        field =
            sin((folded - foldedY) * density * 0.66 - t * 0.47) * 0.54 +
            cos((folded + foldedY) * density * 0.41 + t * 0.29) * 0.31 +
            sin((q.x - q.y) * density * 0.22 + n1 * 1.8) * 0.15;
    }

    field = field * 0.5 + 0.5;
    float mainContour = contour(field, contour_count, line_weight);
    float microContour = contour(field + n1 * 0.075, contour_count * 0.5, line_weight * 0.55);

    float cell = floor(saturate(field) * contour_count) / max(contour_count, 1.0);
    float paper = 0.010 + cell * 0.026;
    float3 color = float3(paper, paper * 0.96, paper * 0.90);
    color += mainContour * float3(0.82, 0.84, 0.80);
    color += microContour * 0.14 * float3(0.52, 0.55, 0.53);

    float seam = 1.0 - smoothstep(0.015, 0.062, abs(n0 - n1));
    float gate = smoothstep(accent_gate, accent_gate + 0.18, field);
    float accentMask = seam * gate * (0.25 + 0.75 * mainContour);
    color = lerp(color, float3(1.0, 0.245, 0.055), accentMask * 0.92);

    float2 corePx = p * float2(_Resolution.y, _Resolution.y);
    float radialPx = length(corePx);
    float registerRing =
        (1.0 - smoothstep(0.0, 1.25, abs(radialPx - 20.0))) +
        (1.0 - smoothstep(0.0, 1.0, abs(radialPx - 34.0)));
    float registerCross =
        (1.0 - smoothstep(0.0, 0.8, abs(corePx.x))) * step(abs(corePx.y), 48.0) +
        (1.0 - smoothstep(0.0, 0.8, abs(corePx.y))) * step(abs(corePx.x), 48.0);
    color += saturate(registerRing + registerCross) * float3(0.18, 0.18, 0.16);

    float vignette = smoothstep(1.0, 0.25, length((uv - 0.5) * float2(1.05, 1.0)));
    color *= lerp(0.56, 1.0, vignette);
    color = saturate(color);

    OutputUAV[pixel] = float4(color, 1.0);
}
