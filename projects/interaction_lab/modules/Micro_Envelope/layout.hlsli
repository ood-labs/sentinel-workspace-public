#ifndef INTERACTION_LAB_MICRO_ENVELOPE_LAYOUT
#define INTERACTION_LAB_MICRO_ENVELOPE_LAYOUT
#include "_ui.generated.hlsli"
float4 mePx(float4 n, float2 R) {
    return float4(n.x * R.x, n.y * R.y, n.z * R.x, n.w * R.y);
}
static const float4 ME_METER = float4(0.055, 0.230, 0.455, 0.900);
#endif
