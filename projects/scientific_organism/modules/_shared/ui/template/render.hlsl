#include "../_shared/ui/sui3_controls.hlsli"
#include "_ui.generated.hlsli"

RWTexture2D<float4> OutputUAV : register(u0);

float4 uiRectPx(float4 normalizedRect, float2 extent) {
    return normalizedRect * float4(extent, extent);
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    if (tid.x >= (uint)_Resolution.x || tid.y >= (uint)_Resolution.y) return;

    float2 extent = _Resolution.xy;
    float2 P = (float2)tid.xy + 0.5;
    float scale = max(1.0, floor(min(extent.x / 960.0, extent.y / 540.0) * 2.0));
    Sui3Theme theme = sui3Theme(SUI3_AMBER);
    float3 color = theme.field;

    float4 panel = float4(18.0, 18.0, extent.x - 18.0, extent.y - 18.0);
    color += theme.well * sui3RectIn(P, panel);
    color += theme.rule * sui3Frame(P, panel);
    color += theme.mid * 0.62 * sui3Brackets(P, panel, 14.0);

    color += theme.ink * sui3TextLong(
        P, float2(panel.x + 20.0, panel.y + 20.0), scale,
        S_S,S_C,S_I,S_E,S_N,S_T,S_I,S_F,S_I,S_C,S_SP,S_U,
        S_I,0,0,0,0,0,0,0,0,0,0,0);

    float4 amountRect = uiRectPx(UI_RECT_AMOUNT, extent);
    float4 enabledRect = uiRectPx(UI_RECT_ENABLED, extent);
    color += theme.dim * sui3Text(
        P, float2(amountRect.x, amountRect.y - 12.0 * scale), scale,
        S_A,S_M,S_O,S_U,S_N,S_T,0,0,0,0,0,0);
    color += sui3Rail(P, amountRect, amount, theme);
    color += theme.dim * sui3Text(
        P, float2(enabledRect.x, enabledRect.y - 12.0 * scale), scale,
        S_E,S_N,S_A,S_B,S_L,S_E,S_D,0,0,0,0,0);
    color += sui3Toggle(P, enabledRect, enabled, theme);

    OutputUAV[tid.xy] = float4(saturate(color), 1.0);
}
