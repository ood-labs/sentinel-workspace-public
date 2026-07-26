RWTexture2D<float4> OutputUAV : register(u0);

static const float TAU = 6.28318530718;

float segmentDistance(float2 p, float2 a, float2 b)
{
    float2 ab = b - a;
    float h = saturate(dot(p - a, ab) / max(dot(ab, ab), 0.000001));
    return length(p - (a + ab * h));
}

float lineMask(float distanceValue, float widthValue, float pixelSize)
{
    return 1.0 - smoothstep(widthValue, widthValue + pixelSize * 1.5, distanceValue);
}

float cyclicDistance(float a, float b)
{
    return abs(frac(a - b + 0.5) - 0.5);
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    uint2 pixel = tid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y)
        return;

    float2 uv = ((float2)pixel + 0.5) / max(_Resolution.xy, float2(1.0, 1.0));
    float aspect = _Resolution.x / max(_Resolution.y, 1.0);
    float2 p = (uv - 0.5) * float2(aspect, 1.0);
    float pixelSize = 1.0 / max(_Resolution.y, 1.0);

    float phase = frac(max(phase_driver, 0.0));
    float apertureSignal = saturate(sine_driver);
    float quadrature = saturate(quadrature_driver);
    float accentSignal = saturate(accent_driver);

    float3 background = float3(0.0035, 0.0040, 0.0038);
    float3 coolInk = saturate(ink_color);
    float3 warmInk = saturate(scar_color);
    float3 col = background;

    float radiusX = aperture_base + aperture_range * apertureSignal;
    float radiusY = radiusX * (0.58 + 0.20 * quadrature);
    float ellipse = length(float2(p.x / max(radiusX, 0.001), p.y / max(radiusY, 0.001)));
    float voidMask = smoothstep(0.97, 1.02, ellipse);

    float fieldLeft = -aspect * 0.44;
    float fieldRight = aspect * 0.44;
    float fieldTop = -0.43;
    float fieldBottom = 0.43;
    float strandWidth = pixelSize * max(stroke_px, 0.5);
    float outerFade = smoothstep(0.50, 0.42, abs(p.y));

    float whiteLayer = 0.0;
    float warmLayer = 0.0;

    [loop]
    for (int i = 0; i < 96; ++i)
    {
        if (i >= strand_count)
            continue;

        float fi = ((float)i + 0.5) / max((float)strand_count, 1.0);
        float x0 = lerp(fieldLeft, fieldRight, fi);
        float warpPhase = p.y * (1.15 + 0.45 * quadrature) + phase + fi * 0.085;
        float centerEnvelope = 0.28 + 0.72 * exp(-abs(p.y) * 3.2);
        float xCurve = x0 + sin(warpPhase * TAU) * warp_amount * centerEnvelope;

        float normalizedY = p.y / max(radiusY, 0.001);
        float boundary = radiusX * sqrt(saturate(1.0 - normalizedY * normalizedY));
        float side = x0 < 0.0 ? -1.0 : 1.0;
        float nearSeam = smoothstep(radiusY * 1.45, radiusY * 0.72, abs(p.y));
        float pushedX = side * (boundary + seam_width + abs(x0) * 0.22);
        xCurve = lerp(xCurve, pushedX, nearSeam * smoothstep(radiusX * 2.6, radiusX * 0.55, abs(x0)));

        float distanceToStrand = abs(p.x - xCurve);
        float strand = lineMask(distanceToStrand, strandWidth, pixelSize) * outerFade;
        strand *= (p.y >= fieldTop && p.y <= fieldBottom) ? 1.0 : 0.0;

        float strandPhase = frac(fi + phase);
        float active = 1.0 - smoothstep(0.0, 0.045, cyclicDistance(strandPhase, 0.5));
        warmLayer = max(warmLayer, strand * active * (0.25 + 0.75 * accentSignal));
        whiteLayer = max(whiteLayer, strand * (1.0 - active * 0.8));
    }

    [loop]
    for (int k = 0; k < 24; ++k)
    {
        if (k >= stitch_count)
            continue;

        float fk = ((float)k + phase) / max((float)stitch_count, 1.0);
        float row = frac(fk);
        float y = lerp(-radiusY * 0.82, radiusY * 0.82, row);
        float normalizedY = y / max(radiusY, 0.001);
        float xBoundary = radiusX * sqrt(saturate(1.0 - normalizedY * normalizedY));
        float direction = (k & 1) == 0 ? 1.0 : -1.0;
        float tilt = direction * (0.010 + 0.018 * quadrature);
        float2 a = float2(-xBoundary - seam_width * 0.70, y - tilt);
        float2 b = float2( xBoundary + seam_width * 0.70, y + tilt);

        float stitch = lineMask(segmentDistance(p, a, b), strandWidth * 1.25, pixelSize);
        float travel = 1.0 - smoothstep(0.0, 0.15, cyclicDistance(row, phase));
        warmLayer = max(warmLayer, stitch * (0.22 + travel * (0.45 + 0.55 * accentSignal)));
        whiteLayer = max(whiteLayer, stitch * (1.0 - travel * 0.9));

        float leftKnot = 1.0 - smoothstep(pixelSize * 2.0, pixelSize * 4.5, length(p - a));
        float rightKnot = 1.0 - smoothstep(pixelSize * 2.0, pixelSize * 4.5, length(p - b));
        warmLayer = max(warmLayer, max(leftKnot, rightKnot) * (0.35 + 0.65 * travel));
    }

    float voidEdge = lineMask(abs(ellipse - 1.0) * min(radiusX, radiusY), pixelSize * 0.8, pixelSize);
    whiteLayer = max(whiteLayer, voidEdge * 0.50);

    float grid = 0.0;
    float cellX = abs(frac((p.x - fieldLeft) / max(fieldRight - fieldLeft, 0.001) * 8.0) - 0.5);
    float cellY = abs(frac((p.y - fieldTop) / max(fieldBottom - fieldTop, 0.001) * 4.0) - 0.5);
    grid = max(1.0 - smoothstep(0.496, 0.5, cellX),
               1.0 - smoothstep(0.496, 0.5, cellY));
    grid *= 0.07 * voidMask;

    float borderX = abs(abs(p.x) - aspect * 0.465);
    float borderY = abs(abs(p.y) - 0.465);
    float border = max(lineMask(borderX, pixelSize * 0.7, pixelSize),
                       lineMask(borderY, pixelSize * 0.7, pixelSize));
    border *= (abs(p.x) <= aspect * 0.465 && abs(p.y) <= 0.465) ? 1.0 : 0.0;

    float registration = 0.0;
    float2 corners[4] = {
        float2(-aspect * 0.465, -0.465),
        float2( aspect * 0.465, -0.465),
        float2(-aspect * 0.465,  0.465),
        float2( aspect * 0.465,  0.465)
    };
    [unroll]
    for (int c = 0; c < 4; ++c)
    {
        float2 d = abs(p - corners[c]);
        float crossMark = max(lineMask(d.x, pixelSize * 0.65, pixelSize) * step(d.y, 0.018),
                              lineMask(d.y, pixelSize * 0.65, pixelSize) * step(d.x, 0.018));
        registration = max(registration, crossMark);
    }

    col += coolInk * saturate(grid + border * 0.22 + registration * 0.65);
    col = lerp(col, coolInk, saturate(whiteLayer));
    col = lerp(col, warmInk, saturate(warmLayer));

    float interiorDepth = (1.0 - smoothstep(0.0, 0.98, ellipse)) * 0.016;
    col += coolInk * interiorDepth * (0.25 + 0.75 * quadrature);
    OutputUAV[pixel] = float4(saturate(col), 1.0);
}
