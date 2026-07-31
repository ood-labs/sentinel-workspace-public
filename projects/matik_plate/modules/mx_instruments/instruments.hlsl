// mx_instruments / instruments.hlsl — draws every plate cell as the instrument its record
// says it is. This is where the reference's texture lives: grids, bitmap blocks, dot
// matrices, rails, dash strips, halftone ramps, dials, data blocks, chevrons, bar meters,
// cones, tags, targets, traces, spirals and key racks.
//
// Coverage is NOT published here. MX_Composite re-derives which pixels belong to a panel
// from the same Plate records, so there is exactly one authority for where a panel is.
//
// The module is a square generator at plate resolution, so uv IS plate space. No transform.
#include "../_shared/plate.hlsli"
#include "../_shared/microfont.hlsli"

RWTexture2D<float4> OutputUAV : register(u0);
// _Data0 = Plate records from MX_Console.

// One family of parallel lines with constant screen weight. x and period are plate units.
float lineGrid(float x, float period, float w, float px)
{
    if (period <= 1e-6) return 0.0;
    float d = abs(frac(x / period - 0.5) - 0.5) * period;
    return 1.0 - smoothstep(w - px, w + px, d);
}
float ringD(float2 p, float r) { return abs(length(p) - r); }

// Every panel carries a real identifier derived from its own seed, never a fixed caption.
float panelTag(float2 q, float2 hs, float seed, float gh, float px)
{
    uint code = (uint)(mxRnd(seed, 61.0) * 8999.0) + 1000u;
    float gw = gh * 0.72;
    float2 org = -hs + float2(gh * 0.35, gh * 0.35);
    float2 lp = (q - org) / float2(gw * 4.0, gh);
    return mf_num(lp, code, 4u);
}

