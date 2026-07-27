// Did this lane fire since last frame? One thread per lane.
//
// Firing is detected from the lane's SERIAL COUNTER advancing, not from record
// timestamps. Serials are per-lane and monotonic, so "the highest serial I can
// see is greater than the highest I saw last frame" is exactly the question,
// and it needs no clock, no sample rate, and no assumption about the source's
// timebase. The scrolling view this replaces had to map sample positions onto
// columns, and that mapping was the source of its worst failure.

RWStructuredBuffer<float4> Pads : register(u0);

struct HitRec { uint lane_id; uint onset_serial; uint hop_index; uint sample_position; };
StructuredBuffer<HitRec> In : register(t0);

static const uint RING_HALF = 512u;   // onsets 0..511, beats 512..1023
static const uint BEAT_LANE = 3u;

[numthreads(4, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    uint lane = tid.x;
    if (lane >= 4u) return;

    float4 st = Pads[lane];
    float lastSerial = st.x;
    float flash      = st.y;
    float total      = st.z;
    float tPrev      = st.w;

    // Lanes 0..2 live in the picker's half, lane 3 in the beat clock's. The two
    // halves carry INDEPENDENT serial sequences, so scanning all 1024 and
    // filtering on lane_id alone would mix two unrelated counters and make the
    // pad fire on the other ring's traffic.
    uint base  = (lane == BEAT_LANE) ? RING_HALF : 0u;
    uint avail = (uint)_Data0_Count;

    float top = 0.0;
    [loop] for (uint k = 0u; k < RING_HALF; ++k) {
        uint i = base + k;
        if (i >= avail) break;
        HitRec h = In[i];
        if (h.onset_serial == 0u) continue;
        if (h.lane_id != lane) continue;
        top = max(top, (float)h.onset_serial);
    }

    float dt = max(_Time - tPrev, 0.0);
    dt = min(dt, 0.25);            // a hitch must not blank every pad at once

    // Decay first, then light. A hit landing this frame therefore always leaves
    // the pad at full brightness rather than at full-minus-one-frame's-decay.
    float tau = max(decay_s, 0.001);
    flash *= exp(-dt / tau);

    if (top > lastSerial) {
        // The serial counter also tells us HOW MANY fired since the last frame,
        // which matters at high rates: at 60 fps a lane firing twice inside one
        // frame would otherwise be one flash and one counted hit.
        total += (lastSerial > 0.0) ? (top - lastSerial) : 1.0;
        flash = 1.0;
    } else if (top > 0.0 && top < lastSerial) {
        // Serials restart when the detector is reloaded or the source restarts.
        // Treat it as a fresh start rather than going dark until the counter
        // climbs back past a stale high-water mark.
        total = 0.0;
        flash = 1.0;
    }

    st.x = top;
    st.y = saturate(flash);
    st.z = total;
    st.w = _Time;
    Pads[lane] = st;
}
