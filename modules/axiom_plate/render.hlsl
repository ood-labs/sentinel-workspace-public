#include "../_shared/anim/anim.hlsli"

StructuredBuffer<float4> PhaseState : register(t0);
RWTexture2D<float4> OutputUAV : register(u0);

float sdBox(float2 p, float2 b)
{
    float2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

float sdSegment(float2 p, float2 a, float2 b)
{
    float2 pa = p - a;
    float2 ba = b - a;
    float h = saturate(dot(pa, ba) / max(dot(ba, ba), 1e-5));
    return length(pa - ba * h);
}

float aaFill(float d, float px)
{
    return smoothstep(px, -px, d);
}

float aaStroke(float d, float width, float px)
{
    return smoothstep(width + px, width - px, abs(d));
}

float hashCell(float2 c)
{
    return frac(sin(dot(c, float2(127.1, 311.7))) * 43758.5453);
}

float3 over(float3 base, float3 ink, float mask)
{
    return lerp(base, ink, saturate(mask));
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;

    float2 uv = ((float2)pixel + 0.5) / _Resolution.xy;
    float aspect = _Resolution.x / max(1.0, _Resolution.y);
    float2 p = (uv - 0.5) * float2(aspect, 1.0) * 2.0;
    p -= (composition_offset - 0.5) * float2(aspect, 1.0) * 1.2;
    float px = 2.0 / max(1.0, _Resolution.y);
    float t = frac(phase + PhaseState[0].x);
    float tau = t * AN_TAU;

    float3 blackInk = float3(0.012, 0.012, 0.011);
    float3 graphite = lerp(blackInk, paper_color, 0.34);
    float3 col = blackInk;

    // Paper aperture: a deliberately cropped, off-register field rather than a
    // diagnostic chart. The three topology modes replace the plate grammar.
    float plateW = topology == 0 ? 1.30 : (topology == 1 ? 1.50 : 1.68);
    float plate = aaFill(sdBox(p - float2(-0.08, 0.00), float2(plateW * 0.5, 0.78)), px);
    col = over(col, paper_color, plate);

    // Primary monoliths. Their motion is phase-locked and completes a full loop.
    float swing = sin(tau) * rupture * 0.11;
    float slabA = aaFill(sdBox(p - float2(-0.51 + swing, -0.04), float2(0.25, 0.68)), px);
    float slabB = aaFill(sdBox(p - float2(0.21 - swing * 0.6, 0.12), float2(0.19, 0.54)), px);
    float slabC = aaFill(sdBox(p - float2(0.63, -0.19 + cos(tau) * rupture * 0.08), float2(0.11, 0.39)), px);
    col = over(col, blackInk, slabA);
    col = over(col, graphite, slabB);
    col = over(col, blackInk, slabC);

    // Interruptions cut bright apertures back through the dark bodies.
    float apertureA = aaFill(sdBox(p - float2(-0.51 + swing, -0.19), float2(0.105, 0.25)), px);
    float apertureB = aaFill(sdBox(p - float2(0.21 - swing * 0.6, 0.25), float2(0.065, 0.18)), px);
    col = over(col, paper_color, apertureA * slabA);
    col = over(col, paper_color, apertureB * slabB);

    // Repeated quantized cells are bounded and intentionally asymmetric.
    int n = clamp(cell_density, 3, 14);
    for (int i = 0; i < 14; ++i)
    {
        if (i >= n) break;
        float fi = (float)i;
        float row = floor(fi / 7.0);
        float column = fmod(fi, 7.0);
        float2 center = float2(-0.92 + column * 0.285, -0.49 + row * 0.86);
        float jitter = (hashCell(float2(column, row + (float)topology)) - 0.5) * rupture * 0.06;
        center.y += jitter + sin(tau + fi * 0.61) * rupture * 0.028;
        float2 halfSize = float2(0.055 + 0.026 * step(0.58, hashCell(float2(fi, 4.0))),
                                 0.045 + 0.020 * step(0.48, hashCell(float2(fi, 9.0))));
        float cell = aaFill(sdBox(p - center, halfSize), px);
        float lightCell = step(0.5, hashCell(float2(fi, 17.0)));
        col = over(col, lerp(graphite, blackInk, lightCell), cell * plate);
    }

    // Concentric reading heads and interrupted circular records.
    float2 head0 = float2(-0.03 + cos(tau) * 0.055 * rupture, -0.11);
    float2 head1 = float2(0.70, 0.40 + sin(tau) * 0.04 * rupture);
    float ring0 = aaStroke(length(p - head0) - 0.27, 0.012 * scan_weight, px);
    float ring1 = aaStroke(length(p - head0) - 0.18, 0.007 * scan_weight, px);
    float ring2 = aaStroke(length(p - head1) - 0.135, 0.009 * scan_weight, px);
    float gate0 = step(-0.76, p.x) * step(p.x, 0.56);
    float gate1 = step(0.38, p.x) * step(p.x, 0.98);
    col = over(col, blackInk, max(ring0, ring1) * gate0 * plate);
    col = over(col, accent_color, ring2 * gate1 * plate * 0.92);

    // Angle-family rails provide meaningful line candidates without becoming a
    // synthetic test card. Mode changes replace the rail family.
    float rail = 0.0;
    if (topology == 0)
    {
        rail = max(aaStroke(sdSegment(p, float2(-1.02, 0.61), float2(0.96, 0.61)), 0.006 * scan_weight, px),
                   aaStroke(sdSegment(p, float2(-0.83, -0.69), float2(0.88, -0.69)), 0.006 * scan_weight, px));
    }
    else if (topology == 1)
    {
        rail = max(aaStroke(sdSegment(p, float2(-1.02, 0.70), float2(0.78, -0.70)), 0.007 * scan_weight, px),
                   aaStroke(sdSegment(p, float2(-0.84, -0.70), float2(0.98, 0.70)), 0.006 * scan_weight, px));
    }
    else
    {
        float sweep = -0.78 + 1.56 * t;
        rail = max(aaStroke(sdSegment(p, float2(sweep, -0.76), float2(sweep, 0.76)), 0.010 * scan_weight, px),
                   aaStroke(sdSegment(p, float2(-1.05, 0.34), float2(0.96, -0.34)), 0.006 * scan_weight, px));
    }
    col = over(col, blackInk, rail * plate);

    // A moving scan shutter reveals a vermilion seam only where it crosses ink.
    float scanX = lerp(-1.06, 0.98, 0.5 - 0.5 * cos(tau));
    float scanner = aaStroke(p.x - scanX, 0.004 + 0.006 * scan_weight, px);
    float seam = scanner * plate * (0.35 + 0.65 * step(0.5, slabA + slabB + slabC));
    col = over(col, accent_color, seam);

    // Fine graphite registration marks and boundary ticks.
    for (int j = 0; j < 11; ++j)
    {
        float y = -0.70 + (float)j * 0.14;
        float tick = aaStroke(sdSegment(p, float2(-1.00, y), float2(-0.94 + 0.025 * (j % 3), y)),
                              0.003, px);
        col = over(col, graphite, tick * plate);
    }

    // Print-like quantization stays restrained and deterministic.
    float grain = hashCell(floor((float2)pixel / max(1.0, 4.0 - graphite_grain * 3.0)));
    col += (grain - 0.5) * graphite_grain * 0.035;
    float vignette = smoothstep(1.25, 0.28, length(p * float2(0.58, 0.92)));
    col *= 0.88 + 0.12 * vignette;

    OutputUAV[pixel] = float4(saturate(col), 1.0);
}