// ---------------------------------------------------------------- instruments
// q  : plate-space offset from the cell centre
// hs : cell half-extent
// n  : q / hs, so -1..1 inside the cell
// px : one pixel in plate units;  lw : half line width in plate units
float drawInstrument(int k, float2 q, float2 hs, float2 n, PlateRec r, float px, float lw, float t)
{
    float ink = 0.0;
    float span = min(hs.x, hs.y);
    float h0 = mxRnd(r.seed, 11.0);
    float h1 = mxRnd(r.seed, 12.0);
    float h2 = mxRnd(r.seed, 13.0);

    if (k == K_GRID)
    {
        if (h0 < 0.42)
        {
            // True perspective floor plane. This is a compute pass, so fwidth/ddx are not
            // available — the line width comes from the analytic gradient of the projection,
            // which is what keeps receding lines a constant weight instead of aliasing out.
            float horizon = -0.72;
            float sy = n.y;
            if (sy > horizon + 0.03)
            {
                float e = sy - horizon;
                float z = 1.0 / e;
                float wx = n.x * z;
                float fx = 1.4 + h1 * 1.6;
                float fz = 0.55 + h2 * 0.9;
                float pxn = px / max(hs.x, 1e-5);

                float gWX = sqrt(z * z + (wx * wx) / (e * e));
                float dWX = abs(frac(wx * fx) - 0.5) / fx;
                float inkX = 1.0 - smoothstep(0.0, gWX * pxn * 1.6, dWX);

                float dZ = abs(frac(z * fz) - 0.5) / fz;
                float inkZ = 1.0 - smoothstep(0.0, z * z * pxn * 1.6, dZ);

                ink = max(inkX, inkZ) * step(abs(n.x), 0.98) * step(abs(n.y), 0.98);
            }
        }
        else
        {
            float cx = lerp(0.10, 0.26, h1) * span * 2.0;
            float cy = lerp(0.10, 0.26, h2) * span * 2.0;
            ink = max(lineGrid(q.x, cx, lw, px), lineGrid(q.y, cy, lw, px));
        }
    }
    else if (k == K_CHECKER)
    {
        float2 cells = max(floor(hs / (span * lerp(0.16, 0.30, h0))), 2.0);
        float2 c = floor((n * 0.5 + 0.5) * cells);
        float v = mxHash21(c + r.seed * 3.7);
        // four ink levels reads as a printed bitmap rather than a binary checker
        ink = (v < 0.42) ? 0.0 : (v < 0.66 ? 0.30 : (v < 0.87 ? 0.62 : 1.0));
        float2 g = frac((n * 0.5 + 0.5) * cells);
        float gl = min(min(g.x, 1.0 - g.x), min(g.y, 1.0 - g.y));
        ink = max(ink * 0.9, (1.0 - smoothstep(0.0, 0.06, gl)) * 0.22);
    }
    else if (k == K_DOTS)
    {
        float pitch = span * lerp(0.16, 0.30, h0);
        float2 g = (frac(q / pitch + 0.5) - 0.5) * pitch;
        float grad = lerp(1.0, saturate(n.x * 0.5 + 0.5), step(0.5, h1));
        float rad = pitch * lerp(0.16, 0.34, h2) * grad;
        ink = pFill(length(g) - rad, px);
    }
    else if (k == K_RAIL)
    {
        ink = pStroke(q.y, lw, px) * step(abs(n.x), 0.90);
        float cnt = floor(lerp(3.0, 9.0, h0));
        float pitch = (hs.x * 1.8) / cnt;
        float idx = floor((q.x + hs.x * 0.9) / pitch);
        float2 g = float2(q.x + hs.x * 0.9 - (idx + 0.5) * pitch, q.y);
        float rad = min(pitch * 0.30, hs.y * 0.72);
        float knob = mxHash21(float2(idx, r.seed)) < 0.45 ? 1.0 : 0.0;
        float d = length(g) - rad;
        ink = max(ink, lerp(pStroke(d, lw, px), pFill(d, px), knob) * step(abs(n.x), 0.94));
    }
    else if (k == K_DASH)
    {
        float cnt = floor(lerp(6.0, 22.0, h0));
        float pitch = (hs.x * 1.8) / cnt;
        float idx = floor((q.x + hs.x * 0.9) / pitch);
        float on = step(mxHash21(float2(idx, r.seed * 2.3)), lerp(0.35, 0.85, h1));
        float inCell = step(frac((q.x + hs.x * 0.9) / pitch), 0.68);
        ink = on * inCell * step(abs(n.x), 0.9) * step(abs(n.y), 0.62);
    }
    else if (k == K_HALFTONE)
    {
        float ramp = (h0 < 0.5) ? saturate(n.x * 0.5 + 0.5) : saturate(1.0 - length(n) * 0.75);
        float pitch = span * 0.11;
        float2 g = (frac(q / pitch + 0.5) - 0.5) * pitch;
        // real halftone: dot area tracks the ramp
        ink = pFill(length(g) - pitch * 0.48 * ramp, px);
        ink = lerp(ramp, ink, step(0.35, h1));
        ink *= step(abs(n.x), 0.92) * step(abs(n.y), 0.92);
    }
    else if (k == K_DIAL)
    {
        float R = span * 0.72;
        ink = pStroke(ringD(q, R), lw, px);
        float ang = atan2(q.y, q.x);
        float ticks = floor(lerp(12.0, 36.0, h0));
        float ta = frac(ang / 6.2831853 * ticks + 0.5) - 0.5;
        float tickInk = (1.0 - smoothstep(0.0, 0.14, abs(ta))) *
                        step(R * 0.80, length(q)) * step(length(q), R);
        ink = max(ink, tickInk);
        float needle = t * 0.6 + r.phase * 6.2831853;
        ink = max(ink, pStroke(pSeg(q, float2(0, 0), float2(cos(needle), sin(needle)) * R * 0.66), lw, px));
        ink = max(ink, pFill(length(q) - span * 0.10, px));
    }
    else if (k == K_DATA)
    {
        float2 cells = max(floor(hs / (span * 0.115)), 3.0);
        float2 c = floor((n * 0.5 + 0.5) * cells);
        ink = step(0.47, mxHash21(c * 1.7 + r.seed * 5.1));
        // registration blocks, like the reference's data squares
        float2 cq = abs(q) - hs + span * 0.26;
        float box = pBox(cq, float2(span * 0.16, span * 0.16));
        ink = max(ink, pStroke(box, lw * 1.4, px));
        ink *= step(abs(n.x), 0.94) * step(abs(n.y), 0.94);
    }
    else if (k == K_CHEVRON)
    {
        float pitch = span * lerp(0.30, 0.60, h0);
        float sk = (h1 < 0.5) ? 1.0 : -1.0;
        float x = q.x + q.y * sk;
        ink = lineGrid(x, pitch, lw * 1.8, px) * step(abs(n.x), 0.92) * step(abs(n.y), 0.86);
    }
    else if (k == K_BARS)
    {
        float cnt = floor(lerp(4.0, 12.0, h0));
        float pitch = (hs.x * 1.85) / cnt;
        float idx = floor((q.x + hs.x * 0.925) / pitch);
        float hgt = lerp(0.18, 0.95, mxHash21(float2(idx, r.seed * 4.4)));
        float inBar = step(frac((q.x + hs.x * 0.925) / pitch), 0.66);
        ink = inBar * step(n.y, 0.90) * step(0.90 - hgt * 1.8, n.y) * step(abs(n.x), 0.93);
    }
    else if (k == K_CONE)
    {
        // Truncated cone in perspective: converging profile plus real elliptical section
        // rings. Banding on the vertical parameter (the previous attempt) reads as a blurred
        // stripe because a section of a cone is an ellipse, not a horizontal line.
        float topW = lerp(0.20, 0.42, h0), botW = lerp(0.62, 0.95, h1);
        float yy = saturate(n.y * 0.5 + 0.5);
        float w = lerp(topW, botW, yy) * hs.x;
        ink = pStroke(abs(q.x) - w, lw, px) * step(abs(n.y), 0.90);

        float rings = floor(lerp(3.0, 7.0, h2));
        for (float i = 0.0; i <= rings; i += 1.0)
        {
            float f = i / rings;
            float ry = (f * 2.0 - 1.0) * hs.y * 0.90;
            float rw = lerp(topW, botW, f) * hs.x;
            float rh = max(rw * 0.30, px * 2.0);
            float2 e2 = float2(q.x / max(rw, 1e-5), (q.y - ry) / rh);
            float d = (length(e2) - 1.0) * min(rw, rh);
            ink = max(ink, pStroke(d, lw, px));
        }
    }
    else if (k == K_GLYPH)
    {
        float gh = min(hs.y * 1.1, hs.x * 0.34);
        float gw = gh * 0.72;
        if (h0 < 0.22)
        {
            // MATIK — the plate's own mark, placed by a record, not hard-positioned
            uint2 packed = uint2(mf_pack1(22u, 10u, 29u, 18u, 20u), 0u);
            ink = mf_text((q + float2(gw * 2.5, gh * 0.5)) / float2(gw * 5.0, gh), packed, 5u);
        }
        else if (h0 < 0.60)
        {
            uint code = (uint)(mxRnd(r.seed, 71.0) * 89999.0) + 10000u;
            ink = mf_num((q + float2(gw * 2.5, gh * 0.5)) / float2(gw * 5.0, gh), code, 5u);
        }
        else
        {
            uint a = 10u + (uint)(mxRnd(r.seed, 72.0) * 25.9);
            uint b = 10u + (uint)(mxRnd(r.seed, 73.0) * 25.9);
            uint c = 10u + (uint)(mxRnd(r.seed, 74.0) * 25.9);
            uint d = 10u + (uint)(mxRnd(r.seed, 75.0) * 25.9);
            uint2 packed = uint2(mf_pack1(a, b, c, d, 0u), 0u);
            ink = mf_text((q + float2(gw * 2.0, gh * 0.5)) / float2(gw * 4.0, gh), packed, 4u);
        }
    }
    else if (k == K_TARGET)
    {
        float R = span * 0.80;
        float rings = floor(lerp(2.0, 5.0, h0));
        for (float i = 1.0; i <= rings; i += 1.0)
            ink = max(ink, pStroke(ringD(q, R * i / rings), lw, px));
        ink = max(ink, pStroke(q.x, lw, px) * step(abs(q.y), R * 1.12));
        ink = max(ink, pStroke(q.y, lw, px) * step(abs(q.x), R * 1.12));
        ink = max(ink, pFill(length(q) - R * 0.16, px) * step(0.5, h1));
    }
    else if (k == K_WAVE)
    {
        float f1 = lerp(3.0, 11.0, h0), f2 = lerp(1.0, 5.0, h1);
        float y = (sin(n.x * f1 + t * 0.5 + r.phase * 6.28) * 0.55
                 + sin(n.x * f2 - t * 0.3) * 0.35) * hs.y * 0.72;
        ink = pStroke(q.y - y, lw * 1.3, px) * step(abs(n.x), 0.92);
        ink = max(ink, pStroke(q.y, lw * 0.7, px) * step(abs(n.x), 0.92) * 0.35);
    }
    else if (k == K_SPIRAL)
    {
        // nested offset loops — the reference's stacked C-shaped coil family
        float loops = floor(lerp(4.0, 9.0, h0));
        float2 dir = normalize(float2(cos(h1 * 6.28), sin(h1 * 6.28)));
        for (float i = 0.0; i < loops; i += 1.0)
        {
            float f = i / max(loops - 1.0, 1.0);
            float R = span * lerp(0.18, 0.86, f);
            float2 c = dir * span * 0.16 * f;
            ink = max(ink, pStroke(ringD(q - c, R), lw, px));
        }
    }
    else // K_KEYS
    {
        float cnt = floor(lerp(4.0, 10.0, h0));
        float pitch = (hs.x * 1.85) / cnt;
        float lx = frac((q.x + hs.x * 0.925) / pitch);
        float body = step(0.12, lx) * step(lx, 0.86) * step(abs(n.y), 0.86) * step(abs(n.x), 0.94);
        // bead column punched OUT of each key — the reference's dotted switch bank reads as
        // dark holes in a light key, not dots painted on top of it
        float beads = floor(lerp(2.0, 6.0, h1));
        float cellH = (hs.y * 1.72) / beads;
        float by = frac((q.y + hs.y * 0.86) / cellH);
        float2 bq = float2((lx - 0.49) * pitch, (by - 0.5) * cellH);
        float bead = pFill(length(bq) - min(pitch * 0.16, cellH * 0.30), px);
        ink = saturate(body * 0.9 - bead * 0.9);
    }

    return saturate(ink);
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 px2 = DTid.xy;
    if (px2.x >= (uint)_Resolution.x || px2.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)px2 + 0.5) / _Resolution.xy;
    float px = 1.0 / _Resolution.x;
    float lw = px * line_weight * 0.5;
    float t = _Time * anim_rate;

    float3 col = float3(0.0, 0.0, 0.0);

    for (uint i = 0u; i < PLATE_CELLS; i++)
    {
        PlateRec r = _Data0[i];
        if (r.role > 0.5 || r.active < 0.5) continue;
        if (r.size.x <= 0.0 || r.size.y <= 0.0) continue;

        float2 q = uv - r.pos;
        float2 pad = r.size + px * 3.0;
        if (abs(q.x) > pad.x || abs(q.y) > pad.y) continue;

        float2 n = q / r.size;
        int k = (int)(r.kind + 0.5);

        // opaque plate first — this is what knocks the wireframe out behind a panel
        float inside = pFill(pBox(q, r.size), px);
        float3 cell = float3(0.0, 0.0, 0.0) + plate_fill * r.tone * 0.5;

        float content = drawInstrument(k, q, r.size, n, r, px, lw, t) * inside;
        float border = pStroke(pBox(q, r.size), lw * border_weight, px);
        float tag = panelTag(q, r.size, r.seed, clamp(min(r.size.x, r.size.y) * 0.34, 0.007, 0.015), px)
                  * inside * step(0.45, mxRnd(r.seed, 91.0)) * tag_opacity;

        float ink = saturate(max(max(content * content_gain, border), tag));
        cell = lerp(cell, float3(1.0, 1.0, 1.0) * ink_level, ink);

        col = lerp(col, cell, saturate(max(inside, border)));
    }

    OutputUAV[px2] = float4(col, 1.0);
}
