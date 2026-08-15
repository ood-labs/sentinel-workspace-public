// FM_Colony / sta.hlsl — the stations' bookkeeping, and the only pass that hands out ants.
//
// Single threaded, and that is the whole design rather than a shortcut. Releasing an ant is an
// ALLOCATION out of a pool that every emitter is competing for, and an allocation needs one
// authority. The alternatives were tried on paper and each one is broken in a specific way:
//
//   every dormant ant rolls a die     needs the dormant count, which no ant can see
//   every emitter claims an index range  two emitters claim the same slot, and a range full of
//                                        already-walking ants silently emits nothing
//   atomic append from a per-ant pass    non-deterministic order, and the clear it needs is
//                                        exactly the pass the scheduler is free to misplace
//
// So: one thread walks the population twice — once to count, once to deal — and publishes an
// explicit list of ant indices per station. 2048 iterations single threaded is nothing, and it
// is exact.
//
// It reads `ants`, so the scheduler puts it after walk and walk acts on the list one cook later.
// A trigger therefore fires 16 ms after the click, which is a frame.
#include "../_shared/formic.hlsli"
#include "colony.hlsli"

RWStructuredBuffer<FmSta> Sta  : register(u0);
StructuredBuffer<FmCtl>   Ctl  : register(t1);
StructuredBuffer<FmRec>   PlanB : register(t2);
StructuredBuffer<FmAnt>   Ants : register(t3);

