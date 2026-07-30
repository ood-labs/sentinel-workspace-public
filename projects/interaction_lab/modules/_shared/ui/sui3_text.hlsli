#ifndef SENTINEL_SUI3_TEXT_HLSLI
#define SENTINEL_SUI3_TEXT_HLSLI

// Typographic layer, v3. Derived from the proven `_shared/au_hud/au_text.hlsli`
// rather than from `sui_typography.hlsli`, for three measured reasons:
//
//  1. SINGLE TAP, NOT BILINEAR. A 4-tap filter multiplies font-table lookups at
//     every call site; one tap is both cheaper and sharper on a bitmap face.
//  2. NO SYNTHETIC EDGE WEIGHT. The v1 "grown" bold smears the glyph by
//     max()ing a shifted copy. A bitmap face should be drawn as authored.
//  3. NEVER `[unroll]` A GLYPH LOOP. Unrolling replicates the whole font table
//     per call site and the shader stops compiling in reasonable time.
//
// HLSL has no character literals, so glyphs are addressed by ASCII code.
// Coordinates are output PIXELS. Glyph cells are 8x11 * scale, advance 7.
//
// NOTE: include paths resolve relative to the CONSUMING module directory
// (modules/<name>/), so "../_shared/..." is correct here.
#include "../_shared/fonts/scientifica_ascii.hlsli"

float sui3GlyphBit(int code, int col, int row) {
    if (code < SCIENTIFICA_FIRST || code > SCIENTIFICA_LAST ||
        col < 0 || col >= 8 || row < 0 || row >= 11) return 0.0;
    int bits = scientificaRowForFace(0, code, row);
    return (float)((bits >> (7 - col)) & 1);
}

float sui3Glyph(float2 P, float2 anchorPx, float scalePx, int code) {
    float s = max(scalePx, 1.0);
    float2 local = (P - anchorPx) / s - 0.5;
    int2 cell = (int2)floor(local);
    return sui3GlyphBit(code, cell.x, cell.y);
}

#define S_SP 32
#define S_MI 45
#define S_DT 46
#define S_SL 47
#define S_CO 58
#define S_PC 37
#define S_0  48
#define S_A  65
#define S_B  66
#define S_C  67
#define S_D  68
#define S_E  69
#define S_F  70
#define S_G  71
#define S_H  72
#define S_I  73
#define S_J  74
#define S_K  75
#define S_L  76
#define S_M  77
#define S_N  78
#define S_O  79
#define S_P  80
#define S_Q  81
#define S_R  82
#define S_S  83
#define S_T  84
#define S_U  85
#define S_V  86
#define S_W  87
#define S_X  88
#define S_Y  89
#define S_Z  90

static const float SUI3_ADVANCE = 7.0;

// WHOLE-RUN BOUNDING REJECT.
//
// A text run occupies ONE 11*s-tall row, but without this guard every call site
// evaluates its full glyph loop -- twelve font-table lookups -- for every pixel
// on the panel, including the ~95% of rows the run cannot possibly touch. On a
// desk with twenty-odd labels that is the dominant cost, and it is the same
// class of waste 3A measured as v1 Motion Console's 14.66 ms.
//
// The bounds are deliberately loose. `sui3Glyph` maps P to a cell via
// (P - anchor)/s - 0.5, so a run covers y in [anchor.y + 0.5s, anchor.y + 11.5s)
// and x out to (glyphs*7 + 8.5)*s. Padding to 12 and +9 keeps the reject
// strictly outside every lit pixel: this is an early-out, not a clip, and it
// must never change what the function returns.
bool sui3RunMiss(float2 P, float2 anchor, float s, int glyphs) {
    return P.y < anchor.y || P.y >= anchor.y + 12.0 * s
        || P.x < anchor.x || P.x >= anchor.x + ((float)glyphs * SUI3_ADVANCE + 9.0) * s;
}

// Up to 12 glyphs; pass 0 to terminate early. [loop], never [unroll].
float sui3Text(float2 P, float2 anchor, float s,
               int c0, int c1, int c2, int c3, int c4, int c5,
               int c6, int c7, int c8, int c9, int c10, int c11) {
    if (sui3RunMiss(P, anchor, s, 12)) return 0.0;
    int cs[12] = { c0, c1, c2, c3, c4, c5, c6, c7, c8, c9, c10, c11 };
    float cov = 0.0;
    [loop] for (int i = 0; i < 12; ++i) {
        if (cs[i] <= 0) continue;
        cov = max(cov, sui3Glyph(P, anchor + float2((float)i * SUI3_ADVANCE * s, 0.0), s, cs[i]));
    }
    return cov;
}

