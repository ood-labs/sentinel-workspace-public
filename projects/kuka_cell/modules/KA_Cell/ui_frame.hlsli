// KA_Cell / ui_frame.hlsli - the canvas frame the drawing (canvas.hlsl) and the type (layout.hlsl)
// share. The strips are layout.hlsli's normalized bounds - the same bounds the state pass hit-tests -
// so a plate, its border and the area a click lands in are one definition at any output extent.
#ifndef KA_UI_FRAME_HLSLI
#define KA_UI_FRAME_HLSLI

float4 kcPlanRect(float2 R) { return float4(KA_X0 * R.x, KA_PY0 * R.y, KA_X1 * R.x, KA_PY1 * R.y); }
float4 kcElevRect(float2 R) { return float4(KA_X0 * R.x, KA_EY0 * R.y, KA_X1 * R.x, KA_EY1 * R.y); }
float4 kcInspRect(float2 R) { return float4(KA_IX0 * R.x, KA_IY0 * R.y, KA_IX1 * R.x, KA_IY1 * R.y); }

#endif
