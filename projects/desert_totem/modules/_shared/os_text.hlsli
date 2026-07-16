// INTER-SPECT OS pixel-space text helpers (ASCII OS build program, 2026-05-29).
//
// Lightweight glyph-blit helpers for modules that place text in PIXEL space rather
// than a strict character grid (slot indices, labels, axis tags, readouts inside
// sub-regions). Complements os_terminal.hlsli's grid-cell text path.
//
// CONTRACT: include the font FIRST, then os_terminal.hlsli, then this file:
//   #include "../_shared/fonts/scientifica_ascii.hlsli"
//   #include "../_shared/os_terminal.hlsli"
//   #include "../_shared/os_text.hlsli"
// All helpers are pure; they return glyph coverage (0/1) at pixel p.

#ifndef INTERSPECT_OS_TEXT_HLSLI
#define INTERSPECT_OS_TEXT_HLSLI

// Single glyph at top-left `anchor`, integer pixel scale `sc`.
float osBlitGlyph(float2 p, float2 anchor, float sc, int face, int code, bool bold) {
    float2 l = (p - anchor) / max(sc, 1.0);
    int gc = (int)floor(l.x), gr = (int)floor(l.y);
    return osGlyphBit(face, code, gc, gr, bold);
}

// Right-aligned zero-padded integer `val` in `ndig` digits; cell pitch = cellW*sc px.
// anchor = top-left of the first (most-significant) digit.
float osBlitInt(float2 p, float2 anchor, float sc, float cellW, int face, int val, int ndig, bool bold) {
    float cov = 0.0;
    int v = max(val, 0);
    [loop]
    for (int i = 0; i < ndig; i++) {
        int place = 1;
        [loop]
        for (int k = 0; k < (ndig - 1 - i); k++) place *= 10;
        int d = (v / place) % 10;
        float2 a = anchor + float2((float)i * cellW * sc, 0.0);
        cov = max(cov, osBlitGlyph(p, a, sc, face, 48 + d, bold));
    }
    return cov;
}

// Hex integer `val` in `ndig` hex digits (uppercase), right-aligned, zero-padded.
float osBlitHex(float2 p, float2 anchor, float sc, float cellW, int face, int val, int ndig, bool bold) {
    float cov = 0.0;
    int v = max(val, 0);
    [loop]
    for (int i = 0; i < ndig; i++) {
        int shift = (ndig - 1 - i) * 4;
        int d = (v >> shift) & 0xF;
        int code = (d < 10) ? (48 + d) : (65 + d - 10);
        float2 a = anchor + float2((float)i * cellW * sc, 0.0);
        cov = max(cov, osBlitGlyph(p, a, sc, face, code, bold));
    }
    return cov;
}

#endif // INTERSPECT_OS_TEXT_HLSLI
