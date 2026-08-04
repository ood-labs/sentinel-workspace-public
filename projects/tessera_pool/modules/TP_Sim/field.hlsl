// TP_Sim / field.hlsl — publish the surface at full resolution, with capillary detail.
//
// The solver runs at half resolution because that is where the wave equation is both stable and
// well resolved for the ripple trains this composition is made of. Publishing a bilinear
// upsample costs nothing and gives consumers a smooth field to sample. What the coarse grid
// genuinely CANNOT carry is the fine chop, so it is added here analytically — into the gradient,
// where it shows as glitter, and only faintly into the height, where the renderer has to be
// able to find the surface in a handful of marching steps.
#include "sim.hlsli"

StructuredBuffer<TpCtl> Ctl : register(t1);
StructuredBuffer<TpRec> Plan : register(t2);
RWTexture2D<float4> FieldOut : register(u0);

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    uint W, H;
    FieldOut.GetDimensions(W, H);
    if (tid.x >= W || tid.y >= H) return;

    float2 uv = ((float2)tid.xy + 0.5) / float2(W, H);
    float4 s = _Tex0.SampleLevel(LinearSampler, uv, 0);

    TpRec tank = Plan[TP_TANK];
    float2 halfXZ = float2(tank.dims.x, tank.dims.z);
    float2 wp = (uv * 2.0 - 1.0) * halfXZ;
    float time = Ctl[0].a.y;

    // THE GRADIENT IS RECOMPUTED HERE, not carried through from the solver.
    //
    // The solver differences its own texels and divides by a cell size it derives from
    // GetDimensions, and the value that arrived downstream was smaller than the true slope by
    // more than an order of magnitude — the water rendered as a mirror-flat sheet while its
    // heights were plainly correct. Rather than calibrate a fudge factor into every consumer,
    // the published slope is measured right here, where the SAME `tex` sets both the sample
    // offset and the world distance it is divided by. That makes it self-consistent by
    // construction: whatever extent the texture actually has, the two cancel.
    uint gw, gh;
    _Tex0.GetDimensions(gw, gh);
    float2 tex = 1.0 / float2(max(gw, 1u), max(gh, 1u));

    float hL = _Tex0.SampleLevel(LinearSampler, uv - float2(tex.x, 0.0), 0).x;
    float hR = _Tex0.SampleLevel(LinearSampler, uv + float2(tex.x, 0.0), 0).x;
    float hD = _Tex0.SampleLevel(LinearSampler, uv - float2(0.0, tex.y), 0).x;
    float hU = _Tex0.SampleLevel(LinearSampler, uv + float2(0.0, tex.y), 0).x;

    float2 world = 2.0 * halfXZ * tex;                 // world units per sample offset
    float2 g = float2((hR - hL) / (2.0 * world.x), (hU - hD) / (2.0 * world.y));

    float dh;
    float2 dg = tpCapillary(wp, time, detail_amp * 0.0012, max(detail_scale, 0.05), dh);

    // COUPLE THE CHOP TO THE WATER'S ACTUAL STATE.
    //
    // This detail is analytic, not simulated: it is added here, after the solver, and animated
    // by its own clock. Left ungated it therefore runs FOREVER and is deaf to every control the
    // sim has — damping, wave speed, wall reflectivity, wave gain, breaking. A tank whose solver
    // had settled to an RMS of 0.00003 still rippled visibly, which is indistinguishable from a
    // physics runaway and impossible to tune out, because none of the tuning reaches it.
    //
    // Still water has no capillary chop. So the amplitude follows the LOCAL wave envelope, using
    // height and velocity together — |h| alone passes through zero twice a cycle and would make
    // the glitter strobe. When the tank calms, the chop calms with it, and the surface can
    // actually reach glass.
    float env = sqrt(s.x * s.x + (s.y * 0.16) * (s.y * 0.16));
    float act = lerp(1.0, saturate(env / max(chop_ref, 1e-5)), saturate(chop_couple));

    FieldOut[tid.xy] = float4(s.x + dh * act, s.y, g.x + dg.x * act, g.y + dg.y * act);
}
