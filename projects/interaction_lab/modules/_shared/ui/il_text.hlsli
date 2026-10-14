// il_text.hlsli - Interaction Lab kit, layer 1: signed-distance type.
//
// One RGB atlas, three faces (R sans, G bold, B mono), one shared cell grid - see
// tools/il_type.py. A pass that draws text binds the atlas asset and names its slot BEFORE
// including this file:
//
//     #define IL_TYPE_TEX _Tex2          // pass input { slot: 2, source: "asset:type" }
//     #include "../_shared/ui/il_text.hlsli"
//     #include "_labels.generated.hlsli" // optional: this module's kerned labels
//
// Sizes are em sizes in output pixels ("13px type"). Vertical placement uses the CAP MIDLINE:
// `y` is the line the capitals are centred on, so a label sits centred in any row by passing
// the row's centre. Small sizes get a touch of weight (light-on-dark text reads thin).
#ifndef IL_TEXT_HLSLI
#define IL_TEXT_HLSLI

#include "../_shared/ui/il_core.hlsli"
#include "../_shared/ui/il_type_metrics.hlsli"

#ifndef IL_TYPE_TEX
#error define IL_TYPE_TEX (the pass input slot bound to the type atlas asset) before including il_text.hlsli
#endif

#define IL_SANS 0u
#define IL_BOLD 1u
#define IL_MONO 2u

#define IL_LEFT   0u
#define IL_CENTER 1u
#define IL_RIGHT  2u

float ilTypeAdv(uint face, uint g) { return IL_TYPE_ADV[face * IL_TYPE_COUNT + min(g, IL_TYPE_COUNT - 1u)]; }

// Extra weight in screen px for small sizes: +0.22 at 9px fading to 0 by 22px.
float ilTypeBias(float size) { return 0.22 * saturate((22.0 - size) / 13.0); }

// Signed screen distance (px, + outside) from p to glyph g whose pen (baseline-left) is at pen.
float ilGlyphDist(float2 p, float2 pen, float k, uint face, uint g)
{
    float2 q = (p - pen) / k + IL_TYPE_ORIGIN;
    if (any(q < 0.5) || any(q > IL_TYPE_CELL - 0.5)) return 1e4;
    float2 cell = float2((float)(g % IL_TYPE_COLS), (float)(g / IL_TYPE_COLS)) * IL_TYPE_CELL;
    float4 t = IL_TYPE_TEX.SampleLevel(LinearSampler, (cell + q) / IL_TYPE_ATLAS, 0);
    float v = (face == 0u) ? t.r : ((face == 1u) ? t.g : t.b);
    return (0.5 - v) * 2.0 * IL_TYPE_SPREAD * k;
}

float ilCov(float d, float size) { return saturate(0.5 - d + ilTypeBias(size)); }

// Baseline y for a cap-midline y.
float ilBaseline(float midY, float size, uint face) { return midY + 0.5 * IL_TYPE_CAP[face] * size / IL_TYPE_EM; }
float ilCapH(float size) { return IL_TYPE_CAP[0] * size / IL_TYPE_EM; }

// ---------------------------------------------------------------- generated labels
#ifdef IL_LABEL_COUNT
uint  ilLbStart(uint id) { return IL_LB_INFO[id] & 0x3FFFu; }
uint  ilLbLen(uint id)   { return (IL_LB_INFO[id] >> 14) & 0x3Fu; }
uint  ilLbFace(uint id)  { return (IL_LB_INFO[id] >> 20) & 0x3u; }
uint  ilLbChar(uint i)   { return (IL_LB_CHARS[i >> 2] >> ((i & 3u) * 8u)) & 0xFFu; }
float ilLbOff(uint i)    { return (float)((IL_LB_OFFS[i >> 1] >> ((i & 1u) * 16u)) & 0xFFFFu) / 16.0; }

// Advance width of a label in px at em size `size`.
float ilLabelW(uint id, float size) { return ilLbOff(IL_LB_OFF0[id] + ilLbLen(id)) * size / IL_TYPE_EM; }

// Coverage of label `id` with its left edge at x and cap midline at y.
float ilLabelL(float2 p, float x, float y, float size, uint id)
{
    uint n = ilLbLen(id);
    if (n == 0u) return 0.0;
    uint face = ilLbFace(id);
    float k = size / IL_TYPE_EM;
    float base = ilBaseline(y, size, face);
    // reject outside the line band and the label's horizontal extent
    if (p.y < base - (IL_TYPE_ASC[face] + 2.0) * k || p.y > base + (IL_TYPE_DESC[face] + 2.0) * k) return 0.0;
    uint o0 = IL_LB_OFF0[id];
    float lx = (p.x - x) / k;
    if (lx < -IL_TYPE_ORIGIN.x || lx > ilLbOff(o0 + n) + IL_TYPE_CELL.x) return 0.0;
    // binary search: last glyph whose offset <= lx
    uint lo = 0u, hi = n - 1u;
    [loop] for (uint it = 0u; it < 6u && lo < hi; it++)
    {
        uint m = (lo + hi + 1u) >> 1;
        if (ilLbOff(o0 + m) <= lx) lo = m; else hi = m - 1u;
    }
    uint c0 = ilLbStart(id);
    float d = 1e4;
    [unroll] for (int j = -1; j <= 1; j++)
    {
        int gi = (int)lo + j;
        if (gi < 0 || gi >= (int)n) continue;
        float2 pen = float2(x + ilLbOff(o0 + (uint)gi) * k, base);
        d = min(d, ilGlyphDist(p, pen, k, face, ilLbChar(c0 + (uint)gi)));
    }
    return ilCov(d, size);
}

