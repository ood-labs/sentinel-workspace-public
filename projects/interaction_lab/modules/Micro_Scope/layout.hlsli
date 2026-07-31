#ifndef INTERACTION_LAB_MICRO_SCOPE_LAYOUT
#define INTERACTION_LAB_MICRO_SCOPE_LAYOUT
#include "_ui.generated.hlsli"
float4 msPx(float4 n, float2 R) {
    return float4(n.x * R.x, n.y * R.y, n.z * R.x, n.w * R.y);
}
static const float4 MS_TRACE = float4(0.045, 0.205, 0.955, 0.700);
#endif
