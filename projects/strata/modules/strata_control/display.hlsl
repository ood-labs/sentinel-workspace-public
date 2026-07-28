// Passive preview for the Strata composition/control bus.
//
// The four plate weights and all exact setup now live only in Properties.
#include "../_shared/ui/sui3_controls.hlsli"

struct Ctrl {
    float seed; float melt; float twist; float marble_warp;
    float spread; float wire_scale; float palette; float blob_mix;
    float marble_mix; float wire_mix; float marks_mix; float feature_enabled;
    float feature_gain; float feature_count; float marker; float pad;
};

StructuredBuffer<Ctrl> _Tex0 : register(t0);
RWTexture2D<float4> OutputUAV : register(u0);

float plateValue(int lane, Ctrl d) {
    return lane == 0 ? d.blob_mix : lane == 1 ? d.marble_mix
         : lane == 2 ? d.wire_mix : d.marks_mix;
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    if (tid.x >= (uint)_Resolution.x || tid.y >= (uint)_Resolution.y) return;

    float2 R = _Resolution.xy;
    float2 P = (float2)tid.xy + 0.5;
    Ctrl d = _Tex0[0];
    Sui3Theme T = sui3Theme(SUI3_AMBER);
    float3 col = T.field;

    col += T.rule * 0.10
         * sui3Graticule(P, float4(0.0, 0.0, R.x, R.y), float2(12.0, 7.0));
    col += T.rule * 0.65 * sui3Registration(P, R, 12.0);
    col += T.ink * sui3TextLong(P, float2(18.0, 18.0), 3.0,
        S_C,S_O,S_M,S_P,S_O,S_S,S_I,S_T,S_I,S_O,S_N,S_SP,
        S_B,S_U,S_S,0,0,0,0,0,0,0,0,0);
    col += T.dim * sui3TextLong(P, float2(18.0, 48.0), 1.0,
        S_P,S_A,S_S,S_S,S_I,S_V,S_E,S_SP,S_SL,S_SP,S_P,S_R,
        S_O,S_P,S_E,S_R,S_T,S_I,S_E,S_S,0,0,0,0);
    col += sui3Rule(P, R, 65.0, 18.0, T);

    float4 plot = float4(18.0, 82.0, R.x - 18.0, 210.0);
    col += T.well * sui3RectIn(P, plot);
    col += T.rule * sui3Frame(P, plot);

    [loop] for (int lane = 0; lane < 4; ++lane) {
        float raw = plateValue(lane, d);
        float value = saturate(raw * 0.5);
        float y = 101.0 + (float)lane * 28.0;
        float x0 = plot.x + 46.0;
        float x1 = plot.z - 48.0;
        float markerX = lerp(x0, x1, value);
        col += T.dim * sui3Digits(P, float2(plot.x + 10.0, y - 5.0), 1.0,
                                  lane + 1, 1);
        col += T.rule * 0.70 * sui3HairAt(P.y, y)
             * step(x0, P.x) * step(P.x, x1);
        col += T.accent * sui3Disc(P, float2(markerX, y), 2.4);
        col += T.ink * sui3Fixed(P, float2(plot.z - 38.0, y - 5.0), 1.0,
                                 raw, 2);
    }

    col += T.dim * sui3TextLong(P, float2(18.0, 238.0), 1.0,
        S_E,S_D,S_I,S_T,S_SP,S_I,S_N,S_SP,S_P,S_R,S_O,S_P,
        S_E,S_R,S_T,S_I,S_E,S_S,0,0,0,0,0,0);
    col += T.accent * sui3Digits(P, float2(R.x - 55.0, 237.0), 1.0,
                                 (int)round(d.feature_count), 3);

    OutputUAV[tid.xy] = float4(saturate(col), 1.0);
}
