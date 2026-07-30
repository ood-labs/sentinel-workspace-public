#ifndef AU_HUD_TEXT_HLSLI
#define AU_HUD_TEXT_HLSLI

// AUTOPSIA — typographic layer for the instrument face.
// HLSL has no character literals, so glyphs are addressed by ASCII code.
// Coordinates are in output pixels; glyph cells are 8x11 * scale, advance 7.
//
// Depends ONLY on the shipped Scientifica bitmap font. The full scientific_ui
// kit is deliberately not included: it pulls in viewport-interaction bindings
// that this renderer does not declare, which would fail to compile.
// NOTE: include paths resolve relative to the CONSUMING module directory
// (modules/<name>/), not to this file, so "../_shared/..." is correct here.
#include "../_shared/fonts/scientifica_ascii.hlsli"

float auGlyphBit(int code, int col, int row) {
    if (code < SCIENTIFICA_FIRST || code > SCIENTIFICA_LAST ||
        col < 0 || col >= 8 || row < 0 || row >= 11) return 0.0;
    int bits = scientificaRowForFace(0, code, row);
    return (float)((bits >> (7 - col)) & 1);
}

// bilinear coverage so glyphs stay legible without shimmering
float suiGlyph(float2 pixel, float2 anchorPx, float scalePx, int code, int emphasis) {
    float s = max(scalePx, 1.0);
    float2 local = (pixel - anchorPx) / s - 0.5;
    int2 cell = (int2)floor(local);
    float2 f = frac(local);
    // Single tap. A 4-tap bilinear filter multiplied the font-table lookups by
    // four at every call site and made the shader take minutes to compile.
    return auGlyphBit(code, cell.x, cell.y);
}

float suiDigit(float2 p, float2 anchor, float scale, int value, int digits) {
    float coverage = 0.0;
    int v = max(value, 0);
    [loop] for (int i = 0; i < digits; ++i) {
        int place = 1;
        [loop] for (int k = 0; k < digits - 1 - i; ++k) place *= 10;
        int digit = (v / place) % 10;
        coverage = max(coverage, suiGlyph(p, anchor + float2((float)i * 7.0 * scale, 0.0), scale, 48 + digit, 0));
    }
    return coverage;
}

#define G_SP 32
#define G_MI 45
#define G_DT 46
#define G_SL 47
#define G_CO 58
#define G_0  48
#define G_A  65
#define G_B  66
#define G_C  67
#define G_D  68
#define G_E  69
#define G_F  70
#define G_G  71
#define G_H  72
#define G_I  73
#define G_J  74
#define G_K  75
#define G_L  76
#define G_M  77
#define G_N  78
#define G_O  79
#define G_P  80
#define G_Q  81
#define G_R  82
#define G_S  83
#define G_T  84
#define G_U  85
#define G_V  86
#define G_W  87
#define G_X  88
#define G_Y  89
#define G_Z  90

// up to 12 glyphs; pass 0 to terminate early
float auText(float2 p, float2 anchor, float s,
             int c0, int c1, int c2, int c3, int c4, int c5,
             int c6, int c7, int c8, int c9, int c10, int c11) {
    int cs[12] = { c0, c1, c2, c3, c4, c5, c6, c7, c8, c9, c10, c11 };
    float cov = 0.0;
    // [loop], never [unroll]: unrolling replicates the whole font lookup twelve
    // times per label and the shader stops compiling in reasonable time.
    [loop] for (int i = 0; i < 12; ++i) {
        if (cs[i] <= 0) continue;
        cov = max(cov, suiGlyph(p, anchor + float2((float)i * 7.0 * s, 0.0), s, cs[i], 0));
    }
    return cov;
}

float auNum(float2 p, float2 anchor, float s, int value, int digits) {
    return suiDigit(p, anchor, s, value, digits);
}

// Signed fixed-point readout: sign, TWO integer digits, point, two decimals.
// One integer digit silently truncated any value >= 10, which made readouts
// lie (an age of 30.98 printed as 0.98).
float auFixed(float2 p, float2 anchor, float s, float value) {
    float cov = 0.0;
    float av = min(abs(value), 99.99);
    int ip = (int)floor(av);
    int fp = (int)floor(frac(av) * 100.0 + 0.5);
    if (fp >= 100) { fp = 0; ip += 1; }
    cov = max(cov, suiGlyph(p, anchor, s, value < 0.0 ? G_MI : G_SP, 0));
    cov = max(cov, suiDigit(p, anchor + float2(7.0 * s, 0.0), s, ip, 2));
    cov = max(cov, suiGlyph(p, anchor + float2(21.0 * s, 0.0), s, G_DT, 0));
    cov = max(cov, suiDigit(p, anchor + float2(28.0 * s, 0.0), s, fp, 2));
    return cov;
}

#endif
