// abstract_ribbon: biomorphic poster ribbon made from nearest-curve sampling.

RWTexture2D<float4> OutputUAV : register(u0);

static const float TAU_LOCAL = 6.2831853;

float2 rot2(float2 v, float a)
{
    float s = sin(a);
    float c = cos(a);
    return float2(c * v.x - s * v.y, s * v.x + c * v.y);
}

float2 curvePoint(float a)
{
    float2 q;
    q.x = 0.136 * cos(a) + 0.043 * cos(2.0 * a + 1.15) - 0.017 * sin(3.0 * a);
    q.y = 0.232 * sin(a) - 0.041 * cos(2.0 * a - 0.25) + 0.022 * sin(3.0 * a + 0.6);
    q.x += aperture * 0.035 * sin(a);
    q *= ribbon_scale;
    q = rot2(q, -0.22 + ribbon_tilt);
    return q + float2(-0.045 + center_shift.x, 0.015 + center_shift.y);
}

float curveWidth(float a)
{
    float bottom = smoothstep(-1.0, -0.05, -sin(a));
    float right = smoothstep(0.0, 1.0, cos(a));
    float topThin = smoothstep(0.35, 1.0, sin(a));
    return width_base + 0.040 * bottom + 0.019 * right - 0.015 * topThin;
}

float segDistParam(float2 p, float2 a, float2 b, out float h)
{
    float2 pa = p - a;
    float2 ba = b - a;
    h = saturate(dot(pa, ba) / max(dot(ba, ba), 1e-5));
    return length(pa - ba * h);
}

float3 palette(float a, float nrm, float fold)
{
    float u = frac((a + 3.14159265) / TAU_LOCAL);
    float3 cream = float3(1.00, 0.78, 0.55);
    float3 orange = float3(1.00, 0.42, 0.02);
    float3 magenta = float3(0.86, 0.02, 0.44);
    float3 wine = float3(0.38, 0.06, 0.18);
    float3 mint = float3(0.74, 0.88, 0.76);
    float3 blue = float3(0.04, 0.02, 0.48);

    float3 col = cream;
    col = lerp(col, orange, smoothstep(0.08, 0.28, u) * (1.0 - smoothstep(0.34, 0.48, u)));
    col = lerp(col, magenta, smoothstep(0.22, 0.43, u) * (1.0 - smoothstep(0.62, 0.78, u)));
    col = lerp(col, wine, smoothstep(0.38, 0.57, u) * 0.75);
    col = lerp(col, mint, smoothstep(0.62, 0.82, u) * (1.0 - smoothstep(0.88, 0.99, u)));
    col = lerp(col, blue, fold * 0.95);
    if (palette_mode == 1)
    {
        col = lerp(cream, float3(0.96, 0.18, 0.40), smoothstep(0.15, 0.75, u));
        col = lerp(col, float3(0.05, 0.04, 0.52), fold);
    }
    else if (palette_mode == 2)
    {
        col = lerp(float3(0.92, 0.82, 0.58), float3(0.10, 0.18, 0.55), smoothstep(0.0, 1.0, u));
        col = lerp(col, float3(1.0, 0.45, 0.05), exp(-pow((u - 0.18) * 5.0, 2.0)));
    }

    float edgeLight = smoothstep(0.56, 1.0, abs(nrm));
    col = lerp(col, float3(1.0, 0.92, 0.70), edgeLight * 0.38);
    return col;
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;

    float2 uv = ((float2)pixel + 0.5) / _Resolution.xy;
    float asp = _Resolution.x / _Resolution.y;
    float2 p = (uv - 0.5) * float2(asp, 1.0);

    float tAnim = _Time * motion;
    p += float2(0.004 * sin(tAnim * 0.7 + uv.y * 5.0), 0.003 * sin(tAnim * 0.43 + uv.x * 4.0)) * shimmer;

    float bestD = 999.0;
    float bestA = 0.0;
    float bestH = 0.0;
    float2 bestA0 = 0.0;
    float2 bestA1 = 0.0;

    const int STEPS = 168;
    [loop]
    for (int i = 0; i < STEPS; ++i)
    {
        float a0 = ((float)i / (float)STEPS) * TAU_LOCAL;
        float a1 = ((float)(i + 1) / (float)STEPS) * TAU_LOCAL;
        float2 c0 = curvePoint(a0);
        float2 c1 = curvePoint(a1);
        float h = 0.0;
        float d = segDistParam(p, c0, c1, h);
        if (d < bestD)
        {
            bestD = d;
            bestA = lerp(a0, a1, h);
            bestH = h;
            bestA0 = c0;
            bestA1 = c1;
        }
    }

    float w = curveWidth(bestA) * ribbon_scale;
    float nrm = bestD / max(w, 0.001);
    float mask = 1.0 - smoothstep(0.98, 1.045, nrm);

    float2 tangent = normalize(bestA1 - bestA0 + 1e-5);
    float2 normal = float2(-tangent.y, tangent.x);
    float side = sign(dot(p - lerp(bestA0, bestA1, bestH), normal));
    float signedN = side * nrm;

    float fold = exp(-pow((bestA - 2.58) * 1.45, 2.0)) * smoothstep(-0.75, 0.25, -signedN);
    float3 baseCol = palette(bestA, signedN, fold);

    float ribsCoord = (signedN * 0.5 + 0.5) * rib_count + 0.35 * sin(bestA * 2.0) + tAnim * 0.035;
    float ribs = 1.0 - smoothstep(0.0, rib_width, abs(frac(ribsCoord) - 0.5));
    ribs *= 1.0 - smoothstep(0.93, 1.02, nrm);
    float fineShadow = 0.72 + 0.28 * smoothstep(-0.95, 0.75, signedN);
    float3 col = baseCol * fineShadow;
    col = lerp(col, col * 0.52, ribs * line_strength);

    float rim = smoothstep(0.70, 0.99, nrm);
    col += float3(1.0, 0.78, 0.50) * rim * 0.20;

    float innerBlue = exp(-pow((bestA - 2.75) * 3.0, 2.0)) * (1.0 - smoothstep(0.12, 0.70, signedN));
    col = lerp(col, float3(0.03, 0.02, 0.35), innerBlue * 0.75);

    float lowerGlow = exp(-pow((bestA - 4.65) * 1.3, 2.0)) * (1.0 - smoothstep(0.45, 1.0, nrm));
    col += lowerGlow * float3(1.0, 0.22, 0.02) * 0.32;

    float highlight = exp(-pow(signedN + 0.42, 2.0) * 22.0) * exp(-pow(bestA - 2.05, 2.0) * 1.4);
    col += highlight * float3(0.72, 0.95, 0.90) * 0.42;

    OutputUAV[pixel] = float4(saturate(col) * mask * intensity, saturate(mask));
}
