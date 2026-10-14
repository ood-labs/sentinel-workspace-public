// LT_Field / segs.hlsl — every traced segment, resolved ONCE per cook into the program frame.
//
// The binner and the renderer both need the same per-segment facts: where the segment lies in
// pixels, how wide this ray is drawn here, how far it puts ink, what colour it carries. Each of
// those is the same for every pixel, but the renderer used to work them out again for every
// pixel that tested the segment — a neighbour-ray lookup with integer divides and a CIE fit,
// repeated a few thousand times per segment per cook. Doing it here once is the same arithmetic
// on the same inputs, so the image does not change; only the bill does.
#include "../_shared/bench.hlsli"
#include "../_shared/optics.hlsli"
#include "view.hlsli"
StructuredBuffer<PathSeg> Paths : register(t0);
RWStructuredBuffer<SegPx> Segs  : register(u0);
#include "segwidth.hlsli"

// Summing RGB(wl) over an equal-energy spectrum lands near (0.34, 0.33, 0.35) per sample, so a
// white beam needs about 3x to come back out white. Measured from the CIE fit rather than dialled
// in by eye, so changing the wavelength count cannot tint the beam.
#define LT_WHITE_NORM 2.95

float3 ltBeamColour(float wl)
{
    return ltWavelengthRGB(wl) * LT_WHITE_NORM;
}

[numthreads(64, 1, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    PathSeg H = Paths[LT_PATH_HDR];
    uint liveSegs = (uint)clamp(H.a.x, 0.0, (float)LT_PATH_TOTAL);
    uint i = DTid.x;
    if (i >= liveSegs) return;

    uint raysPer  = (uint)clamp(H.evt,   1.0, (float)LT_MAX_RAY);
    uint nRay     = (uint)clamp(H.b.x,   1.0, (float)LT_MAX_RAY);
    uint nWave    = (uint)clamp(H.b.y,   1.0, (float)LT_MAX_WAVE);
    uint nBranch  = (uint)clamp(H.wl,    1.0, (float)LT_BRANCH);
    uint stride   = (uint)clamp(H.depth, 1.0, (float)LT_MAX_SEG);

    float ppb = ltPxPerBench(view_zoom);
    float coreW = ltCoreW(ppb, beam_width, H.dev, raysPer);
    float2 res = float2((float)FIELD_W, (float)FIELD_H);

    PathSeg g = Paths[i];
    SegPx s;
    s.ab = float4(ltFieldToPix(g.a, view_center, view_zoom, res),
                  ltFieldToPix(g.b, view_center, view_zoom, res));
    if (g.power <= 1e-4)
    {
        // A dead lane draws nothing, and a negative reach is how the binner knows to skip it.
        s.w = float4(0.0, -1.0, 0.0, 0.0);
        s.col = 0.0.xxxx;
        Segs[i] = s;
        return;
    }

    float localW = ltSegWidth(g, coreW, ppb, nRay, nWave, nBranch, stride);

    // Inside glass the beam travels through a medium that scatters far less than air, so it
    // reads as a tight bright filament rather than a smoky column. Derived from the segment's
    // own recorded index, so a denser glass gets a brighter internal caustic for free.
    bool glass = g.ior > 1.001;
    s.w = float4(localW, ltSegReach(localW, coreW, haze),
                 glass ? 1.0 + (g.ior - 1.0) * 0.55 : 1.0,
                 glass ? 0.55 : 1.0);

    // Interaction points. A refraction or a reflection is a real concentration of light — the
    // blown-out star on the entry face of the reference photograph is exactly this — so every
    // event that is not a plain escape gets a small radial burst, weighted here.
    int evE = (int)g.evtEnd;
    float hot = (evE == EV_ESCAPE) ? 0.0
              : ((evE == EV_SCREEN) ? 1.35 : ((evE == EV_ENTER || evE == EV_EXIT) ? 1.0
              : ((evE == EV_MIRROR) ? 0.8 : 0.45)));
    s.col = float4(ltBeamColour(g.wl) * g.power, hot);
    Segs[i] = s;
}