// Aligned: align is IL_LEFT / IL_CENTER / IL_RIGHT about x.
float ilLabel(float2 p, float x, float y, float size, uint id, uint align)
{
    float w = ilLabelW(id, size);
    float x0 = (align == IL_LEFT) ? x : ((align == IL_CENTER) ? x - 0.5 * w : x - w);
    return ilLabelL(p, x0, y, size, id);
}

// Draw only when it fits a span of `room` px; a caption that cannot fit is dropped, never squeezed
// into its neighbours.
bool ilLabelFits(uint id, float size, float room) { return ilLabelW(id, size) <= room; }
#endif

// ---------------------------------------------------------------- numbers (mono, O(1) per pixel)
// A number is described, not stored: ILNum holds the rounded integer and fraction parts and the
// cell layout, and ilNumChar computes the character of any cell directly. No local arrays, so
// nothing forces the compiler to unroll, and each pixel costs the same whatever the value.
struct ILNum {
    uint ip;        // integer part (rounded at the requested decimals)
    uint fp;        // fraction digits as an integer, 0 .. 10^dec - 1
    uint nd;        // integer digit count (>= minInt)
    uint dec;       // decimals
    uint sign;      // 0 none, 1 '-', 2 '+'
    uint n;         // total cells
};

// Rounded once in float, then everything in integers (see ilP10).
ILNum ilFormat(float v, int decimals, int minInt, bool plus)
{
    ILNum r;
    r.dec = (uint)clamp(decimals, 0, 6);
    uint scale = ilP10(r.dec);
    uint q = (uint)min(floor(abs(v) * (float)scale + 0.5), 4294967040.0);
    r.ip = q / scale;
    r.fp = q % scale;
    uint digits = 1u + (r.ip >= 10u ? 1u : 0u) + (r.ip >= 100u ? 1u : 0u) + (r.ip >= 1000u ? 1u : 0u)
                + (r.ip >= 10000u ? 1u : 0u) + (r.ip >= 100000u ? 1u : 0u) + (r.ip >= 1000000u ? 1u : 0u)
                + (r.ip >= 10000000u ? 1u : 0u) + (r.ip >= 100000000u ? 1u : 0u) + (r.ip >= 1000000000u ? 1u : 0u);
    r.nd = max(digits, (uint)max(minInt, 1));
    r.sign = (v < 0.0 && q > 0u) ? 1u : (plus ? 2u : 0u);
    r.n = (r.sign != 0u ? 1u : 0u) + r.nd + (r.dec > 0u ? 1u + r.dec : 0u);
    return r;
}

// ASCII code of cell i.
uint ilNumChar(ILNum s, uint i)
{
    bool sg = s.sign != 0u;
    uint j = (sg && i > 0u) ? i - 1u : i;                 // the cell, counted after any sign
    uint k = (j > s.nd) ? j - s.nd - 1u : 0u;             // the fraction digit
    uint c = (j < s.nd) ? 48u + (s.ip / ilP10(s.nd - 1u - min(j, s.nd - 1u))) % 10u
           : ((j == s.nd) ? 46u : 48u + (s.fp / ilP10(s.dec - 1u - min(k, s.dec - 1u))) % 10u);
    if (sg && i == 0u) c = (s.sign == 1u) ? 45u : 43u;
    return c;
}

float ilNumW(uint cells, float size) { return (float)cells * IL_MONO_ADV * size / IL_TYPE_EM; }

// Coverage of a formatted number, aligned about x, cap midline at y.
float ilNumDraw(float2 p, float x, float y, float size, ILNum s, uint align)
{
    float k = size / IL_TYPE_EM;
    float adv = IL_MONO_ADV * k;
    float w = (float)s.n * adv;
    float x0 = (align == IL_LEFT) ? x : ((align == IL_CENTER) ? x - 0.5 * w : x - w);
    float base = ilBaseline(y, size, IL_MONO);
    if (p.y < base - IL_TYPE_ASC[2] * k || p.y > base + IL_TYPE_DESC[2] * k) return 0.0;
    float lx = p.x - x0;
    if (lx < -adv || lx > w + adv) return 0.0;
    int i = (int)floor(lx / adv);
    float d = 1e4;
    [unroll] for (int j = -1; j <= 1; j++)
    {
        int gi = i + j;
        if (gi < 0 || gi >= (int)s.n) continue;
        uint ch = ilNumChar(s, (uint)gi);
        d = min(d, ilGlyphDist(p, float2(x0 + gi * adv, base), k, IL_MONO, ch - IL_TYPE_FIRST));
    }
    return ilCov(d, size);
}

// Cheap reject before formatting: a per-pixel pass would otherwise format at every pixel.
// 14 cells is wider than any number the kit prints.
bool ilNumNear(float2 p, float x, float y, float size)
{
    float k = size / IL_TYPE_EM;
    float w = 14.0 * IL_MONO_ADV * k;
    return abs(p.y - y) <= IL_TYPE_ASC[2] * k && abs(p.x - x) <= w;
}
float ilNum(float2 p, float x, float y, float size, float v, int decimals, uint align)
{
    if (!ilNumNear(p, x, y, size)) return 0.0;
    return ilNumDraw(p, x, y, size, ilFormat(v, decimals, 1, false), align);
}
float ilNumSigned(float2 p, float x, float y, float size, float v, int decimals, uint align)
{
    if (!ilNumNear(p, x, y, size)) return 0.0;
    return ilNumDraw(p, x, y, size, ilFormat(v, decimals, 1, true), align);
}
float ilInt(float2 p, float x, float y, float size, int v, int minDigits, uint align)
{
    if (!ilNumNear(p, x, y, size)) return 0.0;
    return ilNumDraw(p, x, y, size, ilFormat((float)v, 0, minDigits, false), align);
}

#endif
