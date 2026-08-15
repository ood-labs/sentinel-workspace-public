// LT_Bench / chief.hlsl — the CHIEF SPECTRUM, ONE BLOCK PER EMITTER.
//
// 32 wavelengths of EVERY emitter, traced through the identical kernel LT_Trace uses for the full
// fan. This is what lets the plan draw a spectral rail at all: a plan view can show where the
// lines go, but not what happened to each colour at each interaction, and the axis this whole
// subject is organised along is wavelength.
//
// ONE BLOCK PER EMITTER, not one block total. The first build traced only the rail's target
// emitter, because the rail — an event ladder and a deviation profile — is inherently a readout
// of ONE source. But the plan strip beside it reads the same buffer, so a bench with three
// sources drew one beam bending and two housings sitting in the dark: the diagram silently
// stopped describing most of its own subject. The rail still reads a single block (chosen by
// `Rail Source`); the plan reads them all.
//
// One axial ray per wavelength. The rail is about dispersion, not about beam width, and adding
// aperture rays here would draw 12 identical curves on top of each other.
#include "../_shared/bench.hlsli"
StructuredBuffer<BenchRec>  Bench : register(t0);
RWStructuredBuffer<PathSeg> Chief : register(u0);
#define LT_BENCH Bench
#define LT_PATHS Chief
#include "../_shared/paths.hlsli"

#define CHIEF_LANES 32
#define CHIEF_STRIDE (CHIEF_LANES * LT_MAX_SEG)

// 12 groups of 32: group index IS the emitter slot, thread index IS the wavelength lane. Every
// slot is written every cook — an inactive emitter dead-fills its block rather than leaving the
// last live bench's paths behind it.
[numthreads(32, 1, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint em = DTid.x / (uint)CHIEF_LANES;
    uint w  = DTid.x % (uint)CHIEF_LANES;
    if (em >= (uint)LT_MAX_EMIT) return;

    gDispGain = dispersion;

    uint base = (em * (uint)CHIEF_LANES + w) * (uint)LT_MAX_SEG;

    BenchRec E = Bench[LT_EMIT_BASE + em];

    if (E.role != ROLE_EMITTER || E.active < 0.5 || LtFlagF(E.flags, F_OFF))
    {
        [loop] for (uint j = 0u; j < (uint)LT_MAX_SEG; ++j) ltWriteDead(base + j);
        return;
    }

    int spec = (int)clamp(E.tone, 0.0, (float)(SP_COUNT - 1));
    float wl = ltLaneWavelength(w, (uint)CHIEF_LANES, spec, E.wl0, E.wl1);

    float2 ro, rd; float apWeight;
    ltEmitRay(E, 0u, 1u, ro, rd, apWeight);   // the axis of the beam

    LtLane C;
    C.wl = wl;
    C.power0 = ltSpectrumPower(wl, spec) * max(E.r0, 0.0);
    C.lane = (float)w;
    C.branch = 0;
    C.maxSeg = (uint)LT_MAX_SEG;
    C.outBase = base;
    ltTracePath(ro, rd, C);
}
