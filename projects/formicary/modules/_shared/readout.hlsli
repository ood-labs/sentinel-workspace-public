// readout.hlsli — text primitives shared by every instrument canvas in formicary.
//
// Generic infrastructure with no creative identity: label placement, right-aligned integers and
// a fixed-point field, plus the glyph indices so a caption reads as letters in the source
// instead of as a list of magic numbers. One copy, so a hairline caption in the plan canvas and
// one in the colony canvas are the same size and sit on the same baseline.
#ifndef FM_READOUT_HLSLI
#define FM_READOUT_HLSLI

// Include paths resolve relative to the MODULE PROJECT directory, not to this file, so a
// sibling in _shared/ still has to be reached as ../_shared/. Every module in this show sits at
// modules/<name>/, so one spelling works from all of them.
#include "../_shared/microfont.hlsli"

// A=10 ... Z=35, digits 0-9 = 0-9, '-'=36 '.'=37 '/'=38 ':'=39 '+'=40 '>'=41
#define GA 10u
#define GB 11u
#define GC 12u
#define GD 13u
#define GE 14u
#define GF 15u
#define GG 16u
#define GH 17u
#define GI 18u
#define GJ 19u
#define GK 20u
#define GL 21u
#define GM 22u
#define GN 23u
#define GO 24u
#define GP 25u
#define GQ 26u
#define GR 27u
#define GS 28u
#define GT 29u
#define GU 30u
#define GV 31u
#define GW 32u
#define GX 33u
#define GY 34u
#define GZ 35u
#define GDASH 36u
#define GDOT  37u
#define GSLSH 38u
#define GCOL  39u
#define GPLUS 40u
#define GGT   41u

// A label anchored at its left edge. `h` is the glyph cell height in pixels; the advance
// includes the font's one column of tracking, so a string's width is predictable and two labels
// stacked in a column line up.
float fmLabel(float2 px, float2 org, float h, uint2 packed, uint count)
{
    float cw = h * (5.0 / 7.0) * 1.2;
    float2 lp = (px - org) / float2(cw * (float)count, h);
    return mf_text(lp, packed, count);
}

float fmLabelW(float h, uint count) { return h * (5.0 / 7.0) * 1.2 * (float)count; }

// A right-aligned fixed-width integer. Leading zeros are kept deliberately: a fixed-width
// reading does not reflow as the value changes, which is what stops a column of live numbers
// twitching sideways while the colony walks.
float fmNumR(float2 px, float2 rightOrg, float h, uint value, uint digits)
{
    float cw = h * (5.0 / 7.0) * 1.2;
    float2 lp = (px - (rightOrg - float2(cw * (float)digits, 0.0))) / float2(cw * (float)digits, h);
    return mf_num(lp, value, digits);
}

// Fixed point, NNN.DD. Built from two integer fields plus a dot so it needs no float
// formatting, and it never loses its decimal point to rounding.
float fmFixed(float2 px, float2 org, float h, float value, uint intDigits)
{
    float cw = h * (5.0 / 7.0) * 1.2;
    float v = max(value, 0.0);
    uint ip = (uint)floor(v);
    uint fp = (uint)floor(frac(v) * 100.0 + 0.5);
    if (fp >= 100u) { fp = 0u; ip += 1u; }

    float m = 0.0;
    m = max(m, mf_num((px - org) / float2(cw * (float)intDigits, h), ip, intDigits));
    float2 dOrg = org + float2(cw * (float)intDigits, 0.0);
    m = max(m, mf_glyph((px - dOrg) / float2(cw, h) * float2(1.2, 1.0), GDOT));
    float2 fOrg = dOrg + float2(cw, 0.0);
    m = max(m, mf_num((px - fOrg) / float2(cw * 2.0, h), fp, 2u));
    return m;
}

float fmFixedW(float h, uint intDigits) { return fmLabelW(h, intDigits + 3u); }

#endif // FM_READOUT_HLSLI
