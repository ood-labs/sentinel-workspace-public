// TP_Caustics / splat.hlsl — shoot photons through the water surface and record where they land.
//
// This is the FORWARD problem, done forward. The cheap alternative is to stand on the floor and
// estimate brightness from the local divergence of the surface normal, which gives soft bands
// and is shipped here as the `Divergence` method — but it can only ever produce a blurred
// reciprocal of curvature. It cannot produce a CUSP: the bright fold where light from a whole
// annulus of surface collapses onto one line, which is what makes a real caustic look like a
// caustic and is exactly what the reference is full of.
//
// One thread = one patch of water surface. It refracts the sun through that patch's normal,
// finds where the ray meets the tank interior, and adds its energy there. Cusps then form on
// their own, because that is what the physics does when neighbouring rays converge.
//
// The landing surface is the tank interior UNFOLDED into one atlas (see tessera.hlsli), so the
// walls below the waterline get their caustics too — the reference plainly shows them streaking
// down the lower left — rather than only the floor.
//
// ---------------------------------------------------------------------------
// WHY THE ACCUMULATOR IS SPLIT IN HALF INSTEAD OF CLEARED BY A SECOND PASS
//
// Passes are scheduled by BUFFER DEPENDENCY, not by the order they are written in the manifest.
// That makes the obvious clear-then-accumulate pair unusable: nothing links the two, so the
// clear is free to run after the splat, and measured, it does — the accumulator comes out empty
// every cook and the splat looks like it never ran.
//
// The obvious repair — accumulate forever, have a later pass snapshot the totals, and let the
// resolve difference them — fails for the same reason from the other direction. Making the
// resolve read the snapshot buffer creates a dependency that forces the snapshot to run BEFORE
// it, so the snapshot is already up to date with this cook's photons and the difference is
// exactly zero everywhere.
//
// So: the accumulator holds two halves and the cook parity chooses between them. Each cook adds
// into its own half and wipes the OTHER one for the next cook. The two never touch the same
// memory in the same dispatch, so there is no race to lose counts to; the half being read was
// wiped exactly one cook ago and accumulated exactly this cook; and the whole thing needs one
// writer and no assumptions about pass ordering at all.
// ---------------------------------------------------------------------------
#include "../_shared/tessera.hlsli"

StructuredBuffer<TpRec> Plan : register(t1);
StructuredBuffer<float4> Tick : register(t2);

// Three crossing trains at incommensurable headings, returning a GRADIENT only — the height is
// never wanted here, because this scale is defined as being too fine to see. Wavelengths sit
// deliberately above the capillary chop the surface_smooth taps exist to suppress: fine enough
// to focus, coarse enough not to print the fixed crosshatch that smoothing was added to kill.
float2 tpCausDetail(float2 wp, float t, float amp, float scale, float speed)
{
    if (amp <= 1e-7) return float2(0.0, 0.0);

    // A SLOW WARP FIRST, and it is not optional polish.
    //
    // Pure sine trains sum to something quasi-periodic: three of them produce an even lattice of
    // identical cells, which is precisely the fixed crosshatch the surface_smooth taps exist to
    // suppress — reintroduced by the back door and, being regular, far more obviously synthetic
    // than the chop ever was. A real caustic net has cells of visibly different sizes that
    // wander and merge.
    //
    // Displacing the sample point by a long, slow wave before evaluating breaks the lattice
    // apart for two cosines: cells stretch and compress across the floor and the repeat stops
    // being findable.
    float2 w = wp + float2(sin(wp.y * 2.1 - t * speed * 0.21), cos(wp.x * 1.7 + t * speed * 0.17)) * 0.16;

    float2 g = float2(0.0, 0.0);
    float2 dirs[4] = { float2(0.8660, 0.5000), float2(-0.2588, 0.9659),
                       float2(0.6428, -0.7660), float2(-0.9397, -0.3420) };
    float wl[4] = { 0.213, 0.139, 0.091, 0.061 };
    float sp[4] = { 0.55, 0.74, 0.98, 1.27 };
    float wt[4] = { 1.00, 0.66, 0.40, 0.22 };

    [unroll]
    for (int i = 0; i < 4; i++)
    {
        float k = 6.2831853 / max(wl[i] * scale, 1e-3);
        float ph = dot(w, dirs[i]) * k - t * speed * sp[i] * k * 0.30;
        g += dirs[i] * (cos(ph) * k * wt[i]);
    }
    return g * amp;
}
RWStructuredBuffer<uint> Acc : register(u0);

