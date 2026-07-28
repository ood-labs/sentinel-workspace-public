// Topographic Operations Console — sui3 port.
//
// The Canvas is a signal instrument, not a second Properties form. Exact
// shaping remains in Properties; the two surviving rails are the performance
// gestures whose values are coupled directly to the live bus traces below.
#include "../_shared/ui/sui3_controls.hlsli"
#include "_ui.generated.hlsli"

struct SigData {
    float pulse; float sweep; float beat; float slow;
    float terrain; float density; float blue_gain; float accent_gain;
    float nodes_gain; float labels_gain; float palette; float energy;
    float authority; float cue_mode; float master_mix; float phase;
    float marker; float pad0; float pad1; float pad2;
};

StructuredBuffer<SigData> _Tex0 : register(t0);
RWTexture2D<float4> OutputUAV : register(u0);

float4 pxRect(float4 r, float2 R) {
    return float4(r.x * R.x, r.y * R.y, r.z * R.x, r.w * R.y);
}

float laneValue(int lane, SigData d) {
    return lane == 0 ? d.pulse : lane == 1 ? d.sweep
         : lane == 2 ? d.beat  : d.slow;
}

float layerValue(int lane, SigData d) {
    return lane == 0 ? d.blue_gain : lane == 1 ? d.accent_gain
         : lane == 2 ? d.nodes_gain : d.labels_gain;
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    if (tid.x >= (uint)_Resolution.x || tid.y >= (uint)_Resolution.y) return;

    float2 R = _Resolution.xy;
    float2 P = (float2)tid.xy + 0.5;
    float k = min(R.x / 1280.0, R.y / 720.0);
    float sB = k >= 2.6 ? 3.0 : k >= 1.7 ? 2.0 : 1.0;
    float sN = 2.0 * sB;
    float sT = 3.0 * sB;
    float pad = max(12.0, 0.026 * R.x);
    bool compactHeight = R.y < 320.0;

    Sui3Theme T = sui3Theme(SUI3_AMBER);
    SigData d = _Tex0[0];
    float3 col = T.field;

    // Quiet survey field: all chrome is snapped through sui3 primitives.
    col += T.rule * 0.13 * sui3Graticule(P, float4(0.0, 0.0, R.x, R.y), float2(16.0, 9.0));
    col += T.rule * 0.75 * sui3Registration(P, R, 14.0 * sB);

    // Header uses three integer bitmap scales: title, live number, captions.
    if (R.x >= 700.0) {
        col += T.ink * sui3TextLong(P, float2(pad, pad), sT,
            S_T,S_O,S_P,S_O,S_G,S_R,S_A,S_P,S_H,S_I,S_C,S_SP,
            S_O,S_P,S_E,S_R,S_A,S_T,S_I,S_O,S_N,S_S,0,0);
    } else {
        col += T.ink * sui3Text(P, float2(pad, pad), sT,
            S_T,S_O,S_P,S_O,S_G,S_R,S_A,S_P,S_H,S_I,S_C,0);
    }
    if (!compactHeight) {
    col += T.dim * sui3TextLong(P, float2(pad, pad + 36.0 * sB), sB,
        S_S,S_I,S_G,S_N,S_A,S_L,S_SP,S_B,S_U,S_S,S_SP,S_SL,
        S_SP,S_L,S_I,S_V,S_E,S_SP,S_S,S_T,S_A,S_T,S_E,0);
    }

    if (R.x >= 700.0) {
        float energyX = R.x - pad - sui3FixedWidth(sN, 2);
        col += T.accent * sui3Fixed(P, float2(energyX, pad + 2.0 * sB), sN, d.energy, 2);
        col += T.dim * sui3Text(P, float2(energyX, pad + 27.0 * sB), sB,
            S_E,S_N,S_E,S_R,S_G,S_Y,0,0,0,0,0,0);
    }

    float yRule = pad + (compactHeight ? 30.0 : 54.0) * sB;
    col += sui3Rule(P, R, yRule, pad, T);

    // Authority / cue / map status. These are readbacks, edited precisely in
    // Properties; active selections alone receive the accent.
    float statusTop = yRule + 16.0 * sB;
    if (!compactHeight) {
    col += T.dim * sui3Text(P, float2(pad, statusTop), sB,
        S_A,S_U,S_T,S_H,S_O,S_R,S_I,S_T,S_Y,0,0,0);
    col += T.ink * sui3Digits(P, float2(pad + 82.0 * sB, statusTop), sB,
                              (int)round(d.authority), 1);
    col += T.dim * sui3Text(P, float2(pad + 120.0 * sB, statusTop), sB,
        S_C,S_U,S_E,0,0,0,0,0,0,0,0,0);
    col += T.ink * sui3Digits(P, float2(pad + 153.0 * sB, statusTop), sB,
                              (int)round(d.cue_mode), 1);
    col += T.dim * sui3Text(P, float2(pad + 190.0 * sB, statusTop), sB,
        S_T,S_E,S_R,S_R,S_A,S_I,S_N,0,0,0,0,0);
    col += T.ink * sui3Digits(P, float2(pad + 250.0 * sB, statusTop), sB,
                              (int)round(d.terrain), 1);
    col += T.dim * sui3Text(P, float2(pad + 288.0 * sB, statusTop), sB,
        S_N,S_O,S_D,S_E,S_S,0,0,0,0,0,0,0);
    col += T.ink * sui3Digits(P, float2(pad + 337.0 * sB, statusTop), sB,
                              (int)round(d.density), 3);
    }

    // Four live transport lanes. Their marker, trace, and numeric value all
    // derive from the same control-output record.
    float plotTop = compactHeight ? yRule + 12.0 * sB : statusTop + 27.0 * sB;
    float plotBottom = (compactHeight ? 0.55 : 0.59) * R.y;
    float4 plot = float4(pad, plotTop, R.x - pad, plotBottom);
    if (sui3RectIn(P, plot) > 0.5 || sui3Frame(P, plot) > 0.0) {
        col += T.well * sui3RectIn(P, plot);
        col += T.rule * 0.20 * sui3Graticule(P, plot, float2(12.0, 4.0));
        col += T.rule * sui3Frame(P, plot);
        col += T.mid * 0.55 * sui3Brackets(P, plot, 16.0 * sB);
    }

    float laneH = (plot.w - plot.y) * 0.25;
    [loop] for (int lane = 0; lane < 4; ++lane) {
        float v = saturate(laneValue(lane, d));
        float y0 = plot.y + laneH * (float)lane;
        float yc = y0 + laneH * 0.5;
        float phase = d.phase * 6.2831853 + (float)lane * 1.13;
        float u = saturate((P.x - plot.x) / max(plot.z - plot.x, 1.0));
        float wave = sin(u * 18.84956 + phase) * (0.18 + 0.28 * v);
        float yw = yc - wave * laneH;
        float inLane = sui3RectIn(P, float4(plot.x, y0, plot.z, y0 + laneH));
        col += T.mid * (0.38 + 0.18 * v) * sui3HairAt(P.y, yw) * inLane;
        float yLive = lerp(y0 + laneH - 3.0, y0 + 3.0, v);
        col += T.accent * sui3Disc(P, float2(plot.z - 7.0 * sB, yLive), 2.3 * sB);
        col += T.rule * 0.55 * sui3HairAt(P.y, y0) * step(plot.x, P.x) * step(P.x, plot.z);
        col += T.accent * sui3Fixed(P, float2(plot.x + 7.0 * sB, y0 + 4.0 * sB),
                                    sB, v, 2);
    }

    // Resolved layer mix: compact positional meters, not controls.
    float metersTop = plot.w + 18.0 * sB;
    if (!compactHeight) {
    col += T.dim * sui3Text(P, float2(pad, metersTop), sB,
        S_L,S_A,S_Y,S_E,S_R,S_SP,S_M,S_I,S_X,0,0,0);
    float meterY = metersTop + 18.0 * sB;
    float gap = 10.0 * sB;
    float meterW = (R.x - 2.0 * pad - 3.0 * gap) * 0.25;
    [loop] for (int m = 0; m < 4; ++m) {
        float4 mr = float4(pad + (meterW + gap) * (float)m, meterY,
                           pad + (meterW + gap) * (float)m + meterW,
                           meterY + max(14.0 * sB, 0.035 * R.y));
        float mv = saturate(layerValue(m, d) * 0.5);
        col += sui3Rail(P, mr, mv, T);
        col += T.ink * sui3Fixed(P, float2(mr.x + 4.0 * sB, mr.y + 2.0 * sB),
                                 sB, layerValue(m, d), 2);
    }
    }

    // The only Canvas controls: two broad performance gestures with attached
    // live numbers. Host rects are the drawing authority.
    float4 rEnergy = pxRect(UI_RECT_MANUAL_ENERGY, R);
    float4 rSweep = pxRect(UI_RECT_MANUAL_SWEEP, R);
    col += T.dim * sui3Text(P, float2(rEnergy.x, rEnergy.y - 14.0 * sB), sB,
        S_P,S_E,S_R,S_F,S_SP,S_E,S_N,S_E,S_R,S_G,S_Y,0);
    col += T.dim * sui3Text(P, float2(rSweep.x, rSweep.y - 14.0 * sB), sB,
        S_P,S_E,S_R,S_F,S_SP,S_S,S_W,S_E,S_E,S_P,0,0);
    col += sui3Rail(P, rEnergy, manual_energy, T);
    col += sui3Rail(P, rSweep, manual_sweep, T);
    col += T.accent * sui3Fixed(P, float2(rEnergy.z - sui3FixedWidth(sB, 2) - 5.0 * sB,
                                          rEnergy.y + 7.0 * sB), sB, manual_energy, 2);
    col += T.accent * sui3Fixed(P, float2(rSweep.z - sui3FixedWidth(sB, 2) - 5.0 * sB,
                                          rSweep.y + 7.0 * sB), sB, manual_sweep, 2);

    float footY = R.y - pad - 11.0 * sB;
    if (!compactHeight) {
    col += T.dim * sui3TextLong(P, float2(pad, footY), sB,
        S_S,S_E,S_T,S_U,S_P,S_SP,S_I,S_N,S_SP,S_P,S_R,S_O,
        S_P,S_E,S_R,S_T,S_I,S_E,S_S,0,0,0,0,0);
    }

    OutputUAV[tid.xy] = float4(saturate(col), 1.0);
}
