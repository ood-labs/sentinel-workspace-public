// INTER-SPECT OS-terminal shared library (Phase 10d).
//
// Reusable core for the supplier-driven OS-terminal surfaces (os_bar_stack_01,
// os_state_cards_01, os_terminal_chrome_01, os_hero_bar_01). Ported and expanded
// from the two component labs (ascii_loading_bar_component_lab_01,
// verification_state_component_lab_01) so the production surfaces share one
// "flowing ASCII" fill language, chrome vocabulary, brightness tiering, and the
// glyph record-buffer walk defined in docs/design/text-glyph-buffer-contract.md.
//
// CONSUMER CONTRACT (matches _shared/*_common.hlsli convention):
//   - Include the font FIRST, then this file:
//       #include "../_shared/fonts/scientifica_ascii.hlsli"
//       #include "../_shared/os_terminal.hlsli"
//   - The record-walk helpers read the auto-injected data:0 buffer
//     (_Data0[i].code, _Data0_Count). Only include in a pass that has data:0.
//   - All functions are pure (no cbuffer param reads) so any renderer can use them.

#ifndef INTERSPECT_OS_TERMINAL_HLSLI
#define INTERSPECT_OS_TERMINAL_HLSLI

#define OS_GLYPH_MAX 512

#define OS_END      0    // end of buffer
#define OS_FIELD    9    // field separator (within a record)
#define OS_RECORD   10   // record separator (next bar / card / row)
#define OS_SPINNER  1    // spinner marker (text_phrase_renderer convention)

// ----------------------------------------------------------------------------
// Hash
// ----------------------------------------------------------------------------
float osHash11(float p) {
    p = frac(p * 0.1031);
    p *= p + 33.33;
    p *= p + p;
    return frac(p);
}

// ----------------------------------------------------------------------------
// Glyph rasterizer (optional bold smear). Needs the font include already pulled.
// ----------------------------------------------------------------------------
float osGlyphBit(int face, int code, int col, int row, bool bold) {
    if (code < SCIENTIFICA_FIRST || code > SCIENTIFICA_LAST) return 0.0;
    if (col < 0 || col >= SCIENTIFICA_GLYPH_W || row < 0 || row >= SCIENTIFICA_GLYPH_H) return 0.0;
    int bits = scientificaRowForFace(face, code, row);
    float core = (float)((bits >> (7 - col)) & 1);
    if (bold) core = max(core, (float)((bits >> (7 - max(col - 1, 0))) & 1));
    return core;
}

// ----------------------------------------------------------------------------
// Fill / flow style library. The flowing-ASCII motion lives here: each style
// marches its pattern per-cell on floor(t*k). i = cell index in the bar,
// filled = current fill count, t = animated time. ~10 styles (0..9, wraps).
// ----------------------------------------------------------------------------
int osRampChar(int idx) {
    int r = idx - (idx / 10) * 10;
    if (r == 0) return 46;  // .
    if (r == 1) return 58;  // :
    if (r == 2) return 45;  // -
    if (r == 3) return 61;  // =
    if (r == 4) return 43;  // +
    if (r == 5) return 42;  // *
    if (r == 6) return 35;  // #
    if (r == 7) return 37;  // %
    if (r == 8) return 64;  // @
    return 36;              // $
}

int osFillChar(int style, int i, int filled, float t) {
    int s = ((style % 10) + 10) % 10;
    int stepT = (int)floor(t * 9.0);
    if (s == 0) return ((i + stepT) % 7 == 0) ? 42 : 35;          // *### candy
    if (s == 1) return ((i + stepT) % 5 < 2) ? 43 : 61;           // +==+ blocks
    if (s == 2) return ((i + stepT) % 2 == 0) ? 47 : 92;          // /\/\ slashes
    if (s == 3) {                                                  // hex churn
        int h = (int)floor(osHash11((float)i * 17.13 + floor(t * 5.0)) * 16.0);
        return (h < 10) ? (48 + h) : (65 + h - 10);
    }
    if (s == 4) return ((i + stepT) % 4 == 0) ? 33 : 124;         // |!|| candy-stripe
    if (s == 5) return (i == filled - 1) ? 62 : 61;               // ===> arrow head
    if (s == 6) {                                                 // ^-v- waveform
        int k = (i + stepT) % 4;
        if (k == 0) return 94; if (k == 1) return 45; if (k == 2) return 118; return 45;
    }
    if (s == 7) return osRampChar(i + stepT);                     // :-=+*%@$ ramp
    if (s == 8) return ((i + stepT) % 3 == 0) ? 62 : 45;          // ->-> arrows
    return ((i + stepT) % 6 == 0) ? 42 : 126;                     // ~*~ pulse
}

int osEmptyChar(int style, int i, float t) {
    int s = ((style % 10) + 10) % 10;
    if (s == 2) return ((i + (int)floor(t * 4.0)) % 2 == 0) ? 46 : 32;
    if (s == 4) return 58;   // :
    if (s == 5) return 95;   // _
    if (s == 8) return 32;   // (blank track for arrow style)
    return 46;               // . default dotted track
}

