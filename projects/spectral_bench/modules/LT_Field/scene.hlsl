// LT_Field / scene.hlsl — the program image.
//
// Everything here is DERIVED. The beams come from LT_Trace's segments, the glass outlines come
// from LT_Bench's records through the shared profile function, and every colour in the fan is the
// CIE response at the wavelength that segment was actually traced at. There is no palette in this
// file, because the subject supplies one: the visible spectrum.
//
// The look is a studio sweep in a dark room, because that is what the subject is. A beam is only
// visible side-on if something in the air scatters it, so the "haze" here is not an effect bolted
// on top — it is the reason there is anything to photograph at all.
//
// Publishes RGBA16F. The highlights are genuinely above 1.0 and LT_Lens needs them that way; an
// RGBA8 hand-off would clip every beam core to flat white before the bloom ever saw it.
#include "../_shared/bench.hlsli"
#include "../_shared/optics.hlsli"
#include "../_shared/shapes.hlsli"
StructuredBuffer<BenchRec> Bench : register(t0);
StructuredBuffer<PathSeg>  Paths : register(t1);
StructuredBuffer<uint>     Bins  : register(t2);
RWTexture2D<float4> OutputUAV : register(u0);
#include "segwidth.hlsli"

// Summing RGB(wl) over an equal-energy spectrum lands near (0.34, 0.33, 0.35) per sample, so a
// white beam needs about 3x to come back out white. Measured from the CIE fit rather than dialled
// in by eye, so changing the wavelength count cannot tint the beam.
#define LT_WHITE_NORM 2.95

