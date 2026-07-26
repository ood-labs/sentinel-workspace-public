#ifndef SPLINE_DESK_LAYOUT_HLSLI
#define SPLINE_DESK_LAYOUT_HLSLI

// Toolbar rects come from _ui.generated.hlsli -- the host's own hit rectangles --
// so the drawn control and the clickable region cannot disagree. Everything else
// is derived from them.
//
// Knot coordinates stay normalized over the WHOLE panel, exactly as v1 stored
// them, because those coordinates are the durable state and the published data.
// The toolbar and telemetry strips overlay that field rather than insetting it.
#include "../_shared/ui/sui3_core.hlsli"
#include "../_shared/ui/sui3_text.hlsli"
#include "_ui.generated.hlsli"

float4 sdPx(float4 n, float2 R) { return float4(n.x * R.x, n.y * R.y, n.z * R.x, n.w * R.y); }

// Integer text scale from the smaller axis ratio. Same rule as the other v3
// stations; see phase doc Amendment 3 for why height alone is wrong.
float sdTextScale(float2 R) {
    float k = min(R.x / 1280.0, R.y / 720.0);
    return k >= 2.6 ? 3.0 : k >= 1.7 ? 2.0 : 1.0;
}

// A caption is fixed pixels tall inside a normalized gap; drop it rather than
// print it across its neighbour.
bool sdCapFits(float gapPx, float sB) { return gapPx >= 12.0 * sB; }

bool sdHit(float2 p, float4 r) {
    return p.x >= r.x && p.x <= r.z && p.y >= r.y && p.y <= r.w;
}

#endif
