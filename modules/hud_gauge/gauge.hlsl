// hud_gauge — procedural FUI dial system. A small table of gauge instances is
// drawn in one pass: each instance is a stack of concentric rings (solid, dashed,
// tick-marked), an optional value arc, radial spokes, and an inner crosshair.
// A separate "tick-fan" instance draws the big radiating arc of ticks.
//
// Technique: procedural polar chrome, multi-instance. Transport: render node
// (alpha = luminance) for additive compositing. No data ports.

RWTexture2D<float4> OutputUAV : register(u0);

static const float TAU = 6.2831853;
static const float PI  = 3.1415926;

// aspect-corrected distance from centre `c` (both in UV space)
float ringMask(float r, float rr, float w)
{
    return 1.0 - smoothstep(0.0, w, abs(r - rr));
}

// dashed ring: `n` dashes with `duty` fraction lit, phase-rotated
float dashRing(float r, float rr, float w, float ang, float n, float duty, float phase)
{
    float ring = ringMask(r, rr, w);
    float seg = step(frac((ang / TAU) * n + phase), duty);
    return ring * seg;
}

// tick ring: short radial ticks around an annulus
float tickRing(float r, float ang, float r0, float r1, float n, float duty, float phase)
{
    float ann = smoothstep(r0, r0 + 0.002, r) * (1.0 - smoothstep(r1 - 0.002, r1, r));
    float t = step(frac((ang / TAU) * n + phase), duty);
    return ann * t;
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;

    float2 uv = ((float2)pixel + 0.5) / _Resolution.xy;
    float asp = _Resolution.x / _Resolution.y;

    float core = 0.0;   // white-hot detail (bright)
    float body = 0.0;   // main teal linework
    float dim  = 0.0;   // faint fills / secondary

    float spin = _Time * spin_speed;

    // ============================ HERO DIAL (right) ============================
    {
        float2 c = float2(hero_x, hero_y);
        float2 p = (uv - c) * float2(asp, 1.0);
        float r = length(p);
        float ang = atan2(p.y, p.x);
        float R = hero_radius;

        // outer solid bezel + a second thin ring
        body = max(body, ringMask(r, R, 0.0016));
        body = max(body, ringMask(r, R * 0.965, 0.0010));

        // dense outer tick ring
        core = max(core, tickRing(r, ang, R * 0.905, R * 0.955, 90.0, 0.45, spin * 0.2) * 0.9);

        // dashed mid ring (rotating, large gaps)
        body = max(body, dashRing(r, R * 0.86, 0.0016, ang, 12.0, 0.62, -spin * 0.3));

        // value arc — bright partial ring showing `hero_value` (0..1), starts at top
        {
            float a01 = frac((ang - PI * 0.5) / TAU + 1.0);   // 0 at top, CW
            float arc = ringMask(r, R * 0.74, 0.006) * step(a01, hero_value);
            core = max(core, arc);
            // arc backing track (dim full ring)
            dim = max(dim, ringMask(r, R * 0.74, 0.004) * 0.5);
        }

        // signature thick bright arc segment on the outer ring (lower-left wedge)
        {
            float a01 = frac((ang - PI * 0.5) / TAU + 1.0);
            float seg = smoothstep(0.30, 0.33, a01) * (1.0 - smoothstep(0.60, 0.63, a01));
            core = max(core, ringMask(r, R * 0.925, 0.013) * seg);
        }

        // inner tick ring (finer)
        body = max(body, tickRing(r, ang, R * 0.60, R * 0.65, 60.0, 0.4, spin * 0.5) * 0.8);

        // radial spokes (a few long index marks)
        {
            float spoke = step(frac((ang / TAU) * 8.0 + 0.02), 0.03);
            float band = smoothstep(R * 0.30, R * 0.32, r) * (1.0 - smoothstep(R * 0.66, R * 0.68, r));
            body = max(body, spoke * band * 0.8);
        }

        // inner core ring + crosshair
        body = max(body, ringMask(r, R * 0.28, 0.0016));
        {
            float ch = (1.0 - smoothstep(0.0, 0.0012, abs(p.y))) * step(r, R * 0.24)
                     + (1.0 - smoothstep(0.0, 0.0012, abs(p.x))) * step(r, R * 0.24);
            dim = max(dim, saturate(ch) * 0.6);
        }
        // hot centre dot
        core = max(core, (1.0 - smoothstep(0.0, R * 0.02, r)));

        // faint inner disc fill
        dim = max(dim, (1.0 - smoothstep(R * 0.27, R * 0.28, r)) * 0.10);
    }

    // ======================= SECONDARY DIAL (mid-left) ========================
    {
        float2 c = float2(sec_x, sec_y);
        float2 p = (uv - c) * float2(asp, 1.0);
        float r = length(p);
        float ang = atan2(p.y, p.x);
        float R = sec_radius;

        body = max(body, ringMask(r, R, 0.0014));
        core = max(core, tickRing(r, ang, R * 0.86, R * 0.98, 48.0, 0.4, -spin * 0.4) * 0.85);
        // partial value arc
        float a01 = frac((ang - PI * 0.5) / TAU + 1.0);
        core = max(core, ringMask(r, R * 0.66, 0.005) * step(a01, 0.62));
        dim  = max(dim, ringMask(r, R * 0.66, 0.004) * 0.4);
        body = max(body, ringMask(r, R * 0.40, 0.0012));
        core = max(core, (1.0 - smoothstep(0.0, R * 0.03, r)));
    }

    // ===================== TICK-FAN (big arc, bottom-left) ====================
    {
        float2 c = float2(fan_x, fan_y);
        float2 p = (uv - c) * float2(asp, 1.0);
        float r = length(p);
        float ang = atan2(p.y, p.x);
        float R = fan_radius;

        // only draw within an angular wedge (opening toward upper-right)
        float a = ang;                              // -PI..PI
        float inWedge = step(fan_start, a) * step(a, fan_end);

        // long radiating ticks
        float ann = smoothstep(R * 0.80, R * 0.81, r) * (1.0 - smoothstep(R * 0.99, R * 1.0, r));
        float t = step(frac((ang / TAU) * fan_ticks), 0.30);
        body = max(body, ann * t * inWedge);
        // bounding arcs
        core = max(core, ringMask(r, R, 0.0016) * inWedge);
        body = max(body, ringMask(r, R * 0.80, 0.0012) * inWedge);
        // a brighter swept segment (progress indicator)
        float swept = step(fan_start, a) * step(a, lerp(fan_start, fan_end, fan_value));
        core = max(core, ringMask(r, R * 0.90, 0.004) * swept);
    }

    float3 col = body_color * body + body_color * dim * 0.7 + core_color * core;
    col *= intensity;

    float lum = max(col.r, max(col.g, col.b));
    OutputUAV[pixel] = float4(col, saturate(lum));
}
