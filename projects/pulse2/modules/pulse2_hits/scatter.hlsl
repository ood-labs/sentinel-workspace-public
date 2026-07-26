// Resolve records into per-lane column occupancy.
//
// One thread per (lane, column), each writing only its own slot: no clear pass,
// no atomics, and no dependence on dispatch order. The alternative -- scattering
// one thread per RECORD into shared columns -- needs both a clear and an
// InterlockedMax, and still loses the tie-break when two records land in one
// column.
//
// Cost is 4 x 1600 threads x 512 records. That sounds worse than a per-pixel
// search and is roughly 300x cheaper, because the answer is constant down a
// column and a per-pixel version recomputes it for every row.

#include "common.hlsli"

StructuredBuffer<HitRec> In : register(t0);
StructuredBuffer<float4> TS : register(t1);
RWStructuredBuffer<float4> Out : register(u0);

[numthreads(64, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    uint col  = tid.x;
    uint lane = tid.y;
    if (col >= HT_COLS || lane >= HT_LANES) return;

    float4 st = TS[0];
    float now = st.x;
    float win = max(window_s, 0.01) * sample_rate;

    // This column covers half a column-width either side of its centre.
    float half = 0.5 * win / (float)HT_COLS;
    float centre = ht_col_to_sample(col, now, win);
    float lo = centre - half;
    float hi = centre + half;

    // Lanes 0..2 live in the picker's ring, lane 3 in the beat clock's. Reading
    // the whole 1024 for every lane would double the work and, worse, let a
    // stale slot from the other ring match on lane id alone.
    uint base  = (lane == HT_BEAT_LANE) ? HT_RING_HALF : 0u;
    uint count = HT_RING_HALF;
    // _Data0_Count, not _Data0_ValueCount -- see clock.hlsl. Hits is a record
    // port, not a hop ring, so its per-generation value stride is zero.
    uint avail = (uint)_Data0_Count;

    float4 res = float4(0.0, 0.0, 0.0, 0.0);
    [loop] for (uint k = 0u; k < count; ++k) {
        uint i = base + k;
        if (i >= avail) break;
        HitRec h = In[i];
        if (h.onset_serial == 0u) continue;
        if (h.lane_id != lane) continue;
        float pos = (float)h.sample_position;
        if (pos < lo || pos >= hi) continue;
        // Newest wins when two land in one column, so a mark always reports the
        // most recent event under it rather than whichever slot came first.
        if (pos >= res.y) {
            res.x = 1.0;
            res.y = pos;
            res.z = (float)h.onset_serial;
        }
    }

    Out[lane * HT_COLS + col] = res;
}