// Fixed-point scale for the atomic accumulator. 1024 was not enough: the conversion to uint
// TRUNCATES, so a corner weight of 0.004 lost a quarter of itself while a centre weight of
// 0.86 lost a tenth of a percent. Which bins get corner weights repeats with the sample
// lattice, so that bias printed a fixed crosshatch across the whole floor that survived every
// amount of jitter and smoothing. Rounding at 16 bits puts the error below one part in ten
// thousand of a single photon.
#define TP_FIX 65536.0

void addBin(int2 b, uint n, uint base, float w)
{
    if (b.x < 0 || b.y < 0 || b.x >= (int)n || b.y >= (int)n) return;
    uint q = (uint)max(w * TP_FIX + 0.5, 0.0);
    if (q > 0u) InterlockedAdd(Acc[base + (uint)b.y * n + (uint)b.x], q);
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    uint n = (uint)atlas_size;
    uint half_ = n * n;
    uint parity = ((uint)max(Tick[0].x, 0.0)) & 1u;
    uint base = parity * half_;
    uint wipe = (1u - parity) * half_;

    // Wipe the half the NEXT cook will fill. Different memory from the half being added to, so
    // this cannot race with any InterlockedAdd in this same dispatch.
    if (tid.x < n && tid.y < n) Acc[wipe + tid.y * n + tid.x] = 0u;

    // RECORD THE HALF WE CHOSE, IN THE BUFFER WE OWN.
    //
    // The obvious thing is for the resolve to read the same cook counter and work the parity
    // out for itself. Measured, it does not: the two passes observe the counter one cook apart,
    // so the resolve reads the half that was just wiped and the atlas comes out uniformly
    // black while the photons are all sitting in the other half. Publishing the choice through
    // the one buffer this pass owns removes the question entirely — the producer states which
    // half it filled and the consumer reads that statement, so no assumption about pass
    // ordering or buffer generation can make them disagree.
    if (tid.x == 0u && tid.y == 0u) Acc[2u * half_] = parity;

    uint S = (uint)sample_grid;
    if (tid.x >= S || tid.y >= S) return;

    // Quality without changing the dispatch: a regular stride through the sample grid. Keeping
    // it regular rather than stochastic matters — a random subset makes the caustic hiss with
    // sampling noise that changes every frame, which reads as broken rather than as cheap.
    uint stride = (uint)max(sample_step, 1);   // not `step`: that shadows the HLSL intrinsic
    if ((tid.x % stride) != 0u || (tid.y % stride) != 0u) return;

    TpRec tank = Plan[TP_TANK];
    TpRec lamp = Plan[TP_LIGHT];
    float3 half3 = tpTankHalf(tank);

    // JITTER, deterministic per thread.
    //
    // A perfectly regular sample lattice beats against the atlas bin lattice and paints a
    // diagonal moire across the whole floor — 2048 samples into 384 bins is 5.33 per bin, and
    // the third of a bin is exactly what you see. Offsetting each sample by a hash of its own
    // index breaks the lattice; hashing the INDEX rather than drawing a fresh random number
    // keeps the offsets fixed forever, so the caustic still changes only when the water does
    // and never hisses with sampling noise of its own.
    // An R2 low-discrepancy offset rather than a white-noise hash: it decorrelates the lattice
    // just as well and distributes far more evenly, so the same photon budget buys a smoother
    // estimate. Both irrational multipliers come from the plastic constant.
    float2 jit = frac(float2(tid.x, tid.y) * float2(0.7548776662, 0.5698402909)
                      + float2(tid.y, tid.x) * float2(0.5698402909, 0.7548776662)) - 0.5;
    // The offset is expressed in ATLAS BIN widths, not sample widths, because the beat being
    // broken is between samples and BINS. At 2048 samples into 384 bins a sample-width jitter
    // moves a photon by a tenth of a bin and changes nothing; a half-bin jitter removes the
    // pattern completely and blurs the estimate by exactly the reconstruction width.
    float2 uv = ((float2)tid.xy + 0.5) / (float)S + jit * jitter_amount / (float)n;

    // SMOOTH THE SURFACE BEFORE REFRACTING THROUGH IT.
    //
    // The published field carries analytic capillary chop in its gradient, which is right for
    // shading — it is the whole difference between water and plastic — and wrong here. Chop at
    // a two-centimetre wavelength has a focal length far shorter than this tank is deep, so in
    // reality it contributes a diffuse wash rather than structure; refracted literally it
    // instead paints a fixed crosshatch over the floor that reads as fabric and completely
    // buries the ripple caustics the composition is about.
    //
    // A finite sun does this smoothing for free in the real world: light arriving over half a
    // degree cannot resolve a focus finer than the source. Four taps is that, cheaply.
    float sm = surface_smooth * 0.5;
    float4 f = (_Tex0.SampleLevel(LinearSampler, uv + float2( sm,  sm), 0)
              + _Tex0.SampleLevel(LinearSampler, uv + float2(-sm,  sm), 0)
              + _Tex0.SampleLevel(LinearSampler, uv + float2( sm, -sm), 0)
              + _Tex0.SampleLevel(LinearSampler, uv + float2(-sm, -sm), 0)) * 0.25;

    float3 p = float3((uv.x * 2.0 - 1.0) * half3.x, f.x, (uv.y * 2.0 - 1.0) * half3.z);

    // CAUSTIC-ONLY MICRO-DETAIL.
    //
    // Caustics ARE curvature. A flat surface focuses nothing, so on calm water there is no
    // structure for gain or contrast to act on — those multiply structure, they cannot invent
    // it. That is why turning the swell down turned the caustics off entirely, and why no
    // downstream knob could bring them back.
    //
    // But real water is never as flat as this field claims. A height field resolved at 512
    // texels across the tank cannot carry millimetre-scale surface structure — structure far
    // too fine to SEE, and yet with a focal length of the order of a pool's depth. That is
    // exactly why a real pool throws a vivid net on a day the surface looks like glass.
    //
    // So this restores that missing scale, and restores it HERE ONLY. It never reaches the
    // shading normal, so the water goes on reading as calm as the swell says it is while the
    // floor comes alive. Physically it is the honest term; artistically it is the one that
    // decouples "how choppy the water looks" from "how strong the caustics are".
    float2 wxz = float2(p.x, p.z);
    float2 dg = tpCausDetail(wxz, Tick[0].y, saturate(caus_detail) * 0.0025,
                             max(caus_scale, 0.05), caus_speed);

    float3 nrm = normalize(float3(-(f.z * focus_gain + dg.x), 1.0, -(f.w * focus_gain + dg.y)));

    float3 sun = normalize(lamp.pos);
    float3 d = -sun;                                              // travelling down toward the water

    float cosI = saturate(dot(-d, nrm));
    float3 t = refract(d, nrm, 1.0 / 1.333);
    if (dot(t, t) < 1e-6) return;                                 // cannot happen air->water, but cheap
    t = normalize(t);

    // Energy: every thread stands for the same HORIZONTAL area of surface, and the flux through
    // a horizontal area does not depend on how the surface under it is tilted — so the only
    // weight that belongs here is how much of the light actually got in.
    float w = 1.0 - tpFresnel(cosI, 1.0, 1.333);

    float tN, tF;
    if (!tpBox(p, t, float3(-half3.x, -half3.y, -half3.z), float3(half3.x, 0.55, half3.z), tN, tF)) return;
    float3 hit = p + t * tF;

    int face = tpInteriorFace(hit, half3);
    float2 auv = tpAtlasUV(hit, face, half3);

    // Bilinear splat: four adds, so a photon between bins does not have to pick one and give
    // the caustic a stair-stepped edge it does not physically have.
    float2 fp = auv * (float)n - 0.5;
    int2 b = int2(floor(fp));
    float2 fr = fp - (float2)b;

    addBin(b + int2(0, 0), n, base, w * (1.0 - fr.x) * (1.0 - fr.y));
    addBin(b + int2(1, 0), n, base, w * fr.x * (1.0 - fr.y));
    addBin(b + int2(0, 1), n, base, w * (1.0 - fr.x) * fr.y);
    addBin(b + int2(1, 1), n, base, w * fr.x * fr.y);
}
