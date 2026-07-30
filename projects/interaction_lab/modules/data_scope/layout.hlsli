// Shared layout for Data Scope. Both passes derive extents from here so the
// sampler's lane count and the renderer's lane rects can never disagree.

#ifndef DATA_SCOPE_LAYOUT_HLSLI
#define DATA_SCOPE_LAYOUT_HLSLI

#include "../_shared/ui/sui3_trace.hlsli"

static const uint DS_LANES  = 3u;
static const uint DS_CAP    = 1024u;
static const uint DS_STRIDE = 1026u;

uint dsStateA(uint lane) { return lane * DS_STRIDE + 0u; }
uint dsStateB(uint lane) { return lane * DS_STRIDE + 1u; }
uint dsTraceBase(uint lane) { return lane * DS_STRIDE + 2u; }

// Mel band ranges per lane, as fractions of value_count. Fractions rather than
// fixed indices because value_count is a property of the stream: hard-coding
// 138 would silently mis-slice the moment a different analyser is wired in.
void dsLaneRange(uint lane, uint valueCount, out uint b0, out uint b1) {
    float n = (float)max(valueCount, 1u);
    float f0 = (lane == 0u) ? 0.00 : (lane == 1u) ? 0.22 : 0.65;
    float f1 = (lane == 0u) ? 0.22 : (lane == 1u) ? 0.65 : 1.00;
    b0 = (uint)floor(f0 * n);
    b1 = (uint)max(floor(f1 * n) - 1.0, (float)b0);
}

// UI unit. Integer and clamped, because the glyph atlas is a bitmap face and a
// fractional scale resamples it into mush at exactly the sizes where the scope's
// numbers most need to stay readable.
float dsUI(float H) { return clamp(floor(H / 300.0), 1.0, 5.0); }

// Type scales and lane rects deliberately live in render.hlsl, not here. They
// need sui3_text's metrics, and this header is included by the sampling pass,
// which must not drag a font table it never draws with into its compile. That
// is the same umbrella-header mistake `au_text.hlsli:9` records.

float dsSafeDb(float amp) { return 20.0 * log10(max(amp, 1e-6)); }

#endif
