// plates.hlsli — the printed stock. Every plate is procedural and evaluated in FACE-LATTICE
// coordinates, never in screen space.
//
// WHY THESE ARE FRACTAL. In an endless zoom a plate with one fixed feature size fails at both
// ends: it goes sub-pixel in the deep octaves and one tooth of it fills the frame in the near
// ones. So every plate is a SUM OF NESTED LEVELS at a fixed base size in lattice units, each
// level weighted by whether it is currently resolvable. Flying in makes the next level fade up
// inside the one above it — the newsprint is made of newsprint, the checker of checkers — and
// the plate keeps yielding new detail for the whole fall.
//
// WHAT THIS REPLACES, AND WHY. The obvious approach is to pick the finest resolvable level and
// cross-blend to the next coarser one. Do not. Blending two scales of a HARD pattern superposes
// them, and a checker over a 4x checker is not a checker — it is a moiré rosette. It also pops,
// because the chosen level steps by a whole factor whenever the texel size crosses a power. A
// weighted nest has neither problem: nothing ever switches, coarse levels simply persist and
// fine ones fade up, and every weight is a continuous function of the texel size.
//
// Because the texel size is a function of the octave scale alone, and the octave scales repeat
// exactly every `period`, the fractal detail is periodic too and costs the loop nothing.
#ifndef AXON_PLATES_HLSLI
#define AXON_PLATES_HLSLI

// include paths resolve against the ROOT shader's directory, not this file's, so a shared
// header including a sibling has to spell the path the way its consumers do
#include "../_shared/axon.hlsli"

// How present a level of size h is, given `lod` lattice units per pixel. Continuous, so a level
// fades up as you fall toward it and there is never a switch to hide.
float axLevelW(float h, float lod)
{
    return smoothstep(1.3, 4.5, h / max(lod, 1e-9));
}

// four or five nested levels covers the whole fall: a facet enters sub-pixel and leaves the
// frame a few screen-heights across, which is under 300x of range
#define AX_LEVELS_MAX 5

// ---------------------------------------------------------------------------
// Newsprint. Columns, leading, word runs, headline rows, and the occasional solid block where a
// photograph sits. The nest is strong here — a column of type resolving into columns of type is
// the single most convincing thing in the whole fall.
// ---------------------------------------------------------------------------
float axNewsInk(float2 p, float sd, float lineH)
{
    float colW = lineH * 9.0;
    float ci = floor(p.x / colW);
    float x = p.x - ci * colW;
    float li = floor(p.y / lineH);
    float fy = frac(p.y / lineH);

    // a block of a column is occasionally solid — the halftone photographs and heavy display
    // type. These, plus the gutters, are what distinguish a newspaper scrap from a striped
    // panel once the type is too small to read as type.
    if (ax_h2(float2(ci * 3.7 + sd, floor(li / 11.0) * 5.3)) > 0.87) return 0.74;

    if (x < lineH * 0.55 || x > colW - lineH * 0.55) return 0.0;   // gutters
    if (fy > 0.60) return 0.0;                                     // leading

    float hb = ax_h2(float2(ci * 11.3 + sd, floor(li / 12.0) * 2.9));
    float wordW = (hb > 0.55 && frac(li / 12.0) < 0.17) ? lineH * 2.8 : lineH * 0.95;
    float wi = floor(x / wordW);
    if (ax_h2(float2(wi * 1.7 + ci * 37.0, li + sd)) < 0.17) return 0.0;   // word gap
    if (frac(x / wordW) > 0.82) return 0.0;                                // letter spacing
    return (wordW > lineH * 2.0) ? 1.0 : 0.86;
}

float3 axPlateNews(float2 p, float sd, float3 paperC, float3 inkC, float lod, bool headline, float2 t01)
{
    float3 c = paperC;
    float h = 0.62;
    [loop] for (int n = 0; n < AX_LEVELS_MAX; n++)
    {
        float w = axLevelW(h, lod);
        if (w <= 0.002) break;
        float ink = axNewsInk(p, sd + (float)n * 19.0, h);
        // each level prints INTO the one above it, so the page stays a page rather than turning
        // into a fog of overlaid text
        c = lerp(c, lerp(c, inkC, saturate(ink) * 0.88), w * ((n == 0) ? 1.0 : 0.62));
        h *= 0.1667;
    }
    if (headline)
    {
        // a masthead band across the top of the FACET (t01 is facet-normalized), so the plate
        // reads as a page rather than as a texture swatch
        float band = 1.0 - smoothstep(0.15, 0.19, t01.y);
        float lh = 0.62 * 2.2;
        float bi = axNewsInk(p * float2(0.42, 1.0), sd + 3.0, lh);
        c = lerp(c, lerp(paperC, inkC, saturate(bi)), band * axLevelW(lh, lod));
    }
    return c;
}