[numthreads(1, 1, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    FmCtl ctl = Ctl[0];
    float dt = clamp(ctl.dt, 0.0, 0.05);

    // ---------------------------------------------------------------------------
    // COUNT. One scan: how many slots are free, how many ants each station owns.
    //
    // Tallied straight into the station buffer rather than into a local array. A local array
    // indexed by a value the compiler cannot see through has to live in registers, and asking
    // for that inside a loop whose bound is a parameter makes fxc try to unroll a thousand-
    // iteration loop and give up with X3511. Buffer memory has no such problem.
    // ---------------------------------------------------------------------------
    uint n = min((uint)ant_count, FM_MAX_ANTS);

    for (uint s = 0u; s < FM_STAS; s++) Sta[s].live = 0.0;

    uint dormant = 0u;
    uint active = 0u;

    [loop]
    for (uint i = 0u; i < n; i++)
    {
        FmAnt a = Ants[i];
        // A slot a CONSUME sink spent is neither dormant nor active — it is gone. Counting it
        // as dormant would report free capacity that no emitter can ever draw on.
        if (a.pad2 > 0.5) continue;
        if (a.active < 0.5) { dormant++; continue; }
        active++;
        uint h = (uint)(a.home + 0.5);
        if (h >= 1u && h <= FM_STAS) Sta[h - 1u].live += 1.0;
    }

    // ---------------------------------------------------------------------------
    // DEMAND. What each emitter is owed this cook, in whole ants. Parked in the record's own
    // pad0 rather than in a local array, for the same register-indexing reason as above; it is
    // transient and rewritten every cook.
    // ---------------------------------------------------------------------------
    uint totalWant = 0u;

    for (uint s2 = 0u; s2 < FM_STAS; s2++)
    {
        FmSta st = Sta[s2];
        st.pad0 = 0.0;

        // Persistent buffers arrive poisoned. A non-finite accumulator would demand an infinite
        // number of ants forever, and a clamp would hold that state permanently rather than let
        // it recover — so the bad value is discarded, not bounded.
        if (!(abs(st.accum) < 1e9)) st.accum = 0.0;
        if (!(abs(st.lastTrig) < 1e9)) st.lastTrig = 0.0;
        if (!(abs(st.served) < 1e12)) st.served = 0.0;

        float liveHere = Sta[s2].live;      // tallied by the scan above
        st.live = liveHere;
        st.relCount = 0.0;
        for (uint r = 0u; r < FM_STA_REL; r++) st.rel[r] = -1.0;

        FmRec rec = PlanB[FM_STA_0 + s2];
        bool isEmit = (rec.active > 0.5) && (((int)(rec.kind + 0.5)) == 0);

        if (!isEmit)
        {
            // Not an emitter: keep the accumulator from drifting while the record is something
            // else, so switching a station back to Emit does not dump a stored backlog at once.
            st.accum = 0.0;
            st.lastTrig = rec.pad0;
            Sta[s2] = st;
            continue;
        }

        int mode = (int)(rec.p1 + 0.5);

        // The trigger is a MONOTONIC COUNTER compared against what we last saw, never a boolean
        // held for a frame. A held flag is missed when a cook is dropped and counted twice when
        // one is slow; a difference is neither.
        float trig = rec.pad0;
        float fired = max(trig - st.lastTrig, 0.0);
        st.lastTrig = trig;

        if (mode == 1)                                   // BURST: silent until fired
        {
            st.accum += fired * max(rec.p3, 1.0);
        }
        else                                             // DRIP and RING: a steady rate
        {
            st.accum += max(rec.p0, 0.0) * dt;
            st.accum += fired * max(rec.p3, 1.0);        // a burst on top is still welcome
        }

        uint owed = (uint)floor(max(st.accum, 0.0));

        // BUDGET. 0 means unlimited; otherwise the station may not have more than p2 ants out at
        // once. Checked against the MEASURED live count rather than against a running tally,
        // because ants die into sinks and wander off a station's books without telling it.
        uint budget = (uint)max(rec.p2, 0.0);
        if (budget > 0u)
        {
            uint held = (uint)max(liveHere, 0.0);
            uint room = (held < budget) ? (budget - held) : 0u;
            owed = min(owed, room);
            // Do not bank demand a full station could not use, or unbudgeting it later fires
            // everything it never emitted in one frame.
            st.accum = min(st.accum, (float)owed + 0.999);
        }

        owed = min(owed, FM_STA_REL);
        st.pad0 = (float)owed;
        totalWant += owed;

        Sta[s2] = st;
    }

    // ---------------------------------------------------------------------------
    // DEAL. One scan, from a rotating cursor, handing free slots to the stations that asked.
    //
    // The cursor rotates so releases walk through the buffer instead of always reusing the
    // lowest free indices. That is not tidiness: the low indices are the ants a sink swallowed
    // most recently, so reusing them preferentially makes one emitter re-release the same few
    // ants over and over, and their per-individual size and tint variation stops reading as a
    // population and starts reading as a repeating pattern.
    // ---------------------------------------------------------------------------
    FmSta sum = Sta[FM_STA_SUM];
    if (!(abs(sum.served) < 1e12)) sum.served = 0.0;

    uint cursor = (uint)max(sum.served, 0.0) % max(n, 1u);
    uint released = 0u;

    // One SHARED scan position carried across the stations, so two emitters can never be
    // handed the same slot: station s starts looking where station s-1 stopped, and no ant
    // index is examined twice in a cook.
    uint scan = 0u;

    if (totalWant > 0u && dormant > 0u)
    {
        for (uint s3 = 0u; s3 < FM_STAS; s3++)
        {
            uint owed = (uint)max(Sta[s3].pad0, 0.0);
            if (owed == 0u) continue;

            uint got = 0u;

            [loop]
            while (got < owed && scan < n)
            {
                uint i = (cursor + scan) % n;
                scan++;

                if (Ants[i].active > 0.5) continue;
                if (Ants[i].pad2 > 0.5) continue;   // spent by a CONSUME sink; not on offer

                // Written straight into the buffer. `got` is a dynamic index, and a dynamic
                // index into a LOCAL copy of the struct is the register-array trap again.
                Sta[s3].rel[got] = (float)i;
                got++;
            }

            if (got > 0u)
            {
                Sta[s3].relCount = (float)got;
                Sta[s3].accum = max(Sta[s3].accum - (float)got, 0.0);
                Sta[s3].served += (float)got;
                released += got;
            }
        }
    }

    // ---------------------------------------------------------------------------
    // SUMMARY. Element FM_STA_SUM is not a station. Field map, which the manifest's control
    // outputs index by byte offset and FM_Plan's readout draws:
    //
    //   lastTrig  dormant slots        accum  ants on the plate
    //   live      stations switched on relCount  released this cook
    //   rel[0..3] emitters / attractors / repellers / sinks
    //   served    the release cursor, carried between cooks
    // ---------------------------------------------------------------------------
    // Four scalars rather than a four-element array indexed by the record's kind. Same
    // register-indexing trap, and at four members the array was never buying anything.
    float nEmit = 0.0, nAttr = 0.0, nRep = 0.0, nSink = 0.0, onCount = 0.0;

    for (uint s4 = 0u; s4 < FM_STAS; s4++)
    {
        FmRec rec = PlanB[FM_STA_0 + s4];
        if (rec.active < 0.5) continue;
        onCount += 1.0;
        int kk = (int)(rec.kind + 0.5);
        if (kk == 0)      nEmit += 1.0;
        else if (kk == 1) nAttr += 1.0;
        else if (kk == 2) nRep  += 1.0;
        else              nSink += 1.0;
    }

    sum.lastTrig = (float)dormant;
    sum.accum    = (float)active;
    sum.live     = onCount;
    sum.relCount = (float)released;
    sum.rel[0] = nEmit; sum.rel[1] = nAttr; sum.rel[2] = nRep; sum.rel[3] = nSink;
    sum.rel[4] = 0.0; sum.rel[5] = 0.0; sum.rel[6] = 0.0; sum.rel[7] = 0.0;

    // Advance the cursor past everything examined, so the next cook starts on fresh slots
    // rather than re-walking the run of active ants this one just stepped over.
    sum.served = (float)((cursor + max(scan, 1u)) % max(n, 1u));

    Sta[FM_STA_SUM] = sum;
}
