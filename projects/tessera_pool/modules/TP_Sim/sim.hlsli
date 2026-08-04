// TP_Sim / sim.hlsli — shared declarations for the water surface.
//
// THE FIELD LAYOUT, published to every consumer:
//     .x  h      surface height in WORLD units, 0 = still water
//     .y  v      vertical velocity, world units per second (foam and glint density read this)
//     .z  dh/dx  world-space gradient
//     .w  dh/dz  world-space gradient
//
// Gradients are stored rather than recomputed downstream on purpose. A consumer that
// differences a bilinearly-interpolated height gets a normal that is constant across each
// texel and jumps at every cell boundary; interpolating the gradients instead gives a smooth
// normal, which is the difference between glassy water and a faceted foil.
#ifndef TP_SIM_HLSLI
#define TP_SIM_HLSLI

#include "../_shared/tessera.hlsli"

struct TpCtl
{
    float4 a;   // [0] (init, time, dtEff, cooks)       [1] (lastInU, lastInV, lastExU, lastExV)
    float4 b;   // [0] (inU0, inV0, inU1, inV1)         [1] (haveIn, haveEx, 0, 0)
    float4 c;   // [0] (exU0, exV0, exU1, exV1)
    float4 d;   // [0] (inActive, exActive, inImpulse, exImpulse)
};

// ---------------------------------------------------------------------------
// Capillary detail. The simulated grid resolves the ripple trains the composition is made of;
// it cannot resolve the fine chop that makes a real surface glitter, and refining the grid
// until it could would cost far more than this does.
//
// Detail is added to the GRADIENT and only barely to the height: the marching intersection
// wants a smooth surface it can find in a few steps, while the shading wants the high-frequency
// normal that produces the sparkle. Perturbing only the normal is invisible as an inconsistency
// and is the entire visual difference between plastic and water.
// ---------------------------------------------------------------------------
float2 tpCapillary(float2 p, float t, float amp, float scale, out float hOut)
{
    float2 g = float2(0.0, 0.0);
    float h = 0.0;

    // four crossing trains, deliberately irrational in direction so nothing tiles
    float2 dirs[4] = { float2(0.9239, 0.3827), float2(-0.3090, 0.9511),
                       float2(0.7071, -0.7071), float2(-0.8660, -0.5000) };
    // NYQUIST. The published field is 512 texels across a two-unit tank, so one texel is
    // 0.0039 world units and anything shorter than about ten texels — 0.04 units — cannot be
    // carried. The original set bottomed out at 0.019, five texels, and since a gradient scales
    // as amplitude times wavenumber that aliased octave arrived with a slope comparable to the
    // real waves. It printed a fixed crosshatch through everything downstream: through the
    // caustic atlas, where it buried the ripple focus lines completely, and it would have
    // shimmered in the render. Every octave here now sits above ten texels.
    float wl[4] = { 0.155, 0.108, 0.074, 0.049 };
    float sp[4] = { 0.42, 0.55, 0.71, 0.93 };
    float wt[4] = { 1.00, 0.64, 0.38, 0.20 };

    [unroll]
    for (int i = 0; i < 4; i++)
    {
        float k = 6.2831853 / max(wl[i] * scale, 1e-3);
        float ph = dot(p, dirs[i]) * k - t * sp[i] * k * 0.35;
        float s = sin(ph);
        float cch = cos(ph);
        h += s * wt[i];
        g += dirs[i] * (cch * k * wt[i]);
    }

    hOut = h * amp;
    return g * amp;
}

