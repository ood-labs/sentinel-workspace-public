// Scroll clock.
//
// The view must advance on WALL time, not on events. Driving the right edge
// straight from the newest record would freeze the strip whenever a lane went
// quiet -- and a silent stretch is precisely what you are looking at the view
// to see. So the clock free-runs at `sample_rate` and is re-synced upward
// whenever a newer record appears.
//
// Re-sync upward is immediate, downward only when the clock has RUN AWAY.
//
// Forward-only ratcheting was the first attempt and it is a trap. A free-running
// clock advances through silence while the record timestamps stand still, so
// every quiet stretch leaves it permanently further ahead: measured 134,650,160
// against a newest record of 98,417,920 after some minutes of no signal -- 12.5
// minutes of runaway, with every record off-screen to the left and a view that
// looked identical to a dead detector while the counters climbed.
//
// So a gap larger than one window forces a resync. That still refuses to follow
// the small backwards step of a File-mode restart or a seek (which is what
// forward-only was protecting against, and it stays protected, since those are
// far smaller than a window), while making a stalled or switched source
// self-healing within one window instead of never.

#include "common.hlsli"

StructuredBuffer<HitRec> In : register(t0);
RWStructuredBuffer<float4> Out : register(u0);

[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    if (tid.x != 0u) return;

    float4 st = Out[0];
    float now     = st.x;
    float tPrev   = st.y;
    float newest  = st.z;
    float valid   = st.w;

    // Newest record across BOTH rings.
    //
    // _Data0_Count, NOT _Data0_ValueCount. ValueCount is the per-generation
    // value stride of a RING port (the audio node's Spectrum and Mel Bands use
    // it); a plain record port like Hits publishes valuesPerGeneration 0, so
    // reading ValueCount here silently gave a loop bound of zero and the whole
    // view rendered empty while the port was healthy and full.
    uint n = min((uint)_Data0_Count, 2u * HT_RING_HALF);
    float maxPos = 0.0;
    [loop] for (uint i = 0u; i < n; ++i) {
        HitRec h = In[i];
        if (h.onset_serial == 0u) continue;          // never-written slot
        maxPos = max(maxPos, (float)h.sample_position);
    }

    float win = max(window_s, 0.01) * sample_rate;

    float dt = max(_Time - tPrev, 0.0);
    // A hitch or a first frame must not teleport the strip.
    dt = min(dt, 0.25);

    if (valid < 0.5 || now <= 0.0) {
        now = maxPos;                                 // cold start on real data
    } else {
        now += dt * sample_rate;
        now = max(now, maxPos);                       // catch up immediately
        // ...but never sit further ahead than the view can show. Without this
        // the clock silently walks off the end of the data during silence.
        if (maxPos > 0.0 && (now - maxPos) > win) now = maxPos;
    }

    st.x = now;
    st.y = _Time;
    st.z = maxPos;
    st.w = (maxPos > 0.0) ? 1.0 : valid;
    Out[0] = st;

    // Per-lane counts inside the visible window, computed HERE in one thread.
    // They were first counted in the render pass by scanning all 1600 columns
    // per pixel, which is 1600 x 1280 x 480 -- about a billion iterations a
    // frame for four small numbers that are identical for every pixel.
    float lo = now - win;
    float4 counts = float4(0.0, 0.0, 0.0, 0.0);
    [loop] for (uint j = 0u; j < n; ++j) {
        HitRec h = In[j];
        if (h.onset_serial == 0u) continue;
        float pos = (float)h.sample_position;
        if (pos < lo || pos > now) continue;
        // Records live in lane-specific halves of the ring; trusting lane_id
        // alone would let a stale slot from the other half be counted.
        bool beatHalf = (j >= HT_RING_HALF);
        if (beatHalf != (h.lane_id == HT_BEAT_LANE)) continue;
        if (h.lane_id == 0u) counts.x += 1.0;
        else if (h.lane_id == 1u) counts.y += 1.0;
        else if (h.lane_id == 2u) counts.z += 1.0;
        else if (h.lane_id == HT_BEAT_LANE) counts.w += 1.0;
    }
    Out[1] = counts;
}
