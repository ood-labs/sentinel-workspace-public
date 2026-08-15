// FM_Colony / walk.hlsl — where the ants go.
//
// One thread per ant, sixteen groups of sixty-four. It used to be a single group with an exact
// groupshared neighbourhood, which was the right answer at 64 ants and is not available at 1024:
// groupshared memory does not span thread groups. Separation now asks the bucket grid, which is
// one cook stale — 16 ms, or a third of a tenth of a body width at walking speed.
//
// STATIONS. Emitters, attractors, repellers and sinks are plan records like any other, and this
// pass is where they become behaviour. An ant is released by an emitter only when the `sta` pass
// has NAMED it — allocation out of a shared pool needs one authority, and this pass has 1024 of
// them running at once.
//
// Steering is STIGMERGIC FIRST: the ant samples the pheromone field with its two antennae and
// turns toward the stronger side, which is literally what an ant does. Route affinity,
// separation, obstacle avoidance and wander sit on top of that.
//
// Everything is expressed as a signed TURN COMMAND rather than as a force vector, because a
// walking animal cannot be pushed sideways — it can only turn and then walk. A force-summing
// steerer produces ants that crab, which is subtly and permanently wrong in a way that is hard
// to name and impossible to unsee.
//
// The gait lives in gait.hlsl. Only the phase is integrated here, because the phase belongs to
// the body's motion and a pass may write exactly one structured buffer.
#include "../_shared/formic.hlsli"
#include "colony.hlsli"

RWStructuredBuffer<FmAnt> Ants : register(u0);
StructuredBuffer<FmCtl>  Ctl   : register(t1);
StructuredBuffer<FmRec>  PlanB : register(t2);
// _Tex3 — the pheromone field, a non-structured texture buffer, auto-declared by the compiler.
StructuredBuffer<FmCell> Grid  : register(t4);
StructuredBuffer<FmSta>  Sta   : register(t5);

// Sample one pheromone channel at a world position. Bilinear, because a nearest-neighbour
// sample makes the gradient piecewise constant, so both antennae read the same texel for most
// of a step — which presents as an ant ignoring the trail it is standing on.
float fmSniff(float2 w, FmRec arena, int channel)
{
    float2 uv = fmWorldToFieldUV(w, arena);
    if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) return 0.0;
    float4 s = _Tex3.SampleLevel(LinearSampler, uv, 0);
    return (channel == FM_CH_FOOD) ? s.r : s.g;
}

// Signed turn toward a desired direction, in the range -1..1 by construction. `cross` is an
// HLSL intrinsic, so the 2D perp-dot is spelled out rather than shadowing it.
float fmTurnToward(float2 want, float2 fwd)
{
    return -(want.x * fwd.y - want.y * fwd.x);
}

