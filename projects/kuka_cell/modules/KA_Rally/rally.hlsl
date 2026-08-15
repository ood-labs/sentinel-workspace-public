// KA_Rally / rally.hlsl — the ball, and the players trying to hit it.
//
// THE BALL IS NOT TOLD WHERE TO GO. IT IS HIT.
//
// An earlier version scheduled the contact: it decided when and where the ball would be struck
// and wrote the new velocity straight onto it, never asking whether the tool had arrived. The
// arm was an actor hitting a mark, and it read like one.
//
// Now every playing arm's pose is evaluated HERE, with the same `ka_rallyPose` and the same
// joint-limit clamp KA_Pose will apply, so this node knows exactly where every tool is in this
// cook without a feedback link (the graph refuses cycles) and without a frame of lag. The ball
// is then swept against those tools as moving spheres and bounces off whatever it actually
// meets. An arm that is late, short, or out of joint range genuinely misses.
//
// What the arm gets to choose is its SWING, not the outcome. Given where the ball will be, how
// fast it will arrive, and where it wants to send it, `ka_solveSwing` inverts the impulse
// equation for the direction to present the tool along and the speed to swing at. The player
// aims; the physics decides.
#include "../_shared/cell.hlsli"

StructuredBuffer<KaRec> Cell : register(t0);
RWStructuredBuffer<KaBall> Rally : register(u0);

#define SIM_DT   (1.0 / 120.0)
#define SIM_MAX  600           // 5 seconds of lookahead

bool armPlays(KaRec r)
{
    if (r.active < 0.5) return false;
    int c = (int)clamp(r.grp, 0.0, 3.0);
    if (c == 0) return play_a;
    if (c == 1) return play_b;
    if (c == 2) return play_c;
    return play_d;
}

// TRUE horizontal reach at the strike plane — much smaller than the headline figure, because an
// arm meeting a ball above its shoulder has already spent most of its reach going up. Electing
// on the headline number puts arms on balls they cannot physically get under, and now that
// contact is real, that is not a cosmetic error: it is a dropped rally.
float playReach(KaRec r)
{
    KaSpec sp = ka_spec(r.kind, r.size.x);
    float R = sp.l2 + sp.l3 + sp.l4;
    float dy = abs(strike_h - (r.size.y + sp.turret));
    if (dy >= R) return 0.0;
    return (sp.off1 + sqrt(R * R - dy * dy)) * 0.92;
}

float flightTime(float vy)
{
    float v = vy, y = 0.0, t = 0.0;
    for (int i = 0; i < SIM_MAX; i++)
    {
        v -= v * min(drag * abs(v) * SIM_DT, 0.9);
        v -= gravity * SIM_DT;
        y += v * SIM_DT;
        t += SIM_DT;
        if (y <= 0.0 && t > 0.08) break;
    }
    return max(t, 0.25);
}

// Horizontal launch velocity that actually lands on a target under drag. Three damped shooting
// iterations against the real integrator; the naive displacement/flight-time estimate
// under-throws by roughly a third once quadratic drag is involved.
float2 solvePass(float3 p0, float vy, float2 target)
{
    float2 vh = (target - float2(p0.x, p0.z)) / flightTime(vy);
    for (int it = 0; it < 3; it++)
    {
        float3 p = p0, v = float3(vh.x, vy, vh.y);
        float t = 0.0;
        float2 land = float2(p0.x, p0.z);
        bool landed = false;
        for (int i = 0; i < SIM_MAX; i++)
        {
            float py = p.y;
            ka_ballStep(p, v, SIM_DT, gravity, drag);
            t += SIM_DT;
            if (v.y < 0.0 && py >= strike_h && p.y < strike_h)
            { land = float2(p.x, p.z); landed = true; break; }
            if (p.y < ball_radius) break;
        }
        if (!landed) break;
        vh += (target - land) / max(t, 0.25) * 0.85;
    }
    return vh;
}

// This arm's tool position, from the same pose function KA_Pose will use, for a GIVEN record.
// The record is passed in rather than read from the buffer on purpose: the buffer still holds
// the previous cook's assignment while this cook's is being decided, and colliding against a
// tool position one cook out of step with the one being drawn is precisely the mismatch this
// whole design exists to remove.
// Where this arm's tool IS — from the angles it has actually reached, which after rate limiting
// is not the same thing as the angles it was asked for.
float3 toolOfRec(KaBall a, KaRec r)
{
    KaSpec sp = ka_spec(r.kind, r.size.x);
    return ka_toolOf(r, sp, a.a1, a.a2, a.a3, a.a5);
}