// ---------------------------------------------------------------------------
// AMBIENT SWELL. The one thing on this surface that is never allowed to stop.
//
// The capillary chop above is deliberately gated by the wave envelope, so a settled tank goes
// genuinely still — correct physics, dead image. Standing water in a room is never a mirror: it
// always carries a slow wander from air movement and building vibration, and the eye reads its
// ABSENCE instantly as "this is a sheet of plastic". So this layer is ungated on purpose. That
// is the opposite decision from tpCapillary and the reason it is a separate function rather
// than a flag on that one: nothing about the solver's state may reach it, because its entire
// job is to still be there after the solver has settled.
//
// WHY A SPECTRUM AND NOT A FIXED SET OF TRAINS.
//
// A handful of sines at hand-picked wavelengths sums to something periodic and obviously
// synthetic — the eye finds the repeat in about a second. Water has an energy spectrum: many
// scales at once, each smaller one an octave up and proportionally weaker, all of them riding
// on the larger ones underneath. Three properties do the convincing, and none of them survive
// a fixed sine stack:
//
//   OCTAVES      a decaying amplitude ladder, so detail exists at every scale you look at
//   CREST SHAPE  gravity waves have sharp crests and broad flat troughs. A sine is symmetric,
//                which is why an unsharpened sum reads as rippled cloth rather than as water
//   WARP         each octave is ADVECTED by the ones below it instead of being laid over them,
//                which is what stops the sum reading as N independent gratings
//
// plus dispersion — longer waves travel faster — without which the whole field slides as one
// scrolling texture.
// ---------------------------------------------------------------------------
struct TpSwell
{
    float amp;       // world units, peak of the summed spectrum
    float wl;        // wavelength of the FIRST (largest) octave, world units
    int   octaves;   // how many scales
    float gain;      // amplitude multiplier per octave (persistence)
    float lac;       // wavelength divisor per octave (lacunarity)
    float spread;    // 0 = every octave runs one way (clean swell), 1 = scattered (confused chop)
    float dir;       // heading of the base train, degrees
    float sharp;     // 0 = raw sine, 1 = hard peaked crests over flat troughs
    float warp;      // how hard each octave is advected by the ones below it
    float speed;
};

float tpSwellH(float2 p, float t, TpSwell w)
{
    float h    = 0.0;
    float amp  = 1.0;
    float norm = 0.0;
    float wl   = max(w.wl, 0.03);
    float2 q   = p;

    int n = clamp(w.octaves, 1, 8);

    [loop]
    for (int i = 0; i < 8; i++)
    {
        if (i >= n) break;

        // Heading. At spread 0 every octave runs the same way and the tank reads as a clean
        // directional swell; at 1 the headings scatter over a full turn and it reads as confused
        // chop. This is the control that decides open water versus bathtub.
        float ang = radians(w.dir) + (tpH1((uint)i * 2654435761u + 17u) - 0.5) * 6.2831853 * w.spread;
        float2 dir = float2(cos(ang), sin(ang));

        float k = 6.2831853 / wl;

        // Deep-water dispersion: omega goes as sqrt(k), so the long octaves outrun the short
        // ones. Give every octave one speed and the field slides as a single texture.
        float ph = -t * w.speed * 0.55 * sqrt(k) + tpH1((uint)i * 374761393u + 91u) * 6.2831853;

        // Crest shaping. pow() above 1 pushes everything below the peak toward zero, which
        // broadens the trough and narrows the crest — the asymmetry a sine does not have.
        float sn = sin(dot(q, dir) * k + ph) * 0.5 + 0.5;
        float oct = pow(sn, 1.0 + w.sharp * 3.0) * 2.0 - 1.0;

        h    += oct * amp;
        norm += amp;

        // Advect the next octave by what is under it. Without this the octaves are independent
        // gratings and the sum has visible axis-aligned structure however many you add.
        q += dir * (h * w.warp * wl);

        amp *= clamp(w.gain, 0.05, 0.95);
        wl  /= max(w.lac, 1.05);
    }

    return h / max(norm, 1e-4);
}

// Height and world-space gradient. The gradient is taken by central difference rather than
// analytically because the crest shaping and the inter-octave warp both make the closed form a
// mess, and this is pure ALU on a 512-wide pass — five evaluations of a few sines is nothing
// next to being unable to change the shaping function without re-deriving it.
//
// The step is a sixteenth of the SHORTEST octave present: large enough not to lose precision,
// small enough that the finest scale in the spectrum is still resolved by the difference.
float2 tpAmbient(float2 p, float t, TpSwell w, out float hOut)
{
    if (w.amp <= 1e-7) { hOut = 0.0; return float2(0.0, 0.0); }

    float shortest = max(w.wl, 0.03) / pow(max(w.lac, 1.05), (float)(clamp(w.octaves, 1, 8) - 1));
    float eps = max(shortest * 0.0625, 1e-4);

    float h  = tpSwellH(p, t, w);
    float hx = tpSwellH(p + float2(eps, 0.0), t, w) - tpSwellH(p - float2(eps, 0.0), t, w);
    float hz = tpSwellH(p + float2(0.0, eps), t, w) - tpSwellH(p - float2(0.0, eps), t, w);

    hOut = h * w.amp;
    return float2(hx, hz) * (w.amp / (2.0 * eps));
}

#endif // TP_SIM_HLSLI
