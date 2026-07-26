// Scroll clock.
//
// The view must advance on WALL time, not on events. Driving the right edge
// straight from the newest record would freeze the strip whenever a lane went
// quiet -- and a silent stretch is precisely what you are looking at the view
// to see. So the clock free-runs at `sample_rate` and is re-synced upward
// whenever a newer record appears.
//
// Re-sync is one-directional on purpose. `sample_position` jumps BACKWARDS on
// every File-mode restart (and on any seek), and following it down would rewind
// the strip mid-scroll and redraw stale records as if they were new. A restart
// instead shows as the clock running ahead until the fresh stream catches up,
// which is self-correcting and cannot invent an event.

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

    float dt = max(_Time - tPrev, 0.0);
    // A hitch or a first frame must not teleport the strip; one window of
    // advance is the most any single frame is allowed to contribute.
    dt = min(dt, 0.25);

    if (valid < 0.5 || now <= 0.0) {
        now = maxPos;                                 // cold start on real data
    } else {
        now += dt * sample_rate;
        now = max(now, maxPos);                       // catch up, never rewind
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
    float win = max(window_s, 0.01) * sample_rate;
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
