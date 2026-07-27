// Turn the analyser's counters into events. One thread.
//
// This is the pass that makes the demo a demo. An envelope can be multiplied
// into a size or a brightness with no state at all, and that is the obvious use
// of audio_bands. The COUNTERS are the interesting output: they are monotonic,
// so watching one change is a discrete trigger, and a trigger can seed an object
// that then lives its own life. That is the difference between a shape that
// throbs with the music and a shape that is BUILT by it.

#include "demo.hlsli"
#include "../_shared/anim/anim.hlsli"

RWStructuredBuffer<float4> Pool : register(u0);

[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    float t = _Time;

    float4 hdr = Pool[DM_HDR];
    float4 snr = Pool[DM_SNR];
    float4 ini = Pool[DM_INI];

    // Settle, then adopt the counters where they stand rather than treating
    // their whole lifetime total as unseen. They arrive in the thousands, so
    // the alternative is several thousand rings on every reload.
    //
    // Adopting on the FIRST cook is not enough, and this is not hypothetical:
    // the counts arrive through expressions, which had not evaluated yet, so
    // the pool adopted zeros and then saw the real 3166 land as a delta. Every
    // lane fired one phantom event on load and the scan line started in the
    // wrong place. Keep re-adopting for a few cooks so whenever the drivers
    // land, they land inside the settling window.
    if (ini.x < 0.5) {
        float cooks = ini.y + 1.0;
        [loop] for (uint i = 0u; i < DM_RINGS; ++i) {
            Pool[i] = float4(0.0, 0.0, 0.0, 0.0);
        }
        Pool[DM_HDR] = float4(kick_hits, snare_hits, hat_hits, 0.0);
        Pool[DM_SNR] = float4(0.5, 0.5, t, 0.0);
        Pool[DM_INI] = float4((cooks >= 8.0) ? 1.0 : 0.0, cooks, 0.0, 0.0);
        return;
    }

    float dk = kick_hits  - hdr.x;
    float ds = snare_hits - hdr.y;
    float dh = hat_hits   - hdr.z;

    // A jump in either direction that is too large to be real hits is
    // bookkeeping: a reset, a reload, or the drivers connecting for the first
    // time. Adopt it silently. Spawning on it would fire a phantom event on
    // every lane each time anything upstream was reloaded, which is exactly
    // what happened before this guard existed.
    if (abs(dk) > DM_ADOPT_JUMP || abs(ds) > DM_ADOPT_JUMP
        || abs(dh) > DM_ADOPT_JUMP || dk < 0.0 || ds < 0.0 || dh < 0.0) {
        Pool[DM_HDR] = float4(kick_hits, snare_hits, hat_hits, hdr.w);
        return;
    }

    // ---- kick -> spawn an expanding ring per hit --------------------------
    uint w = (uint)max(hdr.w, 0.0);
    uint n = (uint)clamp(dk, 0.0, DM_MAX_SPAWN);
    [loop] for (uint s = 0u; s < n; ++s) {
        Pool[w % DM_RINGS] = float4(t, dmHash((float)w * 0.618 + 1.0), 1.0, 0.0);
        w += 1u;
    }

    // ---- snare -> jump the scan line to a new height ----------------------
    if (ds > 0.0) {
        // Capture where the line is RIGHT NOW as the new starting point, not
        // where the last jump was aiming. Starting from the old target would
        // teleport the line backwards whenever two snares landed inside one
        // settle.
        float e   = an_spring(t - snr.z, AN_SNAPPY.x, AN_SNAPPY.y, AN_SNAPPY.z);
        float cur = lerp(snr.y, snr.x, e);
        float tgt = 0.12 + 0.76 * dmHash(snare_hits * 0.37 + 7.0);
        Pool[DM_SNR] = float4(tgt, cur, t, 0.0);
    }

    Pool[DM_HDR] = float4(kick_hits, snare_hits, hat_hits, (float)w);
}