// Advance one player's body by dt: solve the target pose, then move each axis toward it no
// faster than that axis can go, and remember where the tool was before the step.
//
// This is the single integrator for a player's joints. KA_Pose reads the result rather than
// recomputing it, so there is no second copy of this state to fall out of step.
void stepBody(inout KaBall a, KaRec r, float3 ball, float dt)
{
    KaSpec sp = ka_spec(r.kind, r.size.x);
    float3 was = ka_toolOf(r, sp, a.a1, a.a2, a.a3, a.a5);

    float t1, t2, t3, t4, t5, t6;
    ka_rallyPose(a, ball, r, sp, lead_time, follow_time, _Time, t1, t2, t3, t4, t5, t6);

    float ms = max(motor_speed, 0.05);
    a.a1 = clamp(ka_rateStepWrap(t1, a.a1, KA_VMAX[0] * ms, dt), KA_LIM[0].x, KA_LIM[0].y);
    a.a2 = clamp(ka_rateStep(t2, a.a2, KA_VMAX[1] * ms, dt), KA_LIM[1].x, KA_LIM[1].y);
    a.a3 = clamp(ka_rateStep(t3, a.a3, KA_VMAX[2] * ms, dt), KA_LIM[2].x, KA_LIM[2].y);
    a.a4 = clamp(ka_rateStep(t4, a.a4, KA_VMAX[3] * ms, dt), KA_LIM[3].x, KA_LIM[3].y);
    a.a5 = clamp(ka_rateStep(t5, a.a5, KA_VMAX[4] * ms, dt), KA_LIM[4].x, KA_LIM[4].y);
    a.a6 = clamp(ka_rateStep(t6, a.a6, KA_VMAX[5] * ms, dt), KA_LIM[5].x, KA_LIM[5].y);

    a.spin = was;
}

// Tool velocity, differenced against last cook — AND CLAMPED, which is not a fudge.
//
// A role change moves the aim point half a metre in a single frame, and half a metre over 16 ms
// differences to thirty metres per second. Fed into the impulse that launched the ball out of
// the hall at 26 m/s and ended the rally every second touch. A real arm's flange does a few
// metres per second, so clamping to the swing speed the solver is allowed to ask for is both the
// fix and the physically honest number.
float3 toolVelOf(KaBall a, float3 toolNow_, float dt)
{
    float3 prev = a.spin;
    if (dot(prev, prev) < 1e-9) return float3(0, 0, 0);      // first cook, no history
    float3 v = (toolNow_ - prev) / max(dt, 1e-4);
    float sp = length(v);
    float cap = max(swing_max, 1.0) * 1.25;
    return (sp > cap) ? v * (cap / sp) : v;                  // backstop; the rate limiter leads
}

