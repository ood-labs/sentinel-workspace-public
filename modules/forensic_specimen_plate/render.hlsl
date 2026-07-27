RWTexture2D<float4> OutputUAV : register(u0);

float sdSegment(float2 p, float2 a, float2 b)
{
    float2 pa = p - a;
    float2 ba = b - a;
    float h = saturate(dot(pa, ba) / max(dot(ba, ba), 1e-6));
    return length(pa - ba * h);
}

float sdBox2(float2 p, float2 b)
{
    float2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

float lineAA(float d, float width)
{
    float px = 1.5 / max(_Resolution.y, 1.0);
    return 1.0 - smoothstep(width, width + px, d);
}

float ringAA(float d, float radius, float width)
{
    return lineAA(abs(d - radius), width);
}

float cellMask(float2 p, float2 center, float2 size, float angle)
{
    float c = cos(angle);
    float s = sin(angle);
    float2 q = p - center;
    q = float2(c * q.x - s * q.y, s * q.x + c * q.y);
    return 1.0 - smoothstep(-0.005, 0.006, sdBox2(q, size));
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    if (tid.x >= (uint)_Resolution.x || tid.y >= (uint)_Resolution.y) return;

    float2 uv = ((float2)tid.xy + 0.5) / _Resolution.xy;
    float aspect = _Resolution.x / _Resolution.y;
    float2 p = (uv - 0.5) * float2(aspect, 1.0);
    p -= composition_offset * float2(aspect, 1.0);
    p /= max(composition_scale, 0.05);

    float ph = frac(phase + _Time * animation_rate);
    float cycle = ph * 6.28318530718;

    float3 black = float3(0.004, 0.005, 0.005);
    float3 paper = float3(0.82, 0.84, 0.81);
    float3 graphite = float3(0.18, 0.19, 0.18);
    float3 accent = accent_color;
    float3 col = black;

    // Slowly shearing registration field.
    float2 gp = p;
    gp.x += sin(gp.y * 7.0 + cycle) * shear * 0.05;
    float2 gridUv = gp * grid_density;
    float2 gridFootprint = grid_density / max(_Resolution.xy, float2(1.0, 1.0));
    float2 gridCell = abs(frac(gridUv + 0.5) - 0.5) / max(gridFootprint, 1e-5);
    float grid = 1.0 - saturate(min(gridCell.x, gridCell.y));
    col += graphite * grid * grid_gain;

    // Large plate aperture and offset registration rings.
    float apertureR = 0.255 + 0.025 * sin(cycle * 2.0);
    float aperture = 1.0 - smoothstep(apertureR, apertureR + 0.008, length(p * float2(0.93, 1.0)));
    float apertureRing = ringAA(length(p * float2(0.93, 1.0)), apertureR, 0.0025);
    float offsetRing = ringAA(length(p - float2(0.36, -0.16)), 0.115, 0.002);
    col += paper * (apertureRing * 0.9 + offsetRing * 0.55);

    // Rotating occlusion cells produce intentional blobs and corners.
    float cells = 0.0;
    float cellEdges = 0.0;
    [unroll]
    for (int i = 0; i < 9; ++i)
    {
        float fi = (float)i;
        float a = fi * 2.39996323 + cycle * (0.035 + 0.006 * fi);
        float rad = 0.12 + 0.055 * fi;
        float2 center = float2(cos(a), sin(a * 1.13)) * rad;
        center += float2(sin(fi * 4.13), cos(fi * 2.71)) * 0.025;
        float2 size = float2(0.028 + 0.006 * fmod(fi, 3.0), 0.017 + 0.004 * fmod(fi + 1.0, 4.0));
        float ca = cycle * (0.08 + fi * 0.005) + fi * 0.41;

        float c = cos(ca);
        float s = sin(ca);
        float2 q = p - center;
        q = float2(c * q.x - s * q.y, s * q.x + c * q.y);
        float d = sdBox2(q, size);
        cells = max(cells, 1.0 - smoothstep(-0.004, 0.006, d));
        cellEdges = max(cellEdges, lineAA(abs(d), 0.0015));
    }
    col = lerp(col, paper * 0.72, cells * aperture * cell_fill);
    col += paper * cellEdges * 0.7;

    // A constrained family of fracture routes.
    float fractures = 0.0;
    [unroll]
    for (int j = 0; j < 7; ++j)
    {
        float fj = (float)j;
        float y = -0.33 + fj * 0.11;
        float swing = 0.035 * sin(cycle * (0.35 + fj * 0.03) + fj);
        float2 a0 = float2(-0.78, y + swing);
        float2 a1 = float2(-0.22 + 0.035 * sin(fj * 2.0), y + swing);
        float2 a2 = float2(0.05, y + 0.11 * ((j & 1) == 0 ? 1.0 : -1.0) + swing);
        float2 a3 = float2(0.74, a2.y + 0.035 * sin(cycle + fj));
        fractures = max(fractures, lineAA(sdSegment(p, a0, a1), 0.0014));
        fractures = max(fractures, lineAA(sdSegment(p, a1, a2), 0.0014));
        fractures = max(fractures, lineAA(sdSegment(p, a2, a3), 0.0014));
    }
    col += paper * fractures * fracture_gain;

    // Dense barcode islands create bounded line and corner evidence.
    float bars = 0.0;
    float2 bp = p - float2(-0.49, 0.22);
    float barRegion = (1.0 - smoothstep(0.0, 0.008, sdBox2(bp, float2(0.17, 0.095))));
    float barStripe = step(0.52, frac((bp.x + bp.y * 0.12) * 88.0 + ph * 2.0));
    bars = barRegion * barStripe;
    float2 bp2 = p - float2(0.47, 0.25);
    float barRegion2 = 1.0 - smoothstep(0.0, 0.008, sdBox2(bp2, float2(0.13, 0.07)));
    float barStripe2 = step(0.6, frac((bp2.y - bp2.x * 0.18) * 72.0 - ph * 1.5));
    bars = max(bars, barRegion2 * barStripe2);
    col = lerp(col, paper, bars * barcode_gain);

    // Warm scanning event: narrow, sparse, and tied to current phase.
    float scanX = lerp(-0.82, 0.82, ph);
    float scan = lineAA(abs(p.x - scanX), 0.0017);
    float scanWindow = smoothstep(0.52, 0.20, abs(p.y));
    float current = scan * scanWindow * accent_gain;
    col += accent * current;

    // Real registration ticks and central crosshair.
    float ticks = 0.0;
    ticks = max(ticks, lineAA(sdSegment(p, float2(-0.04, 0.0), float2(0.04, 0.0)), 0.0015));
    ticks = max(ticks, lineAA(sdSegment(p, float2(0.0, -0.04), float2(0.0, 0.04)), 0.0015));
    [unroll]
    for (int k = 0; k < 8; ++k)
    {
        float ak = (float)k * 0.78539816339;
        float2 dir = float2(cos(ak), sin(ak));
        ticks = max(ticks, lineAA(sdSegment(p, dir * 0.315, dir * 0.34), 0.0012));
    }
    col += paper * ticks;

    // Hard quantization keeps the image useful to classic CV.
    float luma = dot(col, float3(0.2126, 0.7152, 0.0722));
    float hard = smoothstep(0.11, 0.17, luma);
    col = lerp(col, lerp(black, paper, hard), quantize_strength);
    col += accent * current * (1.0 - quantize_strength * 0.6);

    // Plate boundary and restrained vignette.
    float frame = lineAA(abs(sdBox2(p, float2(0.82, 0.445))), 0.002);
    col += paper * frame * 0.75;
    float vignette = saturate(1.0 - dot(p * float2(0.58, 0.9), p * float2(0.58, 0.9)));
    col *= lerp(0.35, 1.0, vignette);

    OutputUAV[tid.xy] = float4(saturate(col), 1.0);
}
