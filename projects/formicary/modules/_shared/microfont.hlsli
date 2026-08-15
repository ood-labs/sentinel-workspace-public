// microfont.hlsli — 5x7 bitmap glyph set. Generic infrastructure, vendored into formicary.
// A plain 5x7 ASCII bitmap table with no creative identity of its own: every readout in this
// show must display real live state, so the plan canvas and the instrument overlay both need
// honest text. One shared table, no per-module duplicates.
//
// Glyph index space: 0-9 = digits, 10-35 = A-Z, 36 '-', 37 '.', 38 '/', 39 ':', 40 '+', 41 '>'
#ifndef FM_MICROFONT_HLSLI
#define FM_MICROFONT_HLSLI

#define MF_DASH  36u
#define MF_DOT   37u
#define MF_SLASH 38u
#define MF_COLON 39u
#define MF_PLUS  40u
#define MF_GT    41u
#define MF_A     10u
#define MF_COUNT 42u

// Row-major, 7 rows per glyph, low 5 bits per row, MSB = leftmost column.
static const uint MF_FONT[42 * 7] = {
    14,17,19,21,25,17,14,   //  0
    4,12,4,4,4,4,14,        //  1
    14,17,1,2,4,8,31,       //  2
    31,2,4,2,1,17,14,       //  3
    2,6,10,18,31,2,2,       //  4
    31,16,30,1,1,17,14,     //  5
    6,8,16,30,17,17,14,     //  6
    31,1,2,4,8,8,8,         //  7
    14,17,17,14,17,17,14,   //  8
    14,17,17,15,1,2,12,     //  9
    14,17,17,31,17,17,17,   //  A
    30,17,17,30,17,17,30,   //  B
    14,17,16,16,16,17,14,   //  C
    28,18,17,17,17,18,28,   //  D
    31,16,16,30,16,16,31,   //  E
    31,16,16,30,16,16,16,   //  F
    14,17,16,23,17,17,15,   //  G
    17,17,17,31,17,17,17,   //  H
    14,4,4,4,4,4,14,        //  I
    7,2,2,2,2,18,12,        //  J
    17,18,20,24,20,18,17,   //  K
    16,16,16,16,16,16,31,   //  L
    17,27,21,21,17,17,17,   //  M
    17,17,25,21,19,17,17,   //  N
    14,17,17,17,17,17,14,   //  O
    30,17,17,30,16,16,16,   //  P
    14,17,17,17,21,18,13,   //  Q
    30,17,17,30,20,18,17,   //  R
    15,16,16,14,1,1,30,     //  S
    31,4,4,4,4,4,4,         //  T
    17,17,17,17,17,17,14,   //  U
    17,17,17,17,17,10,4,    //  V
    17,17,17,21,21,27,17,   //  W
    17,17,10,4,10,17,17,    //  X
    17,17,10,4,4,4,4,       //  Y
    31,1,2,4,8,16,31,       //  Z
    0,0,0,31,0,0,0,         //  -
    0,0,0,0,0,12,12,        //  .
    1,2,2,4,8,8,16,         //  /
    0,12,12,0,12,12,0,      //  :
    0,4,4,31,4,4,0,         //  +
    8,4,2,1,2,4,8           //  >
};

// One glyph. p is glyph-local, (0,0) top-left .. (1,1) bottom-right. Returns 0 or 1.
float mf_glyph(float2 p, uint g)
{
    if (g >= MF_COUNT) return 0.0;
    if (p.x < 0.0 || p.x >= 1.0 || p.y < 0.0 || p.y >= 1.0) return 0.0;
    int cx = (int)(p.x * 5.0);
    int cy = (int)(p.y * 7.0);
    cx = clamp(cx, 0, 4);
    cy = clamp(cy, 0, 6);
    uint row = MF_FONT[g * 7u + (uint)cy];
    return ((row >> (uint)(4 - cx)) & 1u) != 0u ? 1.0 : 0.0;
}

// Glyph strings pack 6 bits per character, 5 characters per uint (chars 0-4 in .x, 5-9 in .y).
uint mf_pack1(uint a, uint b, uint c, uint d, uint e)
{
    return a | (b << 6) | (c << 12) | (d << 18) | (e << 24);
}
uint mf_at(uint2 packed, uint i)
{
    uint w = (i < 5u) ? packed.x : packed.y;
    uint s = (i % 5u) * 6u;
    return (w >> s) & 63u;
}

// Draw a `count`-glyph string. p is string-local, x spans the whole string, y spans glyph height.
float mf_text(float2 p, uint2 packed, uint count)
{
    if (count == 0u || count > 10u) return 0.0;
    if (p.y < 0.0 || p.y >= 1.0) return 0.0;
    float fx = p.x * (float)count;
    if (fx < 0.0 || fx >= (float)count) return 0.0;
    uint idx = (uint)fx;
    // 5 lit columns + 1 column of tracking per cell
    float2 lp = float2(frac(fx) * 1.2, p.y);
    return mf_glyph(lp, mf_at(packed, idx));
}

// Right-aligned unsigned integer with a fixed digit count (leading zeros kept: reads as a tag).
float mf_num(float2 p, uint value, uint digits)
{
    if (digits == 0u || digits > 10u) return 0.0;
    if (p.y < 0.0 || p.y >= 1.0) return 0.0;
    float fx = p.x * (float)digits;
    if (fx < 0.0 || fx >= (float)digits) return 0.0;
    uint idx = (uint)fx;
    uint place = digits - 1u - idx;
    uint div = 1u;
    for (uint k = 0u; k < place; k++) div *= 10u;
    uint d = (value / div) % 10u;
    float2 lp = float2(frac(fx) * 1.2, p.y);
    return mf_glyph(lp, d);
}

#endif // FM_MICROFONT_HLSLI
