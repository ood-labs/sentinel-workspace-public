#include "../_shared/ui/sui3_controls.hlsli"
#include "layout.hlsli"

RWTexture2D<float4> Out : register(u0);
StructuredBuffer<float4> EnvelopeState : register(t0);

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    if (tid.x >= (uint)_Resolution.x || tid.y >= (uint)_Resolution.y) return;
    float2 R = _Resolution.xy;
    float2 P = (float2)tid.xy + 0.5;
    float k = min(R.x / 640.0, R.y / 260.0);
    float s = k >= 1.7 ? 2.0 : 1.0;

    float3 accent = float3(1.0, 0.42, 0.09);
    float exposureNow = 1.0;
    if (_Data0_Count >= 4u) {
        accent = saturate(float3(_Data0[2].a, _Data0[2].b, _Data0[2].c));
        exposureNow = max(_Data0[0].d, 0.2);
    }
    Sui3Theme T = sui3ThemeExposed(accent, exposureNow);
    float4 state = EnvelopeState[0];
    float valueNow = saturate(state.x);

    float3 col = T.field;
    float pad = 0.055 * R.x;
    col += T.ink * sui3TextLong(P, float2(pad, 0.055*R.y), 2.0*s,
        S_M,S_I,S_C,S_R,S_O,S_SP,S_E,S_N,S_V,S_E,S_L,S_O,
        S_P,S_E,0,0,0,0,0,0,0,0,0,0);
    col += T.dim * sui3Text(P, float2(pad, 0.145*R.y), s,
        S_G,S_A,S_T,S_E,S_SP,S_F,S_O,S_L,S_L,S_O,S_W,0);

    float4 meter = mePx(ME_METER, R);
    if (sui3RectIn(P, meter) > 0.5 || sui3Frame(P, meter) > 0.0) {
        col = lerp(col, float3(0,0,0), sui3RectIn(P, meter));
        col += T.well * sui3RectIn(P, meter);
        col += T.rule * 0.22 * sui3Graticule(P, meter, float2(8.0, 4.0));
        float y = lerp(meter.w - 3.0, meter.y + 3.0, valueNow);
        col += T.mid * 0.18 * sui3RectIn(P, float4(meter.x, y, meter.z, meter.w));
        col += T.ink * sui3HairAt(P.y, y) * sui3RectIn(P, meter);
        col += T.accent * sui3Disc(P, float2(meter.z - 8.0*s, y), 3.0*s);
        col += T.rule * sui3Frame(P, meter);
        col += T.mid * 0.6 * sui3Brackets(P, meter, 14.0*s);
    }
    col += T.accent * sui3Fixed(P,
        float2(meter.z - sui3FixedWidth(s,2) - 5.0*s, meter.y + 5.0*s),
        s, valueNow, 2);

    float4 rGate = mePx(UI_RECT_GATE, R);
    float4 rAttack = mePx(UI_RECT_ATTACK, R);
    float4 rRelease = mePx(UI_RECT_RELEASE, R);

    col += T.dim * sui3Text(P, float2(rGate.x, rGate.y - 12.0*s), s,
        S_G,S_A,S_T,S_E,0,0,0,0,0,0,0,0);
    if (sui3RectIn(P, rGate) > 0.5 || sui3Frame(P, rGate) > 0.0) {
        col = lerp(col, float3(0,0,0), sui3RectIn(P, rGate));
        col += sui3Toggle(P, rGate, gate, T);
    }

    col += T.dim * sui3Text(P, float2(rAttack.x, rAttack.y - 12.0*s), s,
        S_A,S_T,S_T,S_A,S_C,S_K,0,0,0,0,0,0);
    if (sui3RectIn(P, rAttack) > 0.5 || sui3Frame(P, rAttack) > 0.0) {
        col = lerp(col, float3(0,0,0), sui3RectIn(P, rAttack));
        col += sui3Rail(P, rAttack, (attack - 0.01) / 1.99, T);
    }
    col += T.ink * sui3Fixed(P,
        float2(rAttack.x + 5.0*s, rAttack.y + 7.0*s), s, attack, 2);

    col += T.dim * sui3Text(P, float2(rRelease.x, rRelease.y - 12.0*s), s,
        S_R,S_E,S_L,S_E,S_A,S_S,S_E,0,0,0,0,0);
    if (sui3RectIn(P, rRelease) > 0.5 || sui3Frame(P, rRelease) > 0.0) {
        col = lerp(col, float3(0,0,0), sui3RectIn(P, rRelease));
        col += sui3Rail(P, rRelease, (release - 0.01) / 3.99, T);
    }
    col += T.ink * sui3Fixed(P,
        float2(rRelease.x + 5.0*s, rRelease.y + 7.0*s), s, release, 2);

    col += T.rule * 0.7 * sui3Registration(P, R, 12.0*s);
    Out[tid.xy] = float4(saturate(col), 1.0);
}
