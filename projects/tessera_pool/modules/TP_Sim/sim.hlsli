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

#endif // TP_SIM_HLSLI
