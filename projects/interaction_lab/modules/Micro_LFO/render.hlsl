#include "../_shared/ui/sui3_controls.hlsli"
#include "layout.hlsli"

RWTexture2D<float4> Out : register(u0);
StructuredBuffer<float4> LfoState : register(t0);

static const float TAU = 6.28318530718;

float waveBipolar(float p, uint shapeIndex) {
    p = frac(p);
    if (shapeIndex == 0u) return sin(p * TAU);
    if (shapeIndex == 1u) return 1.0 - 4.0 * abs(p - 0.5);
    if (shapeIndex == 2u) return p * 2.0 - 1.0;
    return p < 0.5 ? 1.0 : -1.0;
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    if (tid.x >= (uint)_Resolution.x || tid.y >= (uint)_Resolution.y) return;
    float2 R = _Resolution.xy;
    float2 P = (float2)tid.xy + 0.5;
    float k = min(R.x / 640.0, R.y / 300.0);
    float s = k >= 1.7 ? 2.0 : 1.0;

    float3 accent = float3(1.0, 0.42, 0.09);
    float exposureNow = 1.0;
    if (_Data0_Count >= 4u) {
        accent = saturate(float3(_Data0[2].a, _Data0[2].b, _Data0[2].c));
        exposureNow = max(_Data0[0].d, 0.2);
    }
    Sui3Theme T = sui3ThemeExposed(accent, exposureNow);
    float4 state = LfoState[0];
    float phaseNow = frac(state.x);
    float valueNow = saturate(state.y);
    uint shapeNow = (uint)clamp(round(shape), 0.0, 3.0);

    float3 col = T.field;
    float pad = 0.045 * R.x;
    col += T.ink * sui3Text(P, float2(pad, 0.055 * R.y), 2.0 * s,
        S_M,S_I,S_C,S_R,S_O,S_SP,S_L,S_F,S_O,0,0,0);
    col += T.dim * sui3Text(P, float2(pad, 0.125 * R.y), s,
        S_O,S_N,S_E,S_SP,S_S,S_I,S_G,S_N,S_A,S_L,0,0);

    float4 trace = mlPx(ML_TRACE, R);
    if (sui3RectIn(P, trace) > 0.5 || sui3Frame(P, trace) > 0.0) {
        col = lerp(col, float3(0,0,0), sui3RectIn(P, trace));
        col += T.well * sui3RectIn(P, trace);
        col += T.rule * 0.22 * sui3Graticule(P, trace, float2(8.0, 4.0));
        col += T.rule * sui3Frame(P, trace);
        col += T.mid * 0.6 * sui3Brackets(P, trace, 12.0 * s);
        if (sui3RectIn(P, trace) > 0.5) {
            float u = saturate((P.x - trace.x) / max(trace.z - trace.x, 1.0));
            float p = phaseNow - (1.0 - u) * 2.0;
            float v = 0.5 + 0.5 * waveBipolar(p, shapeNow) * saturate(depth);
            float y = lerp(trace.w - 3.0, trace.y + 3.0, v);
            col += T.ink * sui3HairAt(P.y, y);
            col += T.mid * 0.10 * step(y, P.y);
        }
        // The marker lives a few pixels inside the frame, so evaluate the wave
        // at that exact X. Sampling phaseNow here put the dot ahead of a rising
        // line and behind a falling one.
        float markerX = trace.z - 4.0 * s;
        float markerU = saturate((markerX - trace.x) / max(trace.z - trace.x, 1.0));
        float markerPhase = phaseNow - (1.0 - markerU) * 2.0;
        float markerValue = 0.5 + 0.5 * waveBipolar(markerPhase, shapeNow) * saturate(depth);
        float yHead = lerp(trace.w - 3.0, trace.y + 3.0, markerValue);
        col += T.accent * sui3Disc(P, float2(markerX, yHead), 2.8 * s);
    }
    col += T.accent * sui3Fixed(P,
        float2(trace.z - sui3FixedWidth(s, 2) - 4.0 * s, trace.y + 4.0 * s),
        s, valueNow, 2);

    float4 rRate = mlPx(UI_RECT_RATE, R);
    float4 rDepth = mlPx(UI_RECT_DEPTH, R);
    float4 rShape = mlPx(UI_RECT_SHAPE, R);

    col += T.dim * sui3Text(P, float2(rRate.x, rRate.y - 12.0 * s), s,
        S_R,S_A,S_T,S_E,0,0,0,0,0,0,0,0);
    if (sui3RectIn(P, rRate) > 0.5 || sui3Frame(P, rRate) > 0.0) {
        col = lerp(col, float3(0,0,0), sui3RectIn(P, rRate));
        col += sui3Rail(P, rRate, (rate - 0.02) / 7.98, T);
    }
    col += T.ink * sui3Fixed(P, float2(rRate.x + 5.0*s, rRate.y + 7.0*s), s, rate, 2);

    col += T.dim * sui3Text(P, float2(rDepth.x, rDepth.y - 12.0 * s), s,
        S_D,S_E,S_P,S_T,S_H,0,0,0,0,0,0,0);
    if (sui3RectIn(P, rDepth) > 0.5 || sui3Frame(P, rDepth) > 0.0) {
        col = lerp(col, float3(0,0,0), sui3RectIn(P, rDepth));
        col += sui3Rail(P, rDepth, depth, T);
    }
    col += T.ink * sui3Fixed(P, float2(rDepth.x + 5.0*s, rDepth.y + 7.0*s), s, depth, 2);

    col += T.dim * sui3Text(P, float2(rShape.x, rShape.y - 12.0 * s), s,
        S_S,S_H,S_A,S_P,S_E,0,0,0,0,0,0,0);
    int selected = (int)shapeNow;
    float cellW = (rShape.z - rShape.x) / 4.0;
    [unroll] for (int i = 0; i < 4; ++i) {
        float4 cell = float4(rShape.x + i * cellW, rShape.y,
                             rShape.x + (i + 1) * cellW - 3.0, rShape.w);
        if (sui3RectIn(P, cell) > 0.5 || sui3Frame(P, cell) > 0.0) {
            col = lerp(col, float3(0,0,0), sui3RectIn(P, cell));
            col += sui3BankCell(P, cell, i == selected, T);
        }
        col += (i == selected ? T.accent : T.dim) * sui3Digits(P,
            float2(cell.x + cellW * 0.5 - 3.0*s, cell.y + 7.0*s), s, i, 1);
    }

    col += T.rule * 0.7 * sui3Registration(P, R, 12.0 * s);
    Out[tid.xy] = float4(saturate(col), 1.0);
}