float3 ltBeamColour(float wl)
{
    return ltWavelengthRGB(wl) * LT_WHITE_NORM;
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 px = DTid.xy;
    if (px.x >= (uint)_Resolution.x || px.y >= (uint)_Resolution.y) return;

    float2 res = _Resolution.xy;
    float2 P = (float2)px + 0.5;
    float2 bp = ltPixToField(P, view_center, view_zoom, res);
    float ppb = ltPxPerBench(view_zoom);

    BenchRec H = Bench[LT_HEADER];
    gDispGain = max(H.par, 0.01);

    PathSeg PH = Paths[LT_PATH_HDR];
    uint nRay  = (uint)clamp(PH.b.x, 1.0, (float)LT_MAX_RAY);
    uint nWave = (uint)clamp(PH.b.y, 1.0, (float)LT_MAX_WAVE);
    uint nBranch = (uint)clamp(PH.wl, 1.0, (float)LT_BRANCH);
    uint stride = (uint)clamp(PH.depth, 1.0, (float)LT_MAX_SEG);
    uint raysPer = (uint)clamp(PH.evt, 1.0, (float)LT_MAX_RAY);

    int viewMode = (int)clamp((float)view_mode, 0.0, 2.0);

    // =========================================================================================
    // BACKDROP. A photographic sweep: a graded ground with a soft key from the upper left and a
    // gentle floor lift, all of it well under a twentieth of the beam's brightness. The subject
    // is light in a dark room, so the room has to stay dark enough for light to be the event.
    // =========================================================================================
    float3 col = 0.0.xxx;
    if (viewMode == 0)
    {
        float2 q = (P - res * 0.5) / res.y;
        float key = exp(-dot(q + float2(0.55, 0.42), q + float2(0.55, 0.42)) * 0.55);
        float floorLift = smoothstep(0.30, 0.52, bp.y / BENCH_H) * 0.35;
        float vig = 1.0 - 0.55 * saturate(dot(q, q) * 0.85);
        col = (float3(0.0100, 0.0104, 0.0118) + key * float3(0.0230, 0.0232, 0.0252)
              + floorLift * float3(0.0075, 0.0074, 0.0080)) * vig * backdrop;
    }

    // =========================================================================================
    // GLASS AND HARDWARE.
    //
    // Drawn BEFORE the beams and additively lit by them, which is the right order for the
    // subject: the prism in the reference photograph is almost invisible except where light is
    // passing through it. A body with a bright outline and almost no fill reads as glass; a body
    // with a solid fill reads as plastic.
    // =========================================================================================
    // Glass is accumulated separately and added AFTER the light, because a glass edge is only
    // bright where light is actually near it. An edge drawn at constant brightness reads as a CAD
    // wireframe laid over a photograph — the single thing that most gives away a rendered prism.
    float3 glassAdd = 0.0.xxx;
    float3 rimAdd   = 0.0.xxx;
    if (viewMode == 0)
    {
        [loop] for (uint ei = 0u; ei < (uint)LT_MAX_ELEM; ++ei)
        {
            BenchRec e = Bench[LT_ELEM_BASE + ei];
            if (e.role != ROLE_ELEMENT || e.active < 0.5 || LtFlagF(e.flags, F_OFF)) continue;
            if (length(bp - e.p0) > ltElementBound(e) + 8.0 / ppb) continue;

            float d = ltElementSDF(e, bp) * ppb;          // signed distance in PIXELS
            float inside = saturate(0.5 - d);
            float rim = saturate(1.0 - abs(d) / 1.6);
            int k = (int)e.kind;

            if (ltIsGlass(k))
            {
                // The body: a whisper of tint that deepens toward the silhouette, so the volume
                // reads without the interior ever becoming opaque.
                float depth = saturate(-d / (ltElementBound(e) * ppb * 0.9));
                // FACES, not an outline. The SDF gradient is the local surface normal, so each
                // face of a prism catches the studio key differently and the body reads as a
                // solid object. Without this a triangle of hairlines reads as wireframe no
                // matter how bright the edges are.
                float h = 1.2 / ppb;
                float2 gr = float2(ltElementSDF(e, bp + float2(h, 0)) - ltElementSDF(e, bp - float2(h, 0)),
                                   ltElementSDF(e, bp + float2(0, h)) - ltElementSDF(e, bp - float2(0, h)));
                float2 nrm = (length(gr) > 1e-6) ? normalize(gr) : float2(0, -1);
                float key = saturate(dot(nrm, normalize(float2(-0.55, -0.83)))) * 0.5 + 0.5;
                glassAdd += inside * float3(0.0380, 0.0440, 0.0560)
                          * (0.30 + depth * 1.1) * (0.35 + key * key * 1.65) * glass_body;
                // The edges. A real glass edge is a caustic line, and it is chromatic because the
                // index that made it is chromatic — so the rim is tinted by the material's own
                // dispersion rather than by an arbitrary fringe colour.
                float n1 = ltIOR((int)e.tone, 470.0), n2 = ltIOR((int)e.tone, 650.0);
                float3 fringe = normalize(float3(n2, (n1 + n2) * 0.5, n1) - 1.0 + 1e-3);
                // A glass edge is a caustic, not a hairline: a bright thin core with a soft
                // outward bleed, so the silhouette reads as a lit edge rather than as wireframe.
                float bleed = exp(-abs(d) * 0.16) * 0.22;
                rimAdd += (rim + bleed)
                        * lerp(float3(0.55, 0.58, 0.64), fringe * 0.95, saturate((n1 - n2) * 3.0))
                        * glass_edge;
            }
            else if (k == EK_MIRROR || k == EK_SPLITTER)
            {
                float face = abs(ltElementFace(e, bp)) * ppb;
                glassAdd += inside * float3(0.0090, 0.0094, 0.0105);
                rimAdd += saturate(1.0 - face / 1.3) * float3(0.30, 0.31, 0.34)
                        * ((k == EK_SPLITTER) ? 0.45 : 1.0) * glass_edge;
            }
            else if (k == EK_SCREEN)
            {
                // A matte detector. Deliberately near-black: everything you will see on it is
                // light that landed there, which is the whole point of putting it on the bench.
                col += inside * float3(0.0130, 0.0130, 0.0136) * screen_tone;
            }
            else   // block
            {
                col = lerp(col, float3(0.0035, 0.0035, 0.0040), inside);
            }
        }
    }

    // =========================================================================================
    // THE LIGHT.
    //
    // One tile's segment list, an analytic distance to each, a hot core plus a wide scatter halo.
    // The halo is the volume: a beam crossing a dark room is only visible because the air gives
    // some of it back sideways, and the width of that give-back is the whole difference between
    // a laser line and a searchlight.
    // =========================================================================================
    uint tile = min((uint)(P.y / (float)LT_TILE), (uint)LT_TILES_Y - 1u) * (uint)LT_TILES_X
              + min((uint)(P.x / (float)LT_TILE), (uint)LT_TILES_X - 1u);
    uint base = tile * (uint)LT_BIN_STRIDE;
    uint cnt = min(Bins[base], (uint)LT_BIN_CAP);
    uint over = Bins[base + 1u];

    if (viewMode == 2)
    {
        // OCCUPANCY. How many segments each tile carries, and which tiles overflowed. A silent
        // cap reads as "the fan got dimmer"; this makes it a visible, diagnosable fact.
        float t = (float)cnt / (float)LT_BIN_CAP;
        col = lerp(float3(0.02, 0.02, 0.025), float3(0.15, 0.85, 0.55), sqrt(t));
        if (over != 0u) col = float3(1.0, 0.15, 0.20);
        OutputUAV[px] = float4(col, 1.0);
        return;
    }

    float coreW = ltCoreW(ppb, beam_width, PH.dev, raysPer);
    float haloW = ltHaloW(coreW, haze);
    // Normalise by BOTH lane axes. Every wavelength and every aperture ray carries full power, so
    // without this the image gets brighter purely by being traced at a higher quality rung — the
    // one thing a quality control must never do.
    float norm = exposure / (float)max(nWave * raysPer, 1u);

    float3 light = 0.0.xxx;

    [loop] for (uint bi = 0u; bi < cnt; ++bi)
    {
        uint idx = Bins[base + 2u + bi];
        PathSeg g = Paths[idx];
        if (g.power <= 1e-4) continue;

        float2 a = ltFieldToPix(g.a, view_center, view_zoom, res);
        float2 b = ltFieldToPix(g.b, view_center, view_zoom, res);
        float d = ltSdSeg(P, a, b);
        float3 c = ltBeamColour(g.wl) * g.power;

        float localW = ltSegWidth(g, coreW, ppb, nRay, nWave, nBranch, stride);
        if (d > ltSegReach(localW, coreW, haze)) continue;

        // ======================================================================================
        // THE BEAM IS A SHEET, NOT N FILAMENTS.
        //
        // Each ray is drawn as a FLAT-TOP RIBBON exactly half a ray-spacing to either side, so
        // adjacent ribbons tile edge to edge and reconstruct the continuous bundle. Gaussian
        // filaments cannot do this: they sum to a rippled profile, and the moment the beam is made
        // narrow the gaps between rays open into visible stripes. This is the single change that
        // lets a beam be thin without falling apart.
        //
        // `cov` is the EXACT overlap of that ribbon with a one-pixel box — the analytic
        // convolution, not an approximation — so a ribbon far thinner than a pixel still resolves
        // cleanly instead of aliasing into dashes.
        //
        // Dividing by the ribbon's own width makes it FLUX CONSERVING: the ray carries a fixed
        // power, so squeezing it into a narrower ribbon raises the radiance. A beam brought to a
        // focus brightens, a diverging one fades, and neither is tuned — both fall out of the
        // same two lines.
        float w2 = 2.0 * localW;
        float cov = clamp(localW + 0.5 - d, 0.0, min(w2, 1.0));
        float core = cov / max(w2, 1e-4);

        float halo = exp(-(d * d) / (haloW * haloW)) * haze * 0.14;

        // Inside glass the beam travels through a medium that scatters far less than air, so it
        // reads as a tight bright filament rather than a smoky column. Derived from the segment's
        // own recorded index, so a denser glass gets a brighter internal caustic for free.
        if (g.ior > 1.001)
        {
            core *= 1.0 + (g.ior - 1.0) * 0.55;
            halo *= 0.55;
        }

        light += c * (core + halo);

        // Interaction points. A refraction or a reflection is a real concentration of light —
        // the blown-out star on the entry face of the reference photograph is exactly this — so
        // every event that is not a plain escape gets a small radial burst.
        int evE = (int)g.evtEnd;
        if (evE != EV_ESCAPE)
        {
            float dv = length(P - b);
            float hot = (evE == EV_SCREEN) ? 1.35 : ((evE == EV_ENTER || evE == EV_EXIT) ? 1.0
                      : ((evE == EV_MIRROR) ? 0.8 : 0.45));
            // Sized from the BASE width, not the widened one. A hot spot is a point highlight,
            // and letting it scale with the local ray spacing pushes its falloff past the radius
            // the binner expanded by — which shows up as 16-pixel blocks around the brightest
            // part of the image, the one place nobody will forgive them.
            // The hot spot keeps a size of its own: it is a point highlight, and tying it to a
            // ribbon that may now be a fraction of a pixel would erase it exactly where the light
            // is most concentrated.
            float sw = max(coreW * 2.5, 1.8);
            light += c * hot * exp(-(dv * dv) / (sw * sw * 5.5)) * spark;
        }
    }

    light *= norm;
    col += light;

    // Now the hardware, lit by what is actually crossing it.
    float lit = saturate(dot(light, float3(0.2126, 0.7152, 0.0722)) * 0.55);
    col += glassAdd + rimAdd * (0.30 + 2.10 * lit);

    if (viewMode == 1) col = light;      // BEAMS ONLY — the transport with the room removed

    // An overflowing tile is drawn, faintly, even in the program view. It is better for a capture
    // to carry a visible mark that something was dropped than for it to look merely dim.
    if (over != 0u && viewMode == 0) col += float3(0.010, 0.0, 0.002);

    OutputUAV[px] = float4(max(col, 0.0), 1.0);
}
