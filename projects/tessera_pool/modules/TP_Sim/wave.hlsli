// TP_Sim / wave.hlsli — one substep of the damped wave equation over the tank footprint.
//
// WHY VELOCITY FORM. The textbook surface solver is h' = 2h - h_prev + lambda^2 * laplacian(h),
// which assumes a FIXED timestep. A Sentinel module's timestep is nothing of the kind: it cooks
// at whatever rate the graph happens to run, which changes the moment a preview is opened. The
// symplectic pair below takes dt explicitly, so the water propagates in real seconds no matter
// how fast the node is cooking, and the damping is an exact exponential rather than a
// per-cook multiply that would erase the surface in milliseconds at 2000 cooks per second.
//
// WHY THE WAVE SPEED IS CLAMPED AND NOT THE TIMESTEP. Explicit integration is only stable while
// c*dt/dx stays under about 0.7. When the graph runs slowly, something has to give. Clamping dt
// would decouple the solver's clock from the source clock, so a 1.15 Hz emitter would stop
// emitting at 1.15 Hz; clamping c instead keeps every event in real time and only makes the
// ripples travel slightly slower. That is the failure mode you want: the surface stays correct
// and merely calms down, instead of quietly running in slow motion or exploding.
//
// SUBSTEPS. Three passes share this file through TP_SUBSTEP. Discrete events — drop impacts and
// the pointer's click impulse — apply on substep 0 only, so they land exactly once per cook no
// matter how many substeps are running. Continuous drives apply every substep, scaled by dt.
#include "sim.hlsli"

// How many passes share this file. Each is one third of a frame.
#define TP_SUBSTEPS 3

StructuredBuffer<TpCtl> Ctl : register(t1);
StructuredBuffer<TpRec> Plan : register(t2);
RWTexture2D<float4> FieldOut : register(u0);

float loadH(int2 p, int2 lim) { return _Tex0.Load(int3(clamp(p, int2(0, 0), lim), 0)).x; }
float safeH(float x) { return (abs(x) < 1e5) ? x : 0.0; }