// Head char (drawn at the leading edge of the fill).
int osHeadChar(int style) {
    int s = ((style % 10) + 10) % 10;
    return (s == 2 || s == 8) ? 62 : 124;   // > for slash/arrow styles, | otherwise
}

// ----------------------------------------------------------------------------
// Chrome helpers
// ----------------------------------------------------------------------------
// Micro hex-noise cell (dense field). Returns 0 (space) outside a 'lit' cell.
int osMicroChar(int c, int r, float t) {
    float active = step(0.34, osHash11((float)c * 8.31 + (float)r + floor(t * 3.0)));
    if (active < 0.5) return 46;  // .
    int h = (int)floor(osHash11((float)c * 11.2 + (float)r + floor(t * 4.0)) * 16.0);
    return (h < 10) ? (48 + h) : (65 + h - 10);
}

// Border code for a (cols x rows) box at local cell (c,r). 0 if interior.
//   corners -> '+', top/bottom -> '-', left/right -> '|'
int osBorderCode(int c, int r, int cols, int rows) {
    bool top = (r == 0), bot = (r == rows - 1);
    bool lft = (c == 0), rgt = (c == cols - 1);
    if ((top || bot) && (lft || rgt)) return 43;  // +
    if (top || bot) return 45;                     // -
    if (lft || rgt) return 124;                    // |
    return 0;
}

// 3-digit percent readout glyph for digit 0..3 (hundreds/tens/ones/'%').
int osPercentDigit(int pct, int digit) {
    int h = pct / 100;
    int te = (pct / 10) - h * 10;
    int o = pct - (pct / 10) * 10;
    if (digit == 0) return 48 + h;
    if (digit == 1) return 48 + te;
    if (digit == 2) return 48 + o;
    return 37;  // %
}

// ----------------------------------------------------------------------------
// Brightness-tier resolve. Mirrors the labs' tiered render tail. `kind` selects:
//   <=0.99      -> dim grey body      (dimMask)
//   0.72..1.49  -> chrome white       (whiteMask)
//   >=1.20      -> highlight accent    (accentMask)  [fail-red when badMask set]
// Encode "bad/fail" by adding 2.0 to kind upstream; this strips it into badMask.
// g = glyph coverage at this pixel (0/1). All masks are pre-multiplied by g.
// ----------------------------------------------------------------------------
void osResolveTier(float kind, float g,
                   out float dimMask, out float whiteMask,
                   out float accentMask, out float badMask) {
    badMask = step(2.50, kind);
    float k = kind - badMask * 2.0;
    dimMask    = g * saturate(k) * step(k, 0.99);
    whiteMask  = g * saturate(k - 0.72) * step(k, 1.49);
    accentMask = g * saturate(k - 1.20);
}

// Scanline darkening factor for pixel y (matches the labs).
float osScanline(float py, float amount) {
    return 1.0 - amount * 0.16 * step(0.5, frac(py * 0.5));
}

// ----------------------------------------------------------------------------
// Glyph record-buffer walk (data:0). Records split by OS_RECORD (10), fields by
// OS_FIELD (9). Stops at OS_END (0). See text-glyph-buffer-contract.md.
//
// These touch the auto-injected _Data0 / _Data0_Count, which only exist in a pass
// that declares a data:0 input. A consumer that does NOT use the record buffer
// (e.g. a self-contained window/content module with only a texture input) should
// `#define OS_NO_RECORD_BUFFER` before including this file to compile them out.
// Anchors that drive text from the supplier leave the macro undefined (default).
// ----------------------------------------------------------------------------
#ifndef OS_NO_RECORD_BUFFER
int osCellCode(int i) {
    if (i < 0 || i >= (int)_Data0_Count) return OS_END;
    return (int)(_Data0[i].code + 0.5);
}

int osRecordCount() {
    int rec = 1;
    bool any = false;
    [loop]
    for (int i = 0; i < OS_GLYPH_MAX; i++) {
        int code = osCellCode(i);
        if (code == OS_END) break;
        any = true;
        if (code == OS_RECORD) rec++;
    }
    return any ? rec : 0;
}

int osFieldLen(int r, int f) {
    int rec = 0, fld = 0, n = 0;
    [loop]
    for (int i = 0; i < OS_GLYPH_MAX; i++) {
        int code = osCellCode(i);
        if (code == OS_END) break;
        if (code == OS_RECORD) { rec++; fld = 0; continue; }
        if (code == OS_FIELD)  { fld++; continue; }
        if (rec == r && fld == f) n++;
    }
    return n;
}

// ASCII code of column c in record r, field f (0 = space / absent).
int osRecordFieldCode(int r, int f, int c) {
    int rec = 0, fld = 0, col = 0;
    [loop]
    for (int i = 0; i < OS_GLYPH_MAX; i++) {
        int code = osCellCode(i);
        if (code == OS_END) break;
        if (code == OS_RECORD) { rec++; fld = 0; col = 0; continue; }
        if (code == OS_FIELD)  { fld++; col = 0; continue; }
        if (rec == r && fld == f && col == c) return code;
        col++;
    }
    return 0;
}
#endif // OS_NO_RECORD_BUFFER

#endif // INTERSPECT_OS_TERMINAL_HLSLI
