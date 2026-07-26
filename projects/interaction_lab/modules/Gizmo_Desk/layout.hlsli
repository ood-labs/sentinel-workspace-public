#ifndef GIZMO_DESK_LAYOUT_HLSLI
#define GIZMO_DESK_LAYOUT_HLSLI

// Toolbar rects come from the host's own hit rectangles, so the drawn control
// and the clickable region cannot disagree.
#include "../_shared/ui/sui3_core.hlsli"
#include "../_shared/ui/sui3_text.hlsli"
#include "_ui.generated.hlsli"

float4 gdPx(float4 n, float2 R) { return float4(n.x * R.x, n.y * R.y, n.z * R.x, n.w * R.y); }

// Integer text scale from the smaller axis ratio; see Amendment 3.
float gdTextScale(float2 R) {
    float k = min(R.x / 1280.0, R.y / 720.0);
    return k >= 2.6 ? 3.0 : k >= 1.7 ? 2.0 : 1.0;
}

// A caption is fixed pixels tall in a normalized gap; drop rather than overlap.
// 15 not 12: a glyph run is 11px at scale 1 and a bare 12px gap left the title
// sitting one pixel off the bank frame at 1600x900. The extra 3px is clearance,
// and the caption still drops cleanly on a panel too short to hold it.
bool gdCapFits(float gapPx, float sB) { return gapPx >= 15.0 * sB; }

#endif