// ---------------------------------------------------------------------------
// Houndstooth. A checker whose cells throw a triangular tooth into the neighbour they share the
// +x+y diagonal with, and bite one out along the other — the jagged weave that makes the
// reference's big black-and-white panel read as cloth rather than as a grid.
// ---------------------------------------------------------------------------
float axHoundAt(float2 p, float h)
{
    float2 u = p / h;
    float2 c = floor(u), f = frac(u);
    if (fmod(abs(c.x + c.y), 2.0) < 0.5)
    {
        float d = f.x + f.y;
        return (d < 0.56 || d > 1.44) ? 1.0 : 0.0;
    }
    float e = f.x - f.y;
    return (e < -0.44 || e > 0.44) ? 0.0 : 1.0;
}

float3 axPlateHound(float2 p, float3 a, float3 b, float lod)
{
    float3 c = lerp(a, b, 0.5);
    float h = 0.70;
    [loop] for (int n = 0; n < AX_LEVELS_MAX; n++)
    {
        float w = axLevelW(h, lod);
        if (w <= 0.002) break;
        float3 lev = lerp(a, b, axHoundAt(p, h));
        c = lerp(c, lev, w * ((n == 0) ? 1.0 : 0.45));
        h *= 0.25;
    }
    return c;
}

// ---------------------------------------------------------------------------
// Checkerboard with scattered accent tiles. The reference's floor register is not a clean
// checker — it is a checker with vermilion and newsprint tiles thrown into it.
// ---------------------------------------------------------------------------
float3 axCheckAt(float2 p, float h, float sd, float3 a, float3 b, float3 acc, float3 pap, float density)
{
    float2 c = floor(p / h);
    float3 col = (fmod(abs(c.x + c.y), 2.0) < 0.5) ? a : b;
    float hh = ax_h2(c * float2(3.71, 7.13) + sd);
    if (hh < density * 0.55)  col = acc;
    else if (hh < density)    col = pap;
    return col;
}

float3 axPlateCheck(float2 p, float sd, float3 a, float3 b, float3 acc, float3 pap, float density, float lod)
{
    float3 c = lerp(a, b, 0.5);
    float h = 0.80;
    [loop] for (int n = 0; n < AX_LEVELS_MAX; n++)
    {
        float w = axLevelW(h, lod);
        if (w <= 0.002) break;
        float3 lev = axCheckAt(p, h, sd + (float)n * 23.0, a, b, acc, pap, density);
        c = lerp(c, lev, w * ((n == 0) ? 1.0 : 0.42));
        h *= 0.25;
    }
    return c;
}

// ---------------------------------------------------------------------------
// Fine rules. The reference's striped bars, thickening and thinning down the plate.
// ---------------------------------------------------------------------------
float axStripeAt(float2 p, float h, float sd)
{
    float b = p.y / h;
    return step(frac(b), lerp(0.28, 0.66, ax_h2(float2(floor(b), sd))));
}

float3 axPlateStripe(float2 p, float sd, float3 a, float3 b, float lod)
{
    float3 c = lerp(a, b, 0.45);
    float h = 0.42;
    [loop] for (int n = 0; n < AX_LEVELS_MAX; n++)
    {
        float w = axLevelW(h, lod);
        if (w <= 0.002) break;
        float3 lev = lerp(a, b, axStripeAt(p, h, sd + (float)n * 31.0));
        c = lerp(c, lev, w * ((n == 0) ? 1.0 : 0.40));
        h *= 0.2;
    }
    return c;
}

// ---------------------------------------------------------------------------
// Halftone. Dot size rides a slow gradient across the plate, which is what makes it read as a
// reproduced photograph rather than as a dot pattern.
// ---------------------------------------------------------------------------
float axHalfAt(float2 p, float h, float sd)
{
    float2 f = frac(p / h) - 0.5;
    float grad = 0.5 + 0.5 * sin(p.x * 0.35 / max(h, 1e-4) * 0.12 + sd)
                          * cos(p.y * 0.27 / max(h, 1e-4) * 0.12 - sd * 0.7);
    float r = lerp(0.12, 0.50, saturate(grad));
    return 1.0 - smoothstep(r - 0.10, r + 0.02, length(f));
}

