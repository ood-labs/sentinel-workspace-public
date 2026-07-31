#ifndef INTERACTION_LAB_MICRO_LFO_LAYOUT
#define INTERACTION_LAB_MICRO_LFO_LAYOUT

#include "_ui.generated.hlsli"

float4 mlPx(float4 n, float2 R) {
    return float4(n.x * R.x, n.y * R.y, n.z * R.x, n.w * R.y);
}

static const float4 ML_TRACE = float4(0.045, 0.205, 0.515, 0.930);

#endif
