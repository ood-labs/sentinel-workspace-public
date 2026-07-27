// One thread per channel. Appends the channel's current parameter value once
// per cook.
//
// No data port, and no `_DataN_*` anywhere in this file. That is the point of
// the module: the trace component works on any scalar, and here the scalar is a
// plain float parameter that something else drives (a control-output
// expression, OSC, a Conductor cue, or a hand on a slider).
//
// One sample per cook, so the sample interval is _DeltaTime. Generation
// catch-up is not exercised and does not need to be: it exists for streams that
// outpace the frame rate.

#include "layout.hlsli"

RWStructuredBuffer<float4> Trace : register(u0);

float stChannel(uint ch) {
    return (ch == 0u) ? ch1 : (ch == 1u) ? ch2 : (ch == 2u) ? ch3 : ch4;
}

[numthreads(4, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    uint ch = tid.x;
    if (ch >= ST_CHANS) return;

    float4 A = Trace[stStateA(ch)];
    uint  writeIdx = (uint)max(A.y, 0.0);
    float peak     = A.z;

    float dt  = max(_DeltaTime, 1e-4);
    float raw = stChannel(ch);

    // Bipolar folds -1..1 into 0..1 around a mid baseline; unipolar plots the
    // magnitude. Either way the stored sample is already in plot space, so the
    // renderer stays a pure drawing pass.
    float value = bipolar ? saturate(raw * 0.5 + 0.5) : saturate(abs(raw));

    peak = sui3PeakDecay(peak, value, dt, peak_halflife);

    Trace[sui3TraceAt(stTraceBase(ch), ST_CAP, writeIdx)] =
        float4(value, 0.0, 0.0, 0.0);
    writeIdx += 1u;

    float nShow = sui3TraceSamples(span_seconds, dt, ST_CAP);

    // Same window-max floor Data Scope needed: the decayed peak is anchored at
    // now while the plot shows history, so on its own it lets the scale fall
    // below its own on-screen samples and clip them.
    int shown  = (int)min(nShow, (float)ST_CAP);
    int origin = (int)writeIdx - shown;
    float winMax = 0.0;
    [loop] for (int k = 0; k < shown; ++k) {
        int i = origin + k;
        if (i < 0) continue;
        winMax = max(winMax, Trace[sui3TraceAt(stTraceBase(ch), ST_CAP, (uint)i)].x);
    }
    peak = max(peak, winMax);

    // A bipolar channel must never autoscale, or the 0.5 baseline stops meaning
    // zero and a centred trace drifts off centre as the signal grows.
    float fs = (autoscale && !bipolar)
        ? sui3FullScale(peak, 0.0, 0.15, 1.15)
        : 1.0;

    Trace[stStateA(ch)] = float4(0.0, (float)writeIdx, peak, dt);
    Trace[stStateB(ch)] = float4(value, fs, 0.0, nShow);
}