// distance from p to the segment a->b, all in world units
float segDist(float2 p, float2 a, float2 b)
{
    float2 ab = b - a;
    float t = saturate(dot(p - a, ab) / max(dot(ab, ab), 1e-8));
    return length(p - (a + ab * t));
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    // Scaled-pass discipline: this pass writes a buffer at scale 0.5, so the grid extent comes
    // from the real texture and never from _Resolution.
    uint gw, gh;
    _Tex0.GetDimensions(gw, gh);
    if (tid.x >= gw || tid.y >= gh) return;

    int2 px = int2(tid.xy);
    int2 lim = int2(gw, gh) - 1;
    float2 grid = float2(gw, gh);
    float2 uv = ((float2)px + 0.5) / grid;

    TpCtl st = Ctl[0];
    TpCtl mem = Ctl[1];
    TpRec tank = Plan[TP_TANK];
    float2 halfXZ = float2(tank.dims.x, tank.dims.z);

    // THE SUBSTEP TIMESTEP.
    //
    // Three passes share this file, and each one is a THIRD of a frame — not a whole one. The
    // first version handed every substep the full frame interval, which advanced the solver
    // three frames per cook: waves propagated at three times the authored speed, so the emitted
    // wavelength came out three times longer than the plan drew it, and every continuous source
    // deposited three times its intended energy per frame. Dividing here is what makes
    // substepping do the job it exists for — buying CFL headroom — instead of silently
    // tripling the simulation.
    float dtFull = st.a.z;
    float dtSub = dtFull / (float)TP_SUBSTEPS;

    // Discrete events are tested against the FULL frame interval so they fire exactly once per
    // cook; continuous integration uses the substep.
    float time = st.a.y - (float)(TP_SUBSTEPS - 1 - TP_SUBSTEP) * dtSub;
    float dt = dtSub;
    bool reset = st.d.w > 0.5;

    float4 s = _Tex0.Load(int3(px, 0));

    // SANITIZE ON READ. A persistent buffer is not guaranteed to arrive zeroed, and this one
    // feeds itself: a single non-finite texel on the first cook is fed back on the next cook and
    // poisons the surface for the lifetime of the project, surviving reloads because the
    // buffer survives reloads. It presents as a perfectly flat surface with an RMS of NaN.
    //
    // Written as a magnitude test rather than isfinite() on purpose — a NaN compares false
    // against everything, so this catches NaN and infinity together and cannot be optimised
    // away by fast-math the way an isnan() can.
    bool sane = (abs(s.x) < 1e5) && (abs(s.y) < 1e5);
    float h = sane ? s.x : 0.0;
    float v = sane ? s.y : 0.0;

    if (reset) { FieldOut[px] = float4(0, 0, 0, 0); return; }

    // world position of this cell, and the cell size on each axis (a non-square basin has
    // genuinely anisotropic cells and the Laplacian has to say so)
    float2 wp = (uv * 2.0 - 1.0) * halfXZ;
    float2 cell = (2.0 * halfXZ) / grid;
    float dxmin = min(cell.x, cell.y);

    float c = max(wave_speed, 0.01);
    float cMax = 0.62 * dxmin / max(dt, 1e-5);
    c = min(c, cMax);

    // ---- propagation. Neumann walls: clamping the sample index reflects the wave, which is
    // exactly what a glass tank does and is where the reference's cross-hatched interference
    // in the corners comes from.
    float hL = safeH(loadH(px + int2(-1, 0), lim));
    float hR = safeH(loadH(px + int2( 1, 0), lim));
    float hD = safeH(loadH(px + int2(0, -1), lim));
    float hU = safeH(loadH(px + int2(0,  1), lim));
    float lap = (hL + hR - 2.0 * h) / (cell.x * cell.x)
              + (hD + hU - 2.0 * h) / (cell.y * cell.y);

    // WALL REFLECTIVITY, as a sponge layer rather than a boundary condition.
    //
    // Clamped sampling gives a perfectly reflecting wall, which is what a real glass tank does
    // and which scrambles a ring system within one crossing — every seed converges on the same
    // isotropic chop. The reference's rings are clean and concentric, because its impact was
    // recent and its returns had not come back yet. A graded absorbing band inside the walls
    // buys that permanently: the rings travel their full width and then die instead of coming
    // back through themselves. At wall_reflect = 1 the band vanishes and the tank rings like a
    // real one, which is a different and equally valid look — hence a control, not a constant.
    float2 edge = 1.0 - saturate((1.0 - abs(uv * 2.0 - 1.0)) / max(wall_band, 0.005));
    float sponge = max(edge.x, edge.y);
    float absorb = damping + (1.0 - saturate(wall_reflect)) * sponge * sponge * 14.0;

    // WAVE BREAKING — the loss that actually bounds a driven tank.
    //
    // A tank with sources in it and loss only at the walls is a resonant cavity, and a resonant
    // cavity driven at any frequency it likes grows until something stops it. Linear damping
    // does not stop it: it sets a steady state proportional to drive over damping, and with the
    // damping low enough for ring trains to cross the tank that steady state is enormous. The
    // surface climbs for a minute and then thrashes.
    //
    // Real water solves this by breaking. Past a steepness of roughly 0.6 a wave stops being a
    // wave and starts dumping energy, which is why the sea does not accumulate every storm it
    // has ever had. The same term here makes the surface SELF-LIMITING at any drive setting:
    // below the threshold it costs exactly nothing, and above it the loss climbs steeply.
    float2 slope = float2((hR - hL) / (2.0 * cell.x), (hU - hD) / (2.0 * cell.y));
    float over = max(length(slope) / max(break_slope, 0.02) - 1.0, 0.0);
    float breakLoss = break_gain * over * over;

    v += c * c * lap * dt;
    v *= exp(-max(absorb + breakLoss, 0.0) * dt);
    h += v * dt;
    h *= exp(-(absorb - damping) * dt * 0.55);

    // ---- optional automatic sources, straight off the plan records.
    // `auto_sources` is the master performance switch. The plan records remain editable and
    // visible while dormant; manual preview/renderer gestures bypass this gate below.
    //
    // Note every falloff below squares its argument explicitly. pow(x, 2.0) compiles to
    // exp2(log2(x) * 2), which is NaN for a negative x — and `along` for a swell band is
    // negative on one side of the line by definition.
    float gain = max(wave_gain, 0.0);
    for (uint i = 0u; i < TP_SRCS; i++)
    {
        TpRec r = Plan[TP_SRC_0 + i];
        if (auto_sources != 0 && r.active > 0.5)
        {
            float2 sw = float2(r.pos.x, r.pos.z) * halfXZ;
            float rad = max(r.dims.x, 0.012) * halfXZ.x;
            float amp = r.p0 * gain;

            // A continuous source's DRIVE FREQUENCY is derived, never authored. The plan stores
            // the wavelength because the wavelength is what a viewer actually sees and what the
            // plan canvas draws its ring train at; frequency is then f = c / lambda and the two
            // cannot disagree. Authoring the frequency instead would give the plan a number it
            // could only turn into a picture by knowing the wave speed, which lives here.
            //
            // The floor of eight cells per wavelength is a real guarantee: below it the grid
            // cannot carry the wave the record is asking for, and it degenerates into a
            // checkerboard that looks like corruption rather than like a short ripple.
            float lam = max(r.p2, 8.0 * dxmin);
            float freq = c / lam;

            // CONTINUOUS SOURCES DRIVE WITH A FORCE, NOT A DISPLACEMENT.
            //
            // The first version wrote `h = lerp(h, target, k)` — it CLAMPED the surface to the
            // driver's position inside the source radius. That is a rigid piston, and a rigid
            // piston in a low-loss tank is an energy pump with no upper bound: it holds its
            // own displacement no matter what the surrounding water is doing, so every wave
            // that arrives back at the source is reflected and re-driven, and the field grows
            // without limit. It also cannot be tuned out — the piston's authority is total
            // regardless of the amplitude you ask it for. That was the runaway.
            //
            // A spring instead. It pulls the surface toward the driver, the water can move
            // through it, and it does bounded work per unit time.
            if (r.kind == KIND_EMIT)
            {
                float q = length(wp - sw) / rad;
                float g = exp(-q * q);
                float target = amp * 0.030 * sin(6.2831853 * freq * time);
                v += (target - h) * drive_stiffness * g * dt;
            }
            else if (r.kind == KIND_SWELL)
            {
                // a line source perpendicular to its travel direction: it emits a plane wave
                // that crosses the whole tank, instead of a local ring.
                float2 dir = float2(cos(r.p3), sin(r.p3));
                float band = lam * 0.22;
                float q = dot(wp - sw, dir) / band;
                float g = exp(-q * q);
                // A swell is a LINE source spanning the whole tank: its band covers roughly
                // twenty times the area of a point emitter's disc, so at equal stiffness it
                // deposits twenty times the energy and flattens the ring system into corduroy.
                // The constant below is that area ratio, not a taste setting — it makes a
                // record's stored amplitude mean the same thing whichever kind it is.
                float target = amp * 0.012 * sin(6.2831853 * freq * time);
                v += (target - h) * drive_stiffness * g * 0.05 * dt;
            }
#if TP_SUBSTEP == 0
            else
            {
                // a drop: a discrete dimple, applied on the cook whose interval CROSSES the
                // next impact time. Checked once per cook, not once per substep, or one drop
                // would land three times and be three times as loud as its amplitude claims.
                // Tested against the FULL frame interval, not the substep: this runs on
                // substep 0 only, so a third-of-a-frame window would drop two impacts in three.
                float per = max(r.p1, 0.05);
                float tNow = st.a.y;
                if (floor(tNow / per) > floor((tNow - dtFull) / per))
                {
                    float q = length(wp - sw) / rad;
                    h -= amp * 0.022 * exp(-q * q);
                }
            }
#endif
        }
    }

#if TP_SUBSTEP == 0
    // ---- the pointer. Modelled as a FINGER pressing on the surface, not as an energy source:
    // it drives the height toward a fixed depression inside its radius and lets the surface
    // spring back on its own. An additive push accumulates without bound during a slow drag and
    // blows the tank apart; this cannot, whatever the cook rate.
    {
        float rad = max(pointer_radius, 0.005) * halfXZ.x;
        float rate = saturate(dtFull * 26.0);   // applied once per cook, so full interval

        if (st.d.x > 0.5)
        {
            float q = segDist(wp, (st.b.xy * 2.0 - 1.0) * halfXZ, (st.b.zw * 2.0 - 1.0) * halfXZ) / rad;
            h = lerp(h, -pointer_depth, saturate(exp(-q * q) * rate));
        }
        if (st.d.y > 0.5)
        {
            float q = segDist(wp, (st.c.xy * 2.0 - 1.0) * halfXZ, (st.c.zw * 2.0 - 1.0) * halfXZ) / rad;
            h = lerp(h, -pointer_depth, saturate(exp(-q * q) * rate));
        }
        if (st.d.z > 0.5)
        {
            float q = length(wp - (mem.b.zw * 2.0 - 1.0) * halfXZ) / rad;
            h -= pointer_depth * 1.6 * exp(-q * q);
        }
    }
#endif

    // ---- gradients, central differenced on the NEW height. Written into the field so every
    // consumer interpolates the same smooth normal.
    float2 g2 = float2((hR - hL) / (2.0 * cell.x), (hU - hD) / (2.0 * cell.y));

    // SELF-HEALING BOUND, not a clamp.
    //
    // A plain clamp was the first attempt and it is a trap: it stops NaN, but once a transient
    // pushes the field to the ceiling the field STAYS at the ceiling, because a clamped value
    // is a perfectly finite value that the solver will happily keep. Measured, that is exactly
    // what happened — peak and RMS both pinned at the clamp, the whole surface saturated, and
    // the plan's rim alarm stuck on permanently with no way back short of a manual reset.
    //
    // So the ceiling now BLEEDS ENERGY instead of holding it. Above a height the tank could
    // never legitimately produce — several times the freeboard — velocity is aggressively
    // damped and the height is pulled back toward still water. In normal operation the surface
    // never comes near this and it costs nothing; in the failure regime the field settles back
    // within about a second on its own.
    float ceiling = max(tpTankFree(tank) * 6.0, 0.05);
    float excess = saturate((abs(h) - ceiling) / ceiling);
    if (excess > 0.0)
    {
        v *= exp(-excess * 40.0 * dt);
        h = lerp(h, sign(h) * ceiling, saturate(excess * 8.0 * dt));
    }
    h = clamp(h, -halfXZ.x * 4.0, halfXZ.x * 4.0);
    v = clamp(v, -64.0, 64.0);

    FieldOut[px] = float4(h, v, g2.x, g2.y);
}
