#include "../_shared/ui/sui3_controls.hlsli"
#include "layout.hlsli"

RWTexture2D<float4> Out : register(u0);
StructuredBuffer<float4> Scope : register(t0);

static const uint CAPACITY = 256u;

float scopeSample(int i) {
    int q = (i % (int)CAPACITY + (int)CAPACITY) % (int)CAPACITY;
    return Scope[2u + (uint)q].x;
}

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

    float4 meta = Scope[0];
    float4 ranges = Scope[1];
    float current = ranges.z;
    float lo = ranges.x;
    float hi = ranges.y;
    float center = (lo + hi) * 0.5;
    float halfRange = max((hi - lo) * 0.575, 0.001);
    lo = center - halfRange;
    hi = center + halfRange;

    float3 col = T.field;
    float pad = 0.045 * R.x;
    col += T.ink * sui3Text(P, float2(pad, 0.055 * R.y), 2.0*s,
        S_M,S_I,S_C,S_R,S_O,S_SP,S_S,S_C,S_O,S_P,S_E,0);
    col += T.dim * sui3Text(P, float2(pad, 0.135 * R.y), s,
        S_O,S_N,S_E,S_SP,S_I,S_N,S_P,S_U,S_T,0,0,0);
    col += T.accent * sui3Fixed(P,
        float2(R.x - pad - sui3FixedWidth(s, 2), 0.075 * R.y),
        s, current, 2);

    float4 trace = msPx(MS_TRACE, R);
    if (sui3RectIn(P, trace) > 0.5 || sui3Frame(P, trace) > 0.0) {
        col = lerp(col, float3(0,0,0), sui3RectIn(P, trace));
        col += T.well * sui3RectIn(P, trace);
        col += T.rule * 0.22 * sui3Graticule(P, trace, float2(12.0, 4.0));
        col += T.rule * sui3Frame(P, trace);
        col += T.mid * 0.6 * sui3Brackets(P, trace, 12.0*s);

        if (sui3RectIn(P, trace) > 0.5 && meta.y > 1.0) {
            float u = saturate((P.x - trace.x) / max(trace.z - trace.x, 1.0));
            float shown = min(meta.y, clamp(time_span * 60.0, 2.0, (float)CAPACITY));
            float back = (1.0 - u) * (shown - 1.0);
            float back0 = floor(back);
            float fracBack = frac(back);
            int newest = (int)meta.x - 1;
            float a = scopeSample(newest - (int)back0);
            float b = scopeSample(newest - (int)back0 - 1);
            float v = lerp(a, b, fracBack);
            float norm = saturate((v - lo) / max(hi - lo, 0.0001));
            float y = lerp(trace.w - 3.0, trace.y + 3.0, norm);
            col += T.ink * sui3HairAt(P.y, y);
        }
    }

    float4 rSpan = msPx(UI_RECT_SPAN, R);
    col += T.dim * sui3Text(P, float2(rSpan.x, rSpan.y - 12.0*s), s,
        S_S,S_P,S_A,S_N,0,0,0,0,0,0,0,0);
    if (sui3RectIn(P, rSpan) > 0.5 || sui3Frame(P, rSpan) > 0.0) {
        col = lerp(col, float3(0,0,0), sui3RectIn(P, rSpan));
        col += sui3Rail(P, rSpan, (time_span - 0.5) / 3.5, T);
    }
    col += T.ink * sui3Fixed(P,
        float2(rSpan.x + 5.0*s, rSpan.y + 7.0*s), s, time_span, 2);
    col += T.rule * 0.7 * sui3Registration(P, R, 12.0*s);
    Out[tid.xy] = float4(saturate(col), 1.0);
}