[numthreads(1, 1, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    KaBall hdr = Rally[KA_HEADER];
    float dt = clamp(_DeltaTime, 0.0, 0.05);

    float3 bp = hdr.pos;
    float3 bv = hdr.vel;
    float3 spin = hdr.spin;
    float play = hdr.role;
    float serveT = hdr.serveTimer;
    int striker = (int)hdr.strikerIdx;
    int lastS = (int)hdr.lastIdx;
    float rc = hdr.rallyCount;
    float shots = hdr.a1;
    float grounded = hdr.a3;
    float statRallies = hdr.a4;
    float statTouch = hdr.a5;
    float statBest = hdr.a6;

    // The instrumentation record. `dropFlag` here is not a flag on the ball — it remembers
    // whether the ball was above the strike plane last cook, which is what turns a level test
    // into a CROSSING test. `power` remembers whether anything touched it since it went up.
    KaBall st = Rally[KA_STATS];
    float stCross = st.a1, stWhiff = st.a2;
    float stOut = st.a3, stGround = st.a4;
    float stMissSum = st.a5, stMissMax = st.a6;
    bool wasAbove = (st.dropFlag > 0.5);
    bool touchedUp = (st.power > 0.5);

    // ANGULAR VELOCITY, rad/s, kept separately from the ORIENTATION.
    //
    // They were the same field, and that was the bug: the old code did `spin += bv * dt * k`,
    // accumulating the ball's VELOCITY into what the renderer reads as an axis-angle rotation.
    // The axis therefore pointed along the direction of travel, so a ball thrown upward span
    // about the vertical like a top instead of tumbling, and the angle was accumulated path
    // length — an unbounded number that reached a couple of hundred radians in a few minutes and
    // started losing float precision in the renderer's sin/cos.
    //
    // A ball has an angular velocity that changes only when something touches it, and an
    // orientation that is the integral of that. Two quantities, so two fields.
    float3 omega = st.spin;

    float ballR = ball_radius;
    float toolR = tool_radius;
    float strikeH = strike_h;

    KaRec chdr = Cell[KA_HEADER];
    float halfW = max(chdr.bias, 4.0) * 0.5 + 6.0;
    float halfD = max(chdr.flags, 4.0) * 0.5 + 6.0;

    uint playersN = 0u;
    for (uint c0 = 0u; c0 < KA_MAX_ARMS; c0++) if (armPlays(Cell[KA_ARM_0 + c0])) playersN++;
    bool live = rally_on && playersN > 0u;

    // ---------------- serve ----------------
    //
    // SERVE IS AN EDGE, NOT A LEVEL. The button was read as a level, so for every cook the value
    // stayed high it served AGAIN — sixty fresh balls a second, each teleporting to a different
    // arm and resetting the rally under the one already in flight. One press turned the cell into
    // a hailstorm. A button in a per-frame simulation is a moment, and a moment has to be
    // detected against the previous frame; the last press is remembered in the instrumentation
    // record so the edge survives across cooks.
    bool prevServe = (st.pos.x > 0.5);
    bool serveEdge = serve_now && !prevServe;
    st.pos.x = serve_now ? 1.0 : 0.0;

    if (!live) { play = KA_PLAY_IDLE; }
    else if (play == KA_PLAY_IDLE || serveEdge)
    {
        serveT -= dt;
        if (serveT <= 0.0 || serveEdge)
        {
            uint pick = (uint)(ka_rnd(seed + shots * 7.7, 3.0) * (float)playersN);
            uint kk = 0u, chosen = 0u;
            for (uint s0 = 0u; s0 < KA_MAX_ARMS; s0++)
            {
                if (!armPlays(Cell[KA_ARM_0 + s0])) continue;
                if (kk == pick) { chosen = s0; break; }
                kk++;
            }
            // SERVE WITH LIFT. The old serve dropped the ball from just above the strike plane
            // with almost no upward velocity, so it fell through the contact height within a
            // few tenths of a second — before any arm, rate limited to about 105 deg/s, could
            // possibly get under it. The first touch was missed nearly every rally, which meant
            // most "rallies" never started at all. Serving it UP buys the same hang time a real
            // exchange has.
            //
            // The spawn HEIGHT is the other half of that, and it is a separate control because it
            // buys a different thing. Upward velocity buys hang time the arm can use while the
            // ball is still climbing; height buys hang time before the ball ever reaches the
            // strike plane on the way down, which is the window the FIRST receiver actually gets
            // to travel in. Serving from higher up is why the opening touch stops being the one
            // that is always missed.
            KaRec sr = Cell[KA_ARM_0 + chosen];
            bp = float3(sr.pos.x, strikeH + serve_height, sr.pos.y);
            bv = float3(ka_srnd(seed + shots, 11.0) * 1.2,
                        hit_power * 0.90,
                        ka_srnd(seed + shots, 12.0) * 1.2);
            // A served ball is thrown up by hand, so it comes off with a lazy tumble on a random
            // axis. Without this the ball hangs perfectly still until the first contact, which is
            // the one moment the eye is most likely to be looking straight at it.
            omega = float3(ka_srnd(seed + shots, 61.0),
                           ka_srnd(seed + shots, 62.0),
                           ka_srnd(seed + shots, 63.0)) * 2.6 * spin_gain;
            play = KA_PLAY_LIVE; rc = 0.0; lastS = -1; striker = -1;
            shots += 1.0; serveT = serve_delay;
        }
    }

    // ---------------- predict, publish the arc, elect ----------------
    int predArm = -1;
    float3 predPt = bp;
    float3 predVel = bv;
    float predT = -1.0;
    bool dropped = false;

    if (play != KA_PLAY_IDLE)
    {
        float3 p = bp, v = bv;
        float t = 0.0;
        uint written = 0u;
        int sinceSample = 0;
        bool found = false;

        for (int j = 0; j < SIM_MAX; j++)
        {
            float py = p.y;
            ka_ballStep(p, v, SIM_DT, gravity, drag);
            ka_ballFloor(p, v, ballR, restitution);
            t += SIM_DT;

            if (!found && v.y < 0.0 && py >= strikeH && p.y < strikeH)
            {
                // ELECT BY WHO CAN GET THERE, not by who is nearest.
                //
                // The first version scored candidates on horizontal distance to the landing spot.
                // That is the right rule for a point that can teleport and the wrong one for a
                // machine: measured over a full window it elected an arm that then FAILED TO
                // TOUCH THE BALL AT ALL on 43% of committed strokes (318 strokes, 181 contacts).
                // Nearly half the rally's shots were spent on arms that were never going to make
                // it, and each one dropped the ball.
                //
                // So ask the machine question instead. Build the pose the candidate would have to
                // reach, difference it against the joints it is actually sitting at right now, and
                // divide by the motor limits. An arm is a candidate only if that number fits
                // inside the time the ball is giving it.
                float3 hitPt = float3(p.x, strikeH, p.z);
                int best = -1; float bestD = 1e9;
                int fallback = -1; float fallbackNeed = 1e9;
                for (uint b0 = 0u; b0 < KA_MAX_ARMS; b0++)
                {
                    KaRec q = Cell[KA_ARM_0 + b0];
                    if (!armPlays(q)) continue;
                    if ((int)b0 == lastS) continue;
                    float d = length(q.pos - float2(p.x, p.z));
                    if (d > playReach(q)) continue;

                    // A neutral straight-up presentation is enough to price the journey — the
                    // swing line shifts the wrist a little, but A1/A2/A3 carry the travel and they
                    // are set by WHERE the tool has to be, not by which way it is pointing.
                    KaBall cur = Rally[KA_ARM_0 + b0];
                    KaBall probe = cur;
                    probe.pos    = hitPt - float3(0, 1, 0) * ((ballR + toolR) * 0.72);
                    probe.vel    = float3(0, 1, 0);
                    probe.power  = 0.0;
                    probe.radius = t;
                    probe.role   = KA_ROLE_STRIKE;

                    // t = 0 — the pose AT CONTACT, not the pose at election time. Passing the
                    // time-to-contact here instead prices the trip to the arm's WATCHING pose,
                    // which is a different and much cheaper journey, and the test then passes
                    // arms that cannot make the actual strike. That mistake was worth about four
                    // points of contact rate.
                    KaSpec qs = ka_spec(q.kind, q.size.x);
                    float g1, g2, g3, g4, g5, g6;
                    ka_rallyPose(probe, hitPt, q, qs, lead_time, follow_time, 0.0, g1, g2, g3, g4, g5, g6);
                    float need = ka_travelTime(cur.a1, cur.a2, cur.a3, cur.a4, cur.a5, cur.a6,
                                               g1, g2, g3, g4, g5, g6, motor_speed);

                    // Keep the best long shot in case nobody can genuinely make it — somebody
                    // still has to swing, and an arm that arrives late at least gets a deflection.
                    float slack = need - (((int)b0 == striker) ? 0.20 : 0.0);
                    if (slack < fallbackNeed) { fallbackNeed = slack; fallback = (int)b0; }

                    // The budget is NOT the flight time. The arm sits watching until its stroke
                    // starts, so what it actually gets is its own lead window, and the stroke can
                    // stretch to KA_LEAD_MAX for an arm that needs it (see the striker block).
                    // 0.85 rather than 1.0: arriving exactly as the ball does means arriving at
                    // zero tool speed, and the impulse needs the tool still moving through.
                    float budget = min(t, KA_LEAD_MAX);
                    if (need > budget * 0.85) continue;
                    if (slack < bestD) { bestD = slack; best = (int)b0; }
                }
                if (best < 0) best = fallback;
                if (best < 0 && lastS >= 0)
                {
                    KaRec q = Cell[KA_ARM_0 + (uint)lastS];
                    if (armPlays(q) && length(q.pos - float2(p.x, p.z)) <= playReach(q))
                        best = lastS;
                }
                predArm = best; predPt = float3(p.x, strikeH, p.z); predVel = v; predT = t;
                found = true;
                if (best < 0) dropped = true;
                if (best >= 0)
                {
                    KaBall sc = (KaBall)0;
                    sc.pos = predPt; sc.radius = t; sc.role = 1.0;
                    if (written < KA_TRAJ_N) { Rally[KA_TRAJ_0 + written] = sc; written++; }
                    break;
                }
            }

            sinceSample++;
            if (sinceSample >= 12 && written < KA_TRAJ_N)
            {
                sinceSample = 0;
                KaBall s = (KaBall)0;
                s.pos = p; s.radius = t; s.role = 1.0;
                Rally[KA_TRAJ_0 + written] = s; written++;
            }
            if (written >= KA_TRAJ_N && found) break;
        }
        for (uint w = written; w < KA_TRAJ_N; w++)
        {
            KaBall s = (KaBall)0; s.role = 0.0;
            Rally[KA_TRAJ_0 + w] = s;
        }
        striker = predArm;
        play = (predArm >= 0) ? KA_PLAY_LIVE : KA_PLAY_DROP;

        // NOTE — deliberately NOT ending play here.
        //
        // The previous version did: `found` false plus a ball below the strike plane was treated
        // as stranded and play went idle immediately. That is wrong and it made the ball VANISH
        // in mid-air, most visibly in the instant before a contact, because a ball below the
        // plane has no future crossing by definition — while still being perfectly hittable, the
        // collision test being pure geometry that knows nothing about the strike plane.
        //
        // A ball nobody can be elected for is a ball in play that nobody has claimed. It stays
        // live, stays visible, and can still come off any tool it meets. Only the grounded timer
        // below ends it.
    }
    else
    {
        for (uint w2 = 0u; w2 < KA_TRAJ_N; w2++) { KaBall s = (KaBall)0; Rally[KA_TRAJ_0 + w2] = s; }
    }

    // ---------------- per-arm intent ----------------
    for (uint k2 = 0u; k2 < KA_MAX_ARMS; k2++)
    {
        KaBall a = Rally[KA_ARM_0 + k2];
        KaRec r = Cell[KA_ARM_0 + k2];

        if (!live || !armPlays(r))
        {
            a.role = KA_ROLE_NONE; a.radius = -99.0; a.serveTimer = 0.0;
            a.vel = float3(0, 1, 0); a.power = 0.0;
            Rally[KA_ARM_0 + k2] = a;
            continue;
        }

        float recover = max(a.serveTimer - dt, 0.0);
        a.serveTimer = recover;

        if ((int)k2 == striker && play == KA_PLAY_LIVE)
        {
            // THIS ARM'S OWN STROKE WINDOW. Priced the same way the election priced it: build the
            // pose it has to be in when the ball arrives, difference it against the joints it is
            // sitting at, divide by the motor limits. Computed before the commit branch so that a
            // committed arm and an uncommitted one agree on when the stroke started.
            float armLead = lead_time;
            {
                KaSpec rs = ka_spec(r.kind, r.size.x);
                KaBall pb = a;
                pb.pos    = predPt - float3(0, 1, 0) * ((ballR + toolR) * 0.72);
                pb.vel    = float3(0, 1, 0);
                pb.power  = 0.0;
                pb.radius = 0.0;
                pb.role   = KA_ROLE_STRIKE;
                float h1, h2, h3, h4, h5, h6;
                ka_rallyPose(pb, predPt, r, rs, lead_time, follow_time, 0.0, h1, h2, h3, h4, h5, h6);
                float need = ka_travelTime(a.a1, a.a2, a.a3, a.a4, a.a5, a.a6,
                                           h1, h2, h3, h4, h5, h6, motor_speed);
                armLead = clamp(need / 0.85, lead_time, KA_LEAD_MAX);
            }

            // WHERE TO SEND IT. Chosen once per possession and held, so the swing does not
            // rewrite its own target every cook and shiver.
            int aim = (int)a.aimIdx;
            bool needAim = (a.role != KA_ROLE_STRIKE && a.role != KA_ROLE_RECEIVE)
                        || aim < 0 || aim >= (int)KA_MAX_ARMS || aim == (int)k2;
            if (needAim)
            {
                uint cand = 0u;
                for (uint a0 = 0u; a0 < KA_MAX_ARMS; a0++)
                {
                    if ((int)a0 == (int)k2 || (int)a0 == lastS) continue;
                    KaRec q = Cell[KA_ARM_0 + a0];
                    if (!armPlays(q)) continue;
                    float d = length(q.pos - r.pos);
                    if (d >= pass_min && d <= pass_max) cand++;
                }
                aim = -1;
                if (cand > 0u)
                {
                    uint want = (uint)(ka_rnd(seed + shots * 3.1 + (float)k2, 21.0) * (float)cand);
                    uint seen = 0u;
                    for (uint a1 = 0u; a1 < KA_MAX_ARMS; a1++)
                    {
                        if ((int)a1 == (int)k2 || (int)a1 == lastS) continue;
                        KaRec q = Cell[KA_ARM_0 + a1];
                        if (!armPlays(q)) continue;
                        float d = length(q.pos - r.pos);
                        if (d < pass_min || d > pass_max) continue;
                        if (seen == want) { aim = (int)a1; break; }
                        seen++;
                    }
                }
                if (aim < 0)
                {
                    float bestD = 1e9;
                    for (uint a2 = 0u; a2 < KA_MAX_ARMS; a2++)
                    {
                        if ((int)a2 == (int)k2) continue;
                        KaRec q = Cell[KA_ARM_0 + a2];
                        if (!armPlays(q)) continue;
                        float d = length(q.pos - r.pos);
                        if (d < bestD) { bestD = d; aim = (int)a2; }
                    }
                }
            }
            a.aimIdx = (float)aim;

            // COMMIT THE STROKE. Once the swing has started, the direction, the speed and the
            // contact point are frozen and only the countdown keeps updating.
            //
            // Recomputing them every cook — which is what the first physical build did — means
            // the commanded line shifts a few centimetres each frame as the prediction refines,
            // the tool chases a moving target instead of travelling a straight line, and it
            // arrives near the ball rather than through it. It measured 2.3 touches per rally
            // even with assist at 1.0, which is what proved the arms were missing rather than
            // mis-hitting. A player commits to a swing; so does this.
            // COMMIT EARLY — the moment the stroke starts. Measured, not assumed.
            //
            // The obvious idea is that an arm should keep re-aiming as the prediction refines and
            // only lock in at the last moment. It was tried: committing at ~1.6 swing windows
            // (about 0.3 s) instead of at lead_time measured 1.10 touches per rally against 3.11
            // for committing early, at an otherwise identical setting.
            //
            // It loses because the joints are RATE LIMITED. Re-solving the swing line every cook
            // means the tool is chasing a target that moves under it, so it never travels a clean
            // straight path and arrives with neither the right position nor the right velocity. A
            // line frozen early is something limited joints can actually track to the end. For a
            // machine with speed limits, committing beats tracking.
            //
            // WHEN it starts is per-arm, and that resolves the paradox in the numbers above.
            // Raising lead_time globally measured WORSE every time it was tried, which reads as
            // "less warning is better" and cannot be true. It is not true: a longer window helps
            // the one arm that needs the travel and hurts the twenty that do not, because they
            // reach the strike pose early and then stand in it, so the tool is stationary at the
            // instant the ball arrives and the impulse has nothing to give. Uniform lead time
            // trades one arm's problem against everyone else's.
            //
            // So price this arm's actual journey and give it exactly the window it needs, floored
            // at lead_time so a quick arm still swings rather than jabbing.
            float wCommit = armLead;
            bool committed = (a.dropFlag > 0.5);
            if (committed && predT <= wCommit)
            {
                a.radius = predT;
                a.role = KA_ROLE_STRIKE;
                Rally[KA_ARM_0 + k2] = a;
                continue;
            }

            // THE SWING. Solve the outgoing velocity that would reach the receiver, then invert
            // the impulse for the direction to present the tool along and the speed to swing at.
            float vy = hit_power * (1.0 + ka_srnd(seed + a.rallyCount + (float)k2, 31.0) * power_var);
            float2 vh = float2(0, 0);
            if (aim >= 0)
            {
                KaRec tg = Cell[KA_ARM_0 + (uint)aim];
                float2 err = float2(ka_srnd(seed + a.rallyCount * 2.7 + (float)k2, 41.0),
                                    ka_srnd(seed + a.rallyCount * 2.9 + (float)k2, 43.0)) * aim_error;
                float lim = playReach(tg) * 0.72;
                float el = length(err);
                if (el > lim) err *= lim / max(el, 1e-4);
                vh = solvePass(predPt, vy, tg.pos + err);
            }
            float shl = length(vh);
            if (shl > 24.0) vh *= 24.0 / shl;

            float3 n; float s;
            ka_solveSwing(predVel, float3(vh.x, vy, vh.y), tool_bounce, n, s);
            s = clamp(s, 0.0, swing_max);
            if (n.y < 0.05) n = normalize(float3(n.x, 0.05, n.z));   // never swing downward

            a.vel = n;
            a.power = s;
            // The TOOL's target, backed off the ball's centre along the swing line — but to 0.72
            // of the touching distance, NOT to it. A player aims THROUGH a ball, not at its skin.
            //
            // Aiming at exactly (ballR + toolR) puts the two spheres precisely tangent at the
            // nominal instant, which is a knife edge: any error in either direction and they
            // never overlap, the sweep finds nothing, and the arm swings through empty air. It
            // measured 2.1 touches per rally. Overlapping deliberately gives the sweep a real
            // interval to catch, and since it solves for the EARLIEST contact the ball still
            // leaves the moment the surfaces meet — the tool never visibly buries itself.
            a.pos = predPt - n * ((ballR + toolR) * 0.72);
            a.radius = predT;
            // Role STRIKE from lead_time — that is when the arm starts gathering and swinging.
            // COMMIT is separate and much later: until then n, s and the contact point keep
            // being re-solved every cook against the refining prediction.
            a.role = (predT <= armLead) ? KA_ROLE_STRIKE : KA_ROLE_RECEIVE;
            a.dropFlag = (predT <= wCommit) ? 1.0 : 0.0;
        }
        else if (recover > 0.0)
        {
            a.radius = -recover;
            a.role = KA_ROLE_RECOVER;
            a.dropFlag = 0.0;
        }
        else
        {
            a.radius = -99.0;
            a.role = KA_ROLE_WATCH;
            a.aimIdx = -1.0;
            a.dropFlag = 0.0;
        }

        Rally[KA_ARM_0 + k2] = a;
    }

    // ---------------- move the bodies ----------------
    // Every player's joints step toward their target at motor speed. This is the only place a
    // playing arm's pose changes, and it happens after the intent is decided and before the ball
    // is integrated, so the ball is swept against exactly the arms KA_Pose is about to draw.
    for (uint kb = 0u; kb < KA_MAX_ARMS; kb++)
    {
        KaRec r = Cell[KA_ARM_0 + kb];
        if (!armPlays(r)) continue;
        KaBall a = Rally[KA_ARM_0 + kb];
        stepBody(a, r, bp, dt);
        Rally[KA_ARM_0 + kb] = a;
    }

    // ---------------- integrate, and hit whatever the ball actually meets ----------------
    //
    // This runs AFTER the intent is written and the bodies have moved, so every tool position
    // below comes from the record KA_Pose is about to draw. Doing it the other way round —
    // integrating first, against the previous cook's assignment — collides the ball with an arm
    // one frame out of step with the one on screen, the exact mismatch this design removes.
    bool struck = false;
    int struckBy = -1;

    if (play != KA_PLAY_IDLE)
    {
        int steps = (int)clamp(ceil(dt / SIM_DT), 1.0, 8.0);
        float sdt = dt / (float)steps;

        for (int i = 0; i < steps; i++)
        {
            // Earliest contact against any playing tool. EVERY player is tested, not just the
            // elected one — a ball that strays into somebody else's tool really should come off
            // it, and two arms going for the same ball is then something that happens rather
            // than a case anybody had to write.
            // SCHEDULED mode: the elected arm connects when the ball reaches the strike plane
            // inside its reach, and leaves on exactly the velocity its swing was solved for —
            // whether or not the tool got there. This is the old, reliable behaviour, kept as a
            // shipped mode rather than deleted, because "a rally that never dies" and "a rally
            // that is really happening" are different things to want.
            if ((int)contact_mode == 1)
            {
                if (!struck && striker >= 0 && bv.y < 0.0 &&
                    bp.y <= strikeH && bp.y > strikeH - 1.30)
                {
                    KaRec ar = Cell[KA_ARM_0 + (uint)striker];
                    KaBall a = Rally[KA_ARM_0 + (uint)striker];
                    if (armPlays(ar) && length(ar.pos - float2(bp.x, bp.z)) < playReach(ar))
                    {
                        if (strikeH - bp.y < 0.35) bp.y = strikeH;
                        float3 wn = a.vel;
                        bv = bv + wn * ((1.0 + tool_bounce) * (a.power - dot(bv, wn)));
                        omega = cross(wn, bv) / max(ballR, 0.05) * spin_gain * 0.40;
                        struck = true; struckBy = striker;
                        lastS = striker; striker = -1;
                        rc += 1.0; shots += 1.0;
                    }
                }
                ka_ballStep(bp, bv, sdt, gravity, drag);
                ka_ballFloor(bp, bv, ballR, restitution);
                continue;
            }

            // Three contact spheres per arm — flange, wrist, elbow. The flange is the one that
            // is swung and it carries the full tool velocity; the wrist and elbow are BODY, so
            // they move slower and bounce deader. That is what makes a mistimed arm deflect the
            // ball off its forearm instead of letting it sail through the machine.
            float bestT = 1e9; int bestArm = -1; int bestPart = 0;
            for (uint k = 0u; k < KA_MAX_ARMS; k++)
            {
                KaRec r = Cell[KA_ARM_0 + k];
                if (!armPlays(r)) continue;
                KaBall a = Rally[KA_ARM_0 + k];
                if (a.serveTimer > 0.0) continue;                 // still following through
                KaSpec sp = ka_spec(r.kind, r.size.x);
                float3 eW, wW, fW;
                ka_armPoints(r, sp, a.a1, a.a2, a.a3, a.a5, eW, wW, fW);
                float3 tv = toolVelOf(a, fW, dt);

                float th = ka_sweepHit(bp, bv, ballR, fW, tv, toolR, sdt);
                if (th >= 0.0 && th < bestT) { bestT = th; bestArm = (int)k; bestPart = 0; }
                if (body_bounce > 0.01)
                {
                    th = ka_sweepHit(bp, bv, ballR, wW, tv * 0.55, toolR * 0.95, sdt);
                    if (th >= 0.0 && th < bestT) { bestT = th; bestArm = (int)k; bestPart = 1; }
                    th = ka_sweepHit(bp, bv, ballR, eW, tv * 0.30, toolR * 1.25, sdt);
                    if (th >= 0.0 && th < bestT) { bestT = th; bestArm = (int)k; bestPart = 2; }
                }
            }

            if (bestArm >= 0)
            {
                KaRec r = Cell[KA_ARM_0 + (uint)bestArm];
                KaBall a = Rally[KA_ARM_0 + (uint)bestArm];
                KaSpec sp = ka_spec(r.kind, r.size.x);
                float3 eW, wW, fW;
                ka_armPoints(r, sp, a.a1, a.a2, a.a3, a.a5, eW, wW, fW);
                float3 tvFull = toolVelOf(a, fW, dt);

                float3 tn = (bestPart == 0) ? fW : ((bestPart == 1) ? wW : eW);
                float3 tv = tvFull * ((bestPart == 0) ? 1.0 : ((bestPart == 1) ? 0.55 : 0.30));
                float e = tool_bounce * ((bestPart == 0) ? 1.0 : saturate(body_bounce));

                bp += bv * bestT;
                float3 tAt = tn + tv * bestT;
                float3 n = normalize(bp - tAt + float3(0, 1e-5, 0));
                float3 pre = bv;
                bv = ka_bounce(bv, tv, n, e, tool_friction);

                // ASSIST. The outcome the player was aiming for, reconstructed from the swing it
                // committed to, blended over whatever the impulse actually produced. At 0 this
                // line does nothing and the shank stands.
                // only a real flange strike counts as a played shot; a body deflection is not
                if (assist > 0.001 && bestPart == 0 && a.role == KA_ROLE_STRIKE)
                {
                    float3 wn = a.vel;
                    float want = (1.0 + tool_bounce) * (a.power - dot(pre, wn));
                    bv = lerp(bv, pre + wn * want, saturate(assist));
                }

                // SPIN OFF THE TOOL. A struck ball takes its spin from how the surface RUBS past
                // it, not from where it ends up going: the component of the relative velocity
                // along the contact tangent. cross(n, vTan) / r is the rolling relation, so a
                // tool that catches the ball off-centre imparts exactly the topspin or sidespin
                // that glancing blow would really produce, and a dead-centre hit imparts almost
                // none. Set rather than accumulated — the impact defines the new spin.
                float3 vRel = bv - tv;
                float3 vTan = vRel - n * dot(vRel, n);
                omega = cross(n, vTan) / max(ballR, 0.05) * spin_gain * 0.55;
                ka_ballStep(bp, bv, max(sdt - bestT, 0.0), gravity, drag);

                struck = true; struckBy = bestArm;
                lastS = bestArm; striker = -1;
                rc += 1.0; shots += 1.0;
            }
            else
            {
                ka_ballStep(bp, bv, sdt, gravity, drag);
            }

            ka_ballFloor(bp, bv, ballR, restitution);
        }

        // INTEGRATE THE ORIENTATION, and wrap it.
        //
        // The renderer reads `spin` as axis * angle. Adding omega * dt is the small-angle
        // rotation-vector integration — not exact for a tumbling axis, but the error over one
        // frame at these rates is far below what the eye resolves on a six-gore ball.
        //
        // The wrap is not cosmetic. Angle is modulo 2*pi by definition, so letting it climb
        // forever buys nothing and costs everything: the previous version reached a couple of
        // hundred radians within minutes, and sin/cos of a large float32 loses the low bits that
        // ARE the rotation. Wrapping keeps the same orientation with the precision intact.
        omega *= saturate(1.0 - 0.16 * dt);          // air drags the spin down slowly
        spin += omega * dt;
        float sAng = length(spin);
        if (sAng > KA_TAU) spin *= (fmod(sAng, KA_TAU) / sAng);

        // GROUNDED TIMER, which is what the stranded test should have been. A ball low and slow
        // for a sustained period is genuinely finished; a ball low for an instant is a ball
        // somebody is about to dig out. Time, not a single-frame predicate.
        if (bp.y < ballR * 3.0 && length(bv) < 4.0) grounded += dt; else grounded = 0.0;

        // ---- instrumentation: did this descent past the strike plane get touched? ----
        //
        // Counted here, after the collision loop, so `struck` is known for this cook. A crossing
        // is the ball passing DOWN through the strike height; it is the moment somebody was
        // supposed to play it. If nothing touched it between going up and coming back down, that
        // is a whiff, and the distance from the elected arm's tool to the ball is how badly.
        if (struck) touchedUp = true;
        if (bp.y > strikeH + ballR) wasAbove = true;
        else if (wasAbove && bv.y < 0.0)
        {
            wasAbove = false;
            stCross += 1.0;
            if (!touchedUp)
            {
                stWhiff += 1.0;
                int who = (striker >= 0) ? striker : lastS;
                if (who >= 0 && who < (int)KA_MAX_ARMS)
                {
                    // The arm record's `spin` carries the tool's world position from last cook,
                    // so the miss needs no extra FK.
                    float miss = length(Rally[KA_ARM_0 + (uint)who].spin - bp);
                    stMissSum += miss;
                    stMissMax = max(stMissMax, miss);
                }
            }
            touchedUp = false;
        }

        bool out_ = abs(bp.x) > halfW || abs(bp.z) > halfD;
        if (out_ || grounded > 1.2)
        {
            if (out_) stOut += 1.0; else stGround += 1.0;

            // TELEMETRY. A rally has just ended, so book it. Monotonic counters, so any two
            // reads give the average over that interval without needing a reset, and the whole
            // performance picture comes from one record instead of being inferred from two
            // counters and a stopwatch — which is how three of this session's measurements
            // ended up wrong.
            statRallies += 1.0;
            statTouch += rc;
            statBest = max(statBest, rc);

            play = KA_PLAY_IDLE; serveT = serve_delay;
            rc = 0.0; striker = -1; lastS = -1; grounded = 0.0;
        }
    }

    // ---------------- settle the hit ----------------
    for (uint k3 = 0u; k3 < KA_MAX_ARMS; k3++)
    {
        if (!(struck && (int)k3 == struckBy)) continue;
        KaBall a = Rally[KA_ARM_0 + k3];
        a.serveTimer = follow_time;
        a.rallyCount += 1.0;
        a.radius = -follow_time;
        a.role = KA_ROLE_RECOVER;
        a.dropFlag = 0.0;
        Rally[KA_ARM_0 + k3] = a;
    }

    hdr.pos = bp;
    hdr.radius = ballR;
    hdr.vel = bv;
    hdr.role = play;
    hdr.spin = spin;
    hdr.power = hdr.power + (struck ? 1.0 : 0.0);
    hdr.strikerIdx = (float)striker;
    hdr.lastIdx = (float)lastS;
    hdr.rallyCount = rc;
    hdr.serveTimer = serveT;
    hdr.aimIdx = (float)predArm;
    hdr.dropFlag = dropped ? 1.0 : 0.0;
    hdr.a2 = (float)playersN;
    hdr.a3 = grounded;
    hdr.a4 = statRallies;
    hdr.a5 = statTouch;
    hdr.a6 = statBest;
    hdr.a1 = shots;
    Rally[KA_HEADER] = hdr;

    st.a1 = stCross;   st.a2 = stWhiff;
    st.a3 = stOut;     st.a4 = stGround;
    st.a5 = stMissSum; st.a6 = stMissMax;
    st.dropFlag = wasAbove ? 1.0 : 0.0;
    st.power = touchedUp ? 1.0 : 0.0;
    st.role = 0.0;          // never drawn: the canvas and the renderer both skip role 0
    st.radius = -99.0;
    // THE COLLIDER, PUBLISHED SO IT CAN BE DRAWN. In metres, exactly the sphere the sweep above
    // tests against. KA_Robot renders a head of this radius on the flange, so what you see is
    // the thing the ball actually hits rather than a decoration standing near it.
    st.vel = float3(tool_radius, 0.0, 0.0);
    st.spin = omega;        // the ball's angular velocity. hdr.spin is its ORIENTATION.
    Rally[KA_STATS] = st;
}
