// LT_Trace / trace.hlsl — the physics, and only the physics.
//
// One thread per LANE, where a lane is (ray, wavelength, branch). Every lane is independent, so
// the whole light transport is one flat dispatch with no ordering, no atomics and no feedback.
//
// This node re-decides NOTHING about the bench. It reads placement, glass, apex angles and beam
// apertures out of LT_Bench's records, and it reads the dispersion gain out of the bench HEADER
// rather than carrying its own copy — two numbers that have to be kept in agreement by hand will
// eventually disagree, at exactly the setting nobody tested.
#include "../_shared/bench.hlsli"
StructuredBuffer<BenchRec>  Bench : register(t0);
RWStructuredBuffer<PathSeg> Paths : register(u0);
#define LT_BENCH Bench
#define LT_PATHS Paths
#include "../_shared/paths.hlsli"

[numthreads(64, 1, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint lane = DTid.x;

    // The gain the plan is actually using. One source of truth for the whole graph.
    gDispGain = max(Bench[LT_HEADER].par, 0.01);

    uint nWave   = (uint)clamp((float)wave_count,  2.0, (float)LT_MAX_WAVE);
    uint nBranch = (uint)clamp((float)branch_count, 1.0, (float)LT_BRANCH);
    uint maxSeg  = (uint)clamp((float)max_events,  2.0, (float)LT_MAX_SEG);

    // Live emitters, and how many rays each can afford out of the shared ray budget. Every source
    // gets at least one ray: a source that traces nothing is a source that silently vanished.
    uint nEmit = 0u;
    [loop] for (uint ei = 0u; ei < (uint)LT_MAX_EMIT; ++ei)
    {
        BenchRec E = Bench[LT_EMIT_BASE + ei];
        if (E.role == ROLE_EMITTER && E.active > 0.5 && !LtFlagF(E.flags, F_OFF)) nEmit++;
    }
    if (nEmit == 0u)
    {
        // Nothing emits. The header reports zero live segments, which is all any consumer needs:
        // stale records past the live region are never read, so there is nothing to clear.
        if (lane == 0u) { PathSeg H = (PathSeg)0; H.elem = -1.0; H.depth = 1.0; Paths[LT_PATH_HDR] = H; }
        return;
    }

    uint raysPer = (uint)clamp((float)ray_count, 1.0, (float)LT_MAX_RAY);
    raysPer = max(1u, min(raysPer, (uint)LT_MAX_RAY / nEmit));
    uint nRay = nEmit * raysPer;
    uint nLane = nRay * nWave * nBranch;

    // The paths header. Written by one thread, read by every downstream consumer so that nothing
    // has to scan 32k segments to find the ~2k that are live.
    if (lane == 0u)
    {
        PathSeg H = (PathSeg)0;
        H.a = float2((float)(nLane * maxSeg), (float)nLane);
        H.b = float2((float)nRay, (float)nWave);
        H.wl = (float)nBranch;
        H.evt = (float)raysPer;       // so the renderer can normalise per-ray without recounting
        H.lane = (float)nEmit;
        // The widest live aperture. The renderer needs it to work out how wide to draw ONE ray
        // so that N rays across an aperture fuse into a beam instead of reading as N stripes —
        // a magnitude that belongs to the source, not to the renderer's own parameter list.
        float maxAp = 0.0;
        [loop] for (uint ai = 0u; ai < (uint)LT_MAX_EMIT; ++ai)
        {
            BenchRec Ea = Bench[LT_EMIT_BASE + ai];
            if (Ea.role == ROLE_EMITTER && Ea.active > 0.5 && !LtFlagF(Ea.flags, F_OFF))
                maxAp = max(maxAp, Ea.p1.x);
        }
        H.dev = maxAp;
        H.depth = (float)maxSeg;      // the LANE STRIDE
        H.power = 0.0;                // never drawn; read explicitly at LT_PATH_HDR
        H.elem = -1.0;
        H.ior = gDispGain;
        Paths[LT_PATH_HDR] = H;
    }

    // Lanes past the live region simply stop. Consumers read the header's live-segment count and
    // never look further, so lowering the quality rung costs nothing and leaves nothing behind.
    if (lane >= nLane) return;

    uint br = lane % nBranch;
    uint wv = (lane / nBranch) % nWave;
    uint ry = lane / (nBranch * nWave);

    uint emIdx = ry / raysPer;
    uint subRay = ry % raysPer;

    // Map the emitter ordinal onto an actual live record: slots are not contiguous once records
    // have been deleted or switched off.
    uint slot = (uint)LT_EMIT_BASE;
    uint seen = 0u;
    [loop] for (uint fi = 0u; fi < (uint)LT_MAX_EMIT; ++fi)
    {
        BenchRec E = Bench[LT_EMIT_BASE + fi];
        if (E.role == ROLE_EMITTER && E.active > 0.5 && !LtFlagF(E.flags, F_OFF))
        {
            if (seen == emIdx) { slot = (uint)LT_EMIT_BASE + fi; break; }
            seen++;
        }
    }

    BenchRec E = Bench[slot];
    int spec = (int)clamp(E.tone, 0.0, (float)(SP_COUNT - 1));
    float wl = ltLaneWavelength(wv, nWave, spec, E.wl0, E.wl1);

    float2 ro, rd; float apWeight;
    ltEmitRay(E, subRay, raysPer, ro, rd, apWeight);

    LtLane C;
    C.wl = wl;
    C.power0 = ltSpectrumPower(wl, spec) * max(E.r0, 0.0) * apWeight;
    C.lane = (float)lane;
    C.branch = (int)br;
    C.maxSeg = maxSeg;
    C.outBase = lane * maxSeg;
    ltTracePath(ro, rd, C);
}