[numthreads(64, 1, 1)]
void main(uint3 DTid : SV_DispatchThreadID, uint3 GTid : SV_GroupThreadID)
{
    // DISPATCH thread id, not the group-local one. With sixteen groups the old GTid.x gave
    // every group the same sixty-four ant indices, so fifteen sixteenths of the population would
    // never have been written and the same ants would have been integrated sixteen times.
    uint i = DTid.x;
    if (i >= FM_MAX_ANTS) return;

    FmCtl ctl = Ctl[0];
    float dt = clamp(ctl.dt, 0.0, 0.05);

    FmRec arena = PlanB[FM_ARENA];
    FmRec nest = PlanB[FM_NEST];
    float2 ahalf = fmArenaHalf(arena);
    float2 nestW = fmRecWorld(nest, arena);

    uint n = min((uint)ant_count, FM_MAX_ANTS);
    FmAnt a = Ants[i];

    // --- SEEDING, ALONG THE TRAIL, IN STEADY STATE.
    //
    // The first version put all of them at the nest entrance, which is where a colony really
    // does start — and it was wrong for this show in a way worth recording. Twenty-four ants
    // released at the same instant reach the food at the same instant, load at the same
    // instant and come home as one lockstep column: measured LADEN = 1.00 with the entire
    // population in a single clump. That is a synchronisation artefact of t = 0, not behaviour,
    // and it takes several minutes of drift to disperse.
    //
    // The reference photograph is a crop of a WORKING trail — ants strung out along it, some
    // going each way, at every stage of a round trip. So the colony is seeded in that state:
    // each ant somewhere along a route, facing the way its task implies. This is an initial
    // CONDITION, not a cheat; everything after the first cook is the same simulation either
    // way, and the steady state it starts in is one it would otherwise have to be waited into.
    if (ctl.rebuild > 0.5)
    {
        float s = colony_seed;

        a.size = max(body_len, 0.5) * lerp(0.86, 1.14, fmRnd2(i * 7u + 5u, s));
        a.seed = fmRnd2(i * 7u + 6u, s) * 251.0;
        a.gait = fmRnd2(i * 7u + 4u, s);          // legs out of lockstep too
        a.antenna = fmRnd2(i * 7u + 8u, s);
        a.speed = 0.0;
        a.turn = 0.0;
        a.contact = 0.0;
        a.home = 0.0;
        a.age = 0.0;
        a.fade = 1.0;
        a.pad2 = 0.0;

        // Choose among the ACTIVE routes, weighted by nothing more than availability: the
        // recruitment weighting is the colony's job to discover, not the seeder's to impose.
        uint nAct = 0u;
        uint pick[FM_EDGES];
        for (uint e = 0u; e < FM_EDGES; e++)
            if (PlanB[FM_EDGE_0 + e].active > 0.5) { pick[nAct] = e; nAct++; }

        bool outbound = (fmRnd2(i * 7u + 9u, s) < 0.5);
        a.task = outbound ? 0.0 : 2.0;
        a.load = outbound ? 0.0 : 1.0;
        a.edge = 0.0;

        if (nAct > 0u)
        {
            uint e = pick[fmHashU(i * 2246822519u ^ asuint(s + 2.0)) % nAct];
            FmRec r = PlanB[FM_EDGE_0 + e];
            float2 A = fmRecWorld(PlanB[(uint)r.p0], arena);
            float2 B = fmRecWorld(PlanB[(uint)r.p1], arena);
            float2 ctrl = float2(r.dims.x, r.dims.z);

            float t = lerp(0.06, 0.94, fmRnd2(i * 7u + 1u, s));
            float2 q = fmRoutePoint(A, B, ctrl, t);
            float2 tg = fmRouteTangent(A, B, ctrl, t);
            // Lateral scatter of about a body length, so they read as a trail rather than as
            // beads threaded on a wire.
            float2 lateral = float2(-tg.y, tg.x) * fmSRnd(i * 7u + 2u, s) * a.size * 1.35;

            a.pos = float3(q.x + lateral.x, 0.0, q.y + lateral.y);
            float2 d = tg * (outbound ? 1.0 : -1.0);
            a.dir = float3(d.x, 0.0, d.y);
            a.edge = (float)(e + 1u);
        }
        else
        {
            float ang = fmRnd2(i * 7u + 1u, s) * 6.2831853;
            float rad = max(nest.dims.x, 1.0) * (0.4 + 1.9 * sqrt(fmRnd2(i * 7u + 2u, s)));
            a.pos = float3(nestW.x + cos(ang) * rad, 0.0, nestW.y + sin(ang) * rad);
            float h = fmRnd2(i * 7u + 3u, s) * 6.2831853;
            a.dir = float3(cos(h), 0.0, sin(h));
        }

        // Individuals differ in value and barely in hue. A colony is one species, not a bag of
        // differently coloured insects.
        float3 base = PlanB[FM_PAL_0 + FM_PAL_THORAX].tint;
        a.tint = saturate(base * lerp(0.80, 1.22, fmRnd2(i * 7u + 7u, s)));

        // DORMANT POOL. Nothing is on the plate; every ant is a free slot waiting for an
        // emitter to name it. This is the mode the whole station system exists for, and it is
        // an initial CONDITION exactly like the steady-trail seeding above — not a different
        // simulation, just a different starting state.
        if (((int)seed_mode) == 1)
        {
            a.active = 0.0;
            a.task = FM_TASK_DORMANT;
            a.load = 0.0;
            a.fade = 0.0;
        }
        else
        {
            a.active = 1.0;
        }
    }

    // Beyond the population size the slot is not an ant at all. Inside it, activity belongs to
    // the emitters and the sinks, so it is NOT reasserted here — doing that was the old
    // behaviour and it would resurrect every ant a sink had swallowed, one cook later.
    if (i >= n) { a.active = 0.0; a.task = FM_TASK_DORMANT; Ants[i] = a; return; }

    // ---------------------------------------------------------------------------
    // RELEASE. A dormant ant does nothing at all until the `sta` pass has named it. Scanning
    // the release lists is 16 stations x 8 slots of scalar loads; only dormant ants pay it.
    // ---------------------------------------------------------------------------
    if (a.active < 0.5)
    {
        a.task = FM_TASK_DORMANT;
        a.speed = 0.0;
        a.fade = 0.0;

        // A slot a CONSUME sink took is spent. It is not offered again until the colony is
        // reseeded, which is the whole difference between consume and recycle.
        if (a.pad2 > 0.5) { Ants[i] = a; return; }

        int mine = -1;
        for (uint s = 0u; s < FM_STAS; s++)
        {
            uint rc = (uint)clamp(Sta[s].relCount, 0.0, (float)FM_STA_REL);
            for (uint r = 0u; r < rc; r++)
                if ((uint)(Sta[s].rel[r] + 0.5) == i) { mine = (int)s; break; }
            if (mine >= 0) break;
        }

        if (mine < 0) { Ants[i] = a; return; }

        FmRec st = PlanB[FM_STA_0 + (uint)mine];
        float2 sw = fmRecWorld(st, arena);
        float sr = fmStaRadius(st);
        int smode = (int)(st.p1 + 0.5);

        // The aim lives in pos.y, which is dead space for a placed record — its placement is
        // (fx, 0, fz) in footprint space and the height was never used. The cone half-angle is
        // dims.z, likewise unused by a station.
        float aim = st.pos.y;
        float cone = clamp(st.dims.z, 0.0, 3.14159265);

        float2 rel = float2(0, 0);
        float heading = aim;

        if (smode == 2)
        {
            // RING. Released around the rim facing outward, so a ring emitter reads as a nest
            // mouth boiling over rather than as a point that ants teleport onto.
            float ang = fmRnd2(i * 13u + (asuint(ctl.time) >> 9) + 3u, colony_seed) * 6.2831853;
            rel = float2(cos(ang), sin(ang)) * sr;
            heading = ang;
        }
        else
        {
            // Scattered inside the mouth rather than stacked on one point, or the first frame
            // of a burst is a single ant-shaped lump that then explodes.
            float ang = fmRnd2(i * 13u + 11u, colony_seed + ctl.time) * 6.2831853;
            float rad = sr * 0.45 * sqrt(fmRnd2(i * 13u + 12u, colony_seed + ctl.time));
            rel = float2(cos(ang), sin(ang)) * rad;
        }

        heading += fmSRnd(i * 13u + 17u, colony_seed + ctl.time) * cone;

        a.active = 1.0;
        a.task = FM_TASK_OUT;
        a.load = 0.0;
        a.home = (float)(mine + 1);
        a.age = 0.0;
        a.fade = 0.0;
        a.edge = 0.0;
        a.turn = 0.0;
        a.contact = 0.0;
        a.pos = float3(sw.x + rel.x, a.size * body_ride, sw.y + rel.y);
        a.dir = float3(cos(heading), 0.0, sin(heading));
        // Released WALKING. At zero the ant stands still while it fades up, which reads as a
        // spawn artefact; given a kick it reads as one that came up out of the ground moving.
        a.speed = walk_speed * (0.15 + emit_impulse * 0.85);
    }

    a.age += dt;

    float2 p = a.pos.xz;
    float2 fwd = normalize(a.dir.xz + float2(1e-5, 0.0));

    // ---------------------------------------------------------------------------
    // TASK STATE. Outbound, loading, laden return, unloading.
    // ---------------------------------------------------------------------------
    int task = (int)(a.task + 0.5);
    float2 goal = nestW;
    bool haveGoal = false;

    if (task == 0)
    {
        // Outbound. The goal is only ADOPTED once a cache is inside detection range — before
        // that the ant genuinely does not know where the food is and has nothing to go on but
        // the trail, which is the entire point of a stigmergic system. An outbound ant that
        // homes on a cache from anywhere in the arena has made the pheromone field decorative.
        float best = 1e9;
        for (uint c = 0u; c < FM_CACHES; c++)
        {
            FmRec r = PlanB[FM_CACHE_0 + c];
            if (r.active < 0.5 || r.p0 <= 0.001) continue;
            float2 cw = fmRecWorld(r, arena);
            float d = length(cw - p);
            if (d < best) { best = d; goal = cw; }
        }
        if (best < max(detect_range, 1.0)) haveGoal = true;
        if (best < max(arrive_range, 0.5)) a.task = 1.0;
    }
    else if (task == 1)
    {
        a.load = saturate(a.load + dt / max(load_time, 0.05));
        if (a.load >= 1.0) a.task = 2.0;
    }
    else if (task == 2)
    {
        goal = nestW; haveGoal = true;
        if (length(nestW - p) < max(nest.dims.x, 1.0) * 1.15) a.task = 3.0;
    }
    else
    {
        a.load = max(a.load - dt / max(load_time, 0.05) * 2.0, 0.0);
        goal = nestW; haveGoal = true;
        if (a.load <= 0.0) a.task = 0.0;
    }
    task = (int)(a.task + 0.5);

    float turnCmd = 0.0;

    // --- ANTENNAL SAMPLING. The most ant-like thing in the show: two chemoreceptors held out
    // ahead and to the sides, and a turn toward whichever one smells more.
    {
        int ch = (task >= 2) ? FM_CH_HOME : FM_CH_FOOD;
        float spread = max(antenna_spread, 0.1) * a.size;
        float reach = max(antenna_reach, 0.1) * a.size;
        // The antennae SWEEP, and that is not decoration. A static pair of sensors sits in a
        // local minimum indefinitely; the sweep is what lets an ant that has drifted off a
        // trail find its edge again.
        float sw = sin(a.antenna * 6.2831853) * antenna_sweep;
        float2 la = p + fmRot(float2(-spread + sw * spread, reach), fwd);
        float2 ra = p + fmRot(float2( spread + sw * spread, reach), fwd);
        float sL = fmSniff(la, arena, ch);
        float sR = fmSniff(ra, arena, ch);
        // Normalised by the local total, so the turn responds to the SHAPE of the gradient
        // rather than to how strong the trail happens to be. Without this an ant on a heavily
        // used trail spins on the spot and an ant on a faint one ignores it completely.
        turnCmd += (sL - sR) / (sL + sR + 0.02) * phero_gain;
    }

    // --- ROUTE AFFINITY. The plan's trail network as a weak attractor, so the colony has a
    // trail from the first frame instead of needing minutes of random search to find one. At 0
    // it is switched off entirely and the system is purely emergent.
    if (trail_fidelity > 0.001)
    {
        float bestD = 1e9;
        float2 bestPt = p, bestTan = fwd;
        for (uint e = 0u; e < FM_EDGES; e++)
        {
            FmRec r = PlanB[FM_EDGE_0 + e];
            if (r.active < 0.5) continue;
            float2 A = fmRecWorld(PlanB[(uint)r.p0], arena);
            float2 B = fmRecWorld(PlanB[(uint)r.p1], arena);
            float2 ctrl = float2(r.dims.x, r.dims.z);
            for (uint k = 0u; k <= 12u; k++)
            {
                float t = (float)k / 12.0;
                float2 q = fmRoutePoint(A, B, ctrl, t);
                float d = length(q - p);
                if (d < bestD)
                {
                    bestD = d; bestPt = q;
                    bestTan = fmRouteTangent(A, B, ctrl, t);
                    a.edge = (float)(e + 1u);
                }
            }
        }
        if (bestD < 1e8)
        {
            // A blend of "get back on the trail" and "point the way the trail points".
            // Position alone makes ants oscillate across the centre line; direction alone lets
            // them drift off it and never come back.
            float dirSign = (task >= 2) ? -1.0 : 1.0;
            float2 back = normalize(bestPt - p + float2(1e-5, 0.0)) * saturate(bestD / max(a.size * 3.0, 1.0));
            float2 want = normalize(back + bestTan * dirSign * 1.15);
            turnCmd += fmTurnToward(want, fwd) * trail_fidelity * 3.0;
        }
    }

    if (haveGoal)
        turnCmd += fmTurnToward(normalize(goal - p + float2(1e-5, 0.0)), fwd) * goal_gain;

    // --- SEPARATION AND ANTENNATION. Ants on a trail touch each other constantly; the contact
    // is published so the scope can draw it and the renderer can lift the antennae.
    //
    // Asked of the bucket grid rather than of the population. The radius is CLAMPED to what a
    // 3x3 cell query is guaranteed to cover, because silently reading a smaller neighbourhood
    // than the one the parameter says would present as separation that stops working above a
    // certain slider value — which is indistinguishable from separation that is simply too weak.
    float contact = 0.0;
    {
        float sepR = min(max(separation_radius, 0.2) * a.size, fmGridCellSpan(ahalf));
        int2 c0 = fmGridCell(p, ahalf);

        for (int dz = -1; dz <= 1; dz++)
        for (int dx = -1; dx <= 1; dx++)
        {
            int2 c = c0 + int2(dx, dz);
            if (c.x < 0 || c.y < 0 || c.x >= (int)FM_GRID_X || c.y >= (int)FM_GRID_Z) continue;

            uint gi = fmGridIndex(c);
            uint m = (uint)clamp(Grid[gi].count, 0.0, (float)FM_CELL_CAP);

            for (uint j = 0u; j < m; j++)
            {
                // Skip MYSELF. The grid holds where I was last cook, a third of a millimetre
                // away, which is well inside the separation radius — so without this every ant
                // shoves itself sideways at nearly full weight, every frame, forever.
                if ((uint)(Grid[gi].a[j].idx + 0.5) == i) continue;

                float2 d = p - Grid[gi].a[j].pos;
                float l = length(d);
                if (l > sepR || l < 1e-4) continue;
                float k = 1.0 - l / sepR;
                contact = max(contact, k);
                turnCmd += fmTurnToward(d / l, fwd) * k * k * separation;
            }
        }
    }
    a.contact = lerp(a.contact, contact, saturate(dt * 8.0));

    // ---------------------------------------------------------------------------
    // STATIONS. Attractors pull, repellers push, sinks eat.
    //
    // Attraction is a TURN like everything else in this pass, never a force added to the
    // velocity. An ant dragged sideways toward a beacon crabs, and a crabbing ant is wrong in a
    // way that is hard to name and impossible to unsee once noticed.
    // ---------------------------------------------------------------------------
    float dissolve = 0.0;
    float sinkConsume = 0.0;
    {
        for (uint s = 0u; s < FM_STAS; s++)
        {
            FmRec st = PlanB[FM_STA_0 + s];
            if (st.active < 0.5) continue;

            int kind = (int)(st.kind + 0.5);
            if (kind == 0) continue;                    // an emitter does not steer anybody

            float2 sw = fmRecWorld(st, arena);
            float sr = fmStaRadius(st);
            float2 dv = sw - p;
            float d = length(dv);
            if (d > sr) continue;

            if (kind == 3)
            {
                // SINK. Drain speed rather than a hard ants-per-second quota: an ant inside
                // dissolves at this rate, so a slow sink visibly backs up into a queue at its
                // mouth instead of teleporting a fixed number of arrivals out of existence.
                float bite = max(st.p0, 0.05) * fmStaFalloff(d, sr * 0.85);
                if (bite > dissolve) { dissolve = bite; sinkConsume = (((int)(st.p1 + 0.5)) == 1) ? 1.0 : 0.0; }
                // Still steer INTO it, or ants graze the rim and walk on.
                turnCmd += fmTurnToward(normalize(dv + float2(1e-5, 0.0)), fwd) * 1.4;
                continue;
            }

            float g = fmStaStrength(st, ctl.time) * fmStaFalloff(d, sr) * station_gain;
            if (abs(g) < 1e-4) continue;

            float2 want = normalize(dv + float2(1e-5, 0.0));
            if (kind == 2) want = -want;                // REPEL
            turnCmd += fmTurnToward(want, fwd) * g;
        }
    }

    // --- OBSTACLES. A steering push, not a clamp: a clamp pins an ant flat against a stone
    // with its head in it, which looks far worse than a rare clipped tarsus.
    {
        float od; float2 onrm;
        FM_OBST_QUERY(PlanB, arena, p, od, onrm)
        float margin = a.size * 0.9;
        if (od < margin) turnCmd += fmTurnToward(onrm, fwd) * (1.0 - saturate(od / margin)) * avoid_gain;
    }

    // --- the arena edge, the same way
    {
        float2 push = float2(0, 0);
        float m = a.size * 3.0;
        if (p.x >  ahalf.x - m) push.x -= 1.0;
        if (p.x < -ahalf.x + m) push.x += 1.0;
        if (p.y >  ahalf.y - m) push.y -= 1.0;
        if (p.y < -ahalf.y + m) push.y += 1.0;
        if (dot(push, push) > 0.0) turnCmd += fmTurnToward(normalize(push), fwd) * avoid_gain * 1.6;
    }

    // --- WANDER. Without it a solved steerer walks a dead straight line forever, which is the
    // single most obvious tell that nothing in there is alive. Held for a fraction of a second
    // at a time rather than re-drawn per cook, or at a few thousand cooks per second it
    // averages to exactly zero and does nothing at all.
    turnCmd += (fmRnd(floor(ctl.time * 4.0), a.seed) - 0.5) * 2.0 * wander;

    // ---------------------------------------------------------------------------
    // INTEGRATE. Turn rate limited, because an ant has a body.
    // ---------------------------------------------------------------------------
    float maxTurn = radians(max(turn_rate, 1.0));
    float yaw = clamp(turnCmd, -1.0, 1.0) * maxTurn;
    a.turn = lerp(a.turn, yaw, saturate(dt * 10.0));

    float ca = cos(yaw * dt), sa = sin(yaw * dt);
    fwd = normalize(float2(fwd.x * ca - fwd.y * sa, fwd.x * sa + fwd.y * ca));
    a.dir = float3(fwd.x, 0.0, fwd.y);

    // Speed. A loading or unloading ant is stopped; a laden one is slower. Approached rather
    // than assigned, so a stop and a start read as acceleration instead of a jump.
    float target = walk_speed;
    if (task == 1 || task == 3) target = 0.0;
    else if (task == 2) target *= lerp(1.0, laden_speed, a.load);
    target *= lerp(0.82, 1.18, fmRnd2(i * 29u + 3u, a.seed));
    a.speed = lerp(a.speed, target, saturate(dt * 6.0));

    p += fwd * a.speed * dt;
    a.pos = float3(p.x, a.size * body_ride, p.y);
    a.antenna = frac(a.antenna + dt * antenna_rate);

    // ---------------------------------------------------------------------------
    // THE GAIT PHASE.
    //
    // Stride length is chosen first and the step FREQUENCY is derived from it, never the other
    // way round. With f = v * beta / stride, the ground covered during one stance phase is
    // exactly the stride, so a planted foot is never REQUIRED to slide. Pick the frequency
    // independently — as an authored "steps per second" — and every foot skates by the
    // difference between the two, which is the classic procedural-walk failure and is entirely
    // invisible in a still frame.
    // ---------------------------------------------------------------------------
    float stride = max(stride_frac, 0.05) * a.size;
    float beta = clamp(duty, 0.5, 0.85);
    a.gait = frac(a.gait + (a.speed * beta / max(stride, 1e-3)) * dt);

    // ---------------------------------------------------------------------------
    // PRESENCE. Resolved here, once, rather than incremented earlier and decremented later —
    // an ant standing in a sink would otherwise have the two rates cancel and hover at half
    // size forever, which is exactly the kind of bug that looks like an art direction choice.
    // ---------------------------------------------------------------------------
    float rate = dt / max(emerge_time, 0.02);
    if (dissolve > 0.0)
    {
        a.fade = saturate(a.fade - rate * dissolve);
        if (a.fade <= 0.02)
        {
            a.active = 0.0;
            a.task = FM_TASK_DORMANT;
            a.load = 0.0;
            a.speed = 0.0;
            a.home = 0.0;
            a.fade = 0.0;
            // A CONSUME sink spends the slot. Nothing offers it again until a reseed, which is
            // the entire difference between consuming an ant and recycling one.
            a.pad2 = sinkConsume;
        }
    }
    else
    {
        a.fade = saturate(a.fade + rate);
    }

    Ants[i] = a;
}