float3 axPlateHalf(float2 p, float sd, float3 pap, float3 ink, float lod)
{
    float3 c = lerp(pap, ink, 0.35);
    float h = 0.50;
    [loop] for (int n = 0; n < AX_LEVELS_MAX; n++)
    {
        float w = axLevelW(h, lod);
        if (w <= 0.002) break;
        float3 lev = lerp(pap, ink, axHalfAt(p, h, sd + (float)n * 17.0));
        c = lerp(c, lev, w * ((n == 0) ? 1.0 : 0.45));
        h *= 0.25;
    }
    return c;
}

// ---------------------------------------------------------------------------
// Heavy bar block — the reference's barcode-ish slabs.
// ---------------------------------------------------------------------------
float axBarsAt(float2 p, float h, float sd)
{
    float b = p.x / h;
    return step(frac(b), lerp(0.22, 0.78, ax_h2(float2(floor(b) * 2.3, sd))));
}

float3 axPlateBars(float2 p, float sd, float3 a, float3 b, float lod)
{
    float3 c = lerp(a, b, 0.4);
    float h = 0.90;
    [loop] for (int n = 0; n < AX_LEVELS_MAX; n++)
    {
        float w = axLevelW(h, lod);
        if (w <= 0.002) break;
        float3 lev = lerp(a, b, axBarsAt(p, h, sd + (float)n * 29.0));
        c = lerp(c, lev, w * ((n == 0) ? 1.0 : 0.40));
        h *= 0.2;
    }
    return c;
}

// ---------------------------------------------------------------------------
// Paint runs. Hashed streaks hanging from a facet's upper edge, in a lifted or knocked-back
// version of the facet's own colour — the reference drips, kept inside the facet so they stay
// periodic and cost nothing outside it.
// ---------------------------------------------------------------------------
float3 axRuns(float3 c, float2 t01, float sd, float amount)
{
    if (amount <= 0.001) return c;
    float lanes = 26.0;
    float li = floor(t01.x * lanes);
    if (ax_h2(float2(li, sd * 3.1)) > amount * 0.34) return c;
    float len = lerp(0.12, 0.92, ax_h2(float2(li * 1.7, sd * 5.3)));
    float w = lerp(0.10, 0.42, ax_h2(float2(li * 2.9, sd * 7.1)));
    float lx = abs(frac(t01.x * lanes) - 0.5) * 2.0;
    if (lx > w) return c;
    float run = 1.0 - smoothstep(len * 0.72, len, 1.0 - t01.y);
    // a bead at the end of the run — the detail that makes it read as wet paint
    float bead = 1.0 - smoothstep(0.0, 0.035, abs((1.0 - t01.y) - len));
    float3 tint = (ax_h2(float2(li * 4.1, sd)) < 0.5) ? float3(0.94, 0.93, 0.90)
                                                      : float3(0.05, 0.05, 0.06);
    return lerp(c, tint, saturate(run * 0.85 + bead * 0.55) * (1.0 - lx / max(w, 1e-3)) * 0.9);
}

// ---------------------------------------------------------------------------
// The dispatcher. `p` is face-lattice coordinates, `t01` the same point normalized to the facet.
// ---------------------------------------------------------------------------
float3 axPlate(int mat, float2 p, float2 t01, float sd, float3 own, float lod, float accent)
{
    float3 paperC = axPal(9);
    float3 whiteC = axPal(10);
    float3 blackC = axPal(7);
    float3 inkC   = lerp(blackC, axPal(8), 0.25);

    if (mat == AX_M_NEWS)   return axPlateNews(p, sd, own, inkC, lod, false, t01);
    if (mat == AX_M_HEAD)   return axPlateNews(p, sd, own, inkC, lod, true, t01);
    if (mat == AX_M_HOUND)  return axPlateHound(p, blackC, whiteC, lod);
    if (mat == AX_M_CHECK)  return axPlateCheck(p, sd, blackC, whiteC, own, paperC, accent, lod);
    if (mat == AX_M_STRIPE) return axPlateStripe(p, sd, blackC, whiteC, lod);
    if (mat == AX_M_HALF)   return axPlateHalf(p, sd, paperC, own, lod);
    if (mat == AX_M_BARS)   return axPlateBars(p, sd, own, blackC, lod);
    return own;   // AX_M_SOLID
}

#endif // AXON_PLATES_HLSLI