// Width in pixels of a label, for right-alignment and gutter maths.
float sui3TextWidth(int count, float s) {
    return (float)max(count, 0) * SUI3_ADVANCE * s;
}

// 24 glyphs as two chained runs. Twelve is short enough that real headings get
// silently truncated -- "STYLE AUTHORITY" printed as "STYLE AUTH" on the first
// Style Authority capture. Chaining beats widening the parameter list because
// the inner loop stays at twelve and the font table is still touched once.
float sui3TextLong(float2 P, float2 anchor, float s,
                   int a0, int a1, int a2, int a3, int a4, int a5,
                   int a6, int a7, int a8, int a9, int a10, int a11,
                   int b0, int b1, int b2, int b3, int b4, int b5,
                   int b6, int b7, int b8, int b9, int b10, int b11) {
    float cov = sui3Text(P, anchor, s, a0,a1,a2,a3,a4,a5,a6,a7,a8,a9,a10,a11);
    float2 second = anchor + float2(12.0 * SUI3_ADVANCE * s, 0.0);
    return max(cov, sui3Text(P, second, s, b0,b1,b2,b3,b4,b5,b6,b7,b8,b9,b10,b11));
}

float sui3Digits(float2 P, float2 anchor, float s, int value, int digits) {
    if (sui3RunMiss(P, anchor, s, digits)) return 0.0;
    float cov = 0.0;
    int v = max(value, 0);
    [loop] for (int i = 0; i < digits; ++i) {
        int place = 1;
        [loop] for (int k = 0; k < digits - 1 - i; ++k) place *= 10;
        int digit = (v / place) % 10;
        cov = max(cov, sui3Glyph(P, anchor + float2((float)i * SUI3_ADVANCE * s, 0.0), s, 48 + digit));
    }
    return cov;
}

// Right-aligned integer: the last digit lands on `rightPx`. Numeric columns that
// do not right-align are unreadable as a column, which is the whole point of a
// readout stack.
float sui3DigitsRight(float2 P, float rightPx, float yPx, float s, int value, int digits) {
    float w = sui3TextWidth(digits, s);
    return sui3Digits(P, float2(rightPx - w, yPx), s, value, digits);
}

// Signed fixed-point: sign, TWO integer digits, point, `dec` decimals.
// TWO integer digits is not cosmetic. `au_text.hlsli:97` records that a single
// integer digit silently truncated any value >= 10, so an age of 30.98 printed
// as 0.98 -- a readout that lies is worse than no readout.
float sui3Fixed(float2 P, float2 anchor, float s, float value, int dec) {
    if (sui3RunMiss(P, anchor, s, 4 + clamp(dec, 1, 3))) return 0.0;
    float cov = 0.0;
    int d = clamp(dec, 1, 3);
    float scale = (d == 1) ? 10.0 : ((d == 2) ? 100.0 : 1000.0);
    float av = min(abs(value), 99.0 + (scale - 1.0) / scale);
    int ip = (int)floor(av);
    int fp = (int)floor(frac(av) * scale + 0.5);
    if ((float)fp >= scale) { fp = 0; ip += 1; }
    cov = max(cov, sui3Glyph(P, anchor, s, value < 0.0 ? S_MI : S_SP));
    cov = max(cov, sui3Digits(P, anchor + float2(SUI3_ADVANCE * s, 0.0), s, ip, 2));
    cov = max(cov, sui3Glyph(P, anchor + float2(3.0 * SUI3_ADVANCE * s, 0.0), s, S_DT));
    cov = max(cov, sui3Digits(P, anchor + float2(4.0 * SUI3_ADVANCE * s, 0.0), s, fp, d));
    return cov;
}

// Width of a sui3Fixed run, so callers can right-align a value column.
float sui3FixedWidth(float s, int dec) {
    return (4.0 + (float)clamp(dec, 1, 3)) * SUI3_ADVANCE * s;
}

#endif
