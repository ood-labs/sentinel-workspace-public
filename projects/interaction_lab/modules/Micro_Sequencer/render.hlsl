#include "../_shared/ui/sui3_controls.hlsli"
#include "layout.hlsli"

RWTexture2D<float4> Out : register(u0);
StructuredBuffer<float4> SequenceState : register(t0);

bool enabledAt(int i) {
    if (i == 0) return step_1;
    if (i == 1) return step_2;
    if (i == 2) return step_3;
    if (i == 3) return step_4;
    if (i == 4) return step_5;
    if (i == 5) return step_6;
    if (i == 6) return step_7;
    return step_8;
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    if (tid.x >= (uint)_Resolution.x || tid.y >= (uint)_Resolution.y) return;
    float2 R = _Resolution.xy;
    float2 P = (float2)tid.xy + 0.5;
    float k = min(R.x / 720.0, R.y / 240.0);
    float s = k >= 1.7 ? 2.0 : 1.0;

    float3 accent = float3(1.0, 0.42, 0.09);
    float exposureNow = 1.0;
    if (_Data0_Count >= 4u) {
        accent = saturate(float3(_Data0[2].a, _Data0[2].b, _Data0[2].c));
        exposureNow = max(_Data0[0].d, 0.2);
    }
    Sui3Theme T = sui3ThemeExposed(accent, exposureNow);
    float4 state = SequenceState[0];
    int currentStep = (int)clamp(round(state.z), 0.0, 7.0);

    float3 col = T.field;
    float pad = 0.045 * R.x;
    col += T.ink * sui3TextLong(P, float2(pad, 0.055*R.y), 2.0*s,
        S_M,S_I,S_C,S_R,S_O,S_SP,S_S,S_E,S_Q,S_U,S_E,S_N,
        S_C,S_E,S_R,0,0,0,0,0,0,0,0,0);
    col += T.dim * sui3Text(P, float2(pad, 0.145*R.y), s,
        S_E,S_I,S_G,S_H,S_T,S_SP,S_G,S_A,S_T,S_E,S_S,0);

    float4 rRate = mqPx(UI_RECT_RATE, R);
    col += T.dim * sui3Text(P, float2(rRate.x, rRate.y - 12.0*s), s,
        S_R,S_A,S_T,S_E,0,0,0,0,0,0,0,0);
    if (sui3RectIn(P, rRate) > 0.5 || sui3Frame(P, rRate) > 0.0) {
        col = lerp(col, float3(0,0,0), sui3RectIn(P, rRate));
        col += sui3Rail(P, rRate, (rate - 0.25) / 7.75, T);
    }
    col += T.ink * sui3Fixed(P,
        float2(rRate.x + 5.0*s, rRate.y + 7.0*s), s, rate, 2);

    [unroll] for (int i = 0; i < 8; ++i) {
        float4 cell = mqStepRect(i, R);
        bool on = enabledAt(i);
        if (sui3RectIn(P, cell) > 0.5 || sui3Frame(P, cell) > 0.0) {
            col = lerp(col, float3(0,0,0), sui3RectIn(P, cell));
            col += sui3Toggle(P, cell, on, T);
            if (i == currentStep) {
                col += T.accent * 0.8 * sui3Brackets(P, cell, 18.0*s);
                col += T.accent * sui3RectIn(P,
                    float4(cell.x, cell.y, cell.z, cell.y + 3.0*s));
            }
        }
        col += (i == currentStep ? T.accent : T.dim) * sui3Digits(P,
            float2((cell.x + cell.z)*0.5 - 3.0*s,
                   (cell.y + cell.w)*0.5 - 5.0*s), s, i + 1, 1);
    }

    col += T.dim * sui3Text(P, float2(pad, 0.920*R.y), s,
        S_G,S_A,S_T,S_E,0,0,0,0,0,0,0,0);
    col += (state.y > 0.5 ? T.accent : T.ink) * sui3Fixed(P,
        float2(pad + sui3TextWidth(5, s), 0.920*R.y), s, state.y, 2);
    col += T.rule * 0.7 * sui3Registration(P, R, 12.0*s);
    Out[tid.xy] = float4(saturate(col), 1.0);
}
