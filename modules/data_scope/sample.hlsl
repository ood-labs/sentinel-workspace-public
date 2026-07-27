// One thread per lane. Drains every hop that arrived since the last cook and
// appends one sample per hop to the lane's ring.
//
// The whole reason this is a drain and not a read-the-newest-value is mechanism
// 1: at the default 256-sample hop and 48 kHz the stream produces 187.5 samples
// a second while the graph cooks at ~60 Hz. Sampling once per cook would discard
// two of every three and the time axis would be a fiction.

#include "layout.hlsli"

RWStructuredBuffer<float4> Trace : register(u0);

[numthreads(4, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    uint lane = tid.x;
    if (lane >= DS_LANES) return;

    uint capacity = max(_Data0_HopCapacity, 1u);
    uint latest   = _Data0_Generation;
    uint vcount   = max(_Data0_ValueCount, 1u);
    uint total    = (uint)_Data0_Count;

    float4 A = Trace[dsStateA(lane)];
    uint  cursor   = (uint)max(A.x, 0.0);
    uint  writeIdx = (uint)max(A.y, 0.0);
    float peak     = A.z;
    float hopDt    = A.w;

    uint b0, b1;
    dsLaneRange(lane, vcount, b0, b1);

    float floorDb = min(db_floor, -6.0);
    float value   = Trace[dsStateB(lane)].x;

    uint start = sui3CatchupStart(cursor, latest, capacity);
    uint end   = sui3CatchupEnd(start, latest, capacity);
    float drained = 0.0;

    [loop] for (uint g = start; g <= end; ++g) {
        uint sbase = (g % capacity) * vcount;
        if (sbase + vcount > total) continue;
        // Mel Bands carries no standalone header record, so element zero cannot
        // report the latest generation. Each slot's own counter is the only way
        // to know it holds the generation we think it does.
        if (_Data0[sbase].generation_counter != g) continue;

        uint sr = _Data0[sbase].sample_rate;
        uint hs = _Data0[sbase].hop_size;
        if (sr == 0u || hs == 0u) continue;
        hopDt = (float)hs / (float)sr;

        uint hi = min(b1, vcount - 1u);
        // SUM, not mean. Measured: band 0 carries 0.0116 while band 20 is down
        // at 1e-5, so averaging a 48-band slice divides the few bands that hold
        // the energy by the many that do not, and the high lane lands 40 dB
        // below the floor reading a flat zero. Summing is also what a band
        // level physically is.
        float esum = 0.0;
        [loop] for (uint b = b0; b <= hi; ++b) {
            esum += _Data0[sbase + b].energy;
        }

        // Normalized dB. The strip's own autoscale then works on top of this, so
        // the dB floor sets the window and the autoscale sets the zoom.
        value = saturate((dsSafeDb(esum) - floorDb) / (0.0 - floorDb));

        peak = sui3PeakDecay(peak, value, hopDt, peak_halflife);

        Trace[sui3TraceAt(dsTraceBase(lane), DS_CAP, writeIdx)] =
            float4(value, reference, 0.0, 0.0);
        writeIdx += 1u;
        drained  += 1.0;
    }

    // Even with no new hops the peak must keep falling, or a stopped stream
    // freezes the scale and the plot looks live when it is not.
    if (drained < 0.5) {
        peak = sui3PeakDecay(peak, 0.0, max(_DeltaTime, 0.0), peak_halflife);
    }

    float nShow = (hopDt > 0.0) ? sui3TraceSamples(span_seconds, hopDt, DS_CAP) : 0.0;

    // The decaying peak alone is not enough, and measuring it caught this: with
    // a 4 s half-life and a 3 s span, a loud passage still fully on screen had
    // already decayed the peak below its own samples, so the scale clipped its
    // own history. Measured median column height was 1.000 -- most of the plot
    // pinned flat against the top edge.
    //
    // The scale must cover the window being DISPLAYED. Taking the max over the
    // visible samples guarantees nothing on screen can clip, and keeping the
    // decayed peak as a floor means the scale zooms back in smoothly when the
    // material quietens instead of snapping the moment a peak scrolls off.
    int shown  = (int)min(nShow, (float)DS_CAP);
    int origin = (int)writeIdx - shown;
    float winMax = 0.0;
    [loop] for (int k = 0; k < shown; ++k) {
        int i = origin + k;
        if (i < 0) continue;
        winMax = max(winMax, Trace[sui3TraceAt(dsTraceBase(lane), DS_CAP, (uint)i)].x);
    }
    peak = max(peak, winMax);

    float fs = autoscale
        ? sui3FullScale(peak, reference, 0.08, 1.15)
        : max(fixed_scale, 1e-3);

    Trace[dsStateA(lane)] = float4((float)sui3CatchupNext(latest),
                                   (float)writeIdx, peak, hopDt);
    Trace[dsStateB(lane)] = float4(value, fs, drained, nShow);
}
