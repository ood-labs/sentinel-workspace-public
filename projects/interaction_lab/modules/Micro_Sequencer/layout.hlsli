#ifndef INTERACTION_LAB_MICRO_SEQUENCER_LAYOUT
#define INTERACTION_LAB_MICRO_SEQUENCER_LAYOUT
#include "_ui.generated.hlsli"
float4 mqPx(float4 n, float2 R) {
    return float4(n.x * R.x, n.y * R.y, n.z * R.x, n.w * R.y);
}
float4 mqStepRect(int i, float2 R) {
    float x0 = 0.045 + (float)i * 0.114;
    return mqPx(float4(x0, 0.470, x0 + 0.100, 0.880), R);
}
#endif
