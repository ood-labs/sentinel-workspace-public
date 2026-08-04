// TP_School / swim.hlsl — the steering.
//
// One thread group, one fish per thread, every fish visible to every other through groupshared.
// At this population an exact O(n^2) neighbourhood costs nothing and a spatial hash would only
// add a way to be wrong.
//
// WHY THE BUFFER IS SNAPSHOTTED FIRST.
//
// The school is read and written in the same pass. Without the groupshared copy and the barrier,
// fish 3 would steer off fish 1's NEW position and fish 5's OLD one, so the flock would depend
// on thread scheduling — which reads as a school that behaves slightly differently every run and
// cannot be debugged, because nothing in the parameters is responsible for it.
//
// STEERING, NOT SETTING. Every term below produces an acceleration that is integrated into the
// heading. Assigning a direction outright gives fish that snap between headings like turrets;
// the whole read of a school is that turning takes time and the body leans into it.
#include "school.hlsli"

RWStructuredBuffer<TpFish> Fish : register(u0);
StructuredBuffer<TpSCtl>   Ctl  : register(t1);
StructuredBuffer<TpRec>    Plan : register(t2);

groupshared TpFish gF[16];

[numthreads(16, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID, uint3 gtid : SV_GroupThreadID)
{
    uint i = gtid.x;

    TpRec tank = Plan[TP_TANK];
    float3 half3 = tpTankHalf(tank);
    float shortHalf = min(half3.x, half3.z);

    TpSCtl ctl = Ctl[0];
    float dt = ctl.a.z;
    float t  = ctl.a.y;

    uint n = (uint)clamp((int)fish_count, 1, (int)TP_FISH_MAX);

    float3 lo, hi;
    tpSchoolBounds(tank, wall_margin, depth_bias, depth_band, lo, hi);

    TpFish f = Fish[i];

    // ---- (re)seed -------------------------------------------------------------------------
    // Also catches a fish that has just been switched ON by raising Fish, so a new arrival is
    // placed properly instead of swimming in from the origin.
    bool needInit = (ctl.a.x < 0.5) || (f.active < 0.5 && i < n) || (f.len <= 1e-5);
    if (needInit)
    {
        float s = school_seed + (float)i * 17.0;
        float r0 = tpRnd2(i * 3u + 0u, s);
        float r1 = tpRnd2(i * 3u + 1u, s);
        float r2 = tpRnd2(i * 3u + 2u, s);
        float r3 = tpRnd2(i * 7u + 5u, s + 1.0);
        float r4 = tpRnd2(i * 7u + 6u, s + 2.0);
        float r5 = tpRnd2(i * 7u + 7u, s + 3.0);

        f.pos = lerp(lo, hi, float3(r0, r1, r2));

        float a = r3 * 6.2831853;
        float e = (r4 - 0.5) * 0.5;                       // mostly level; fish do not fly
        f.dir = normalize(float3(cos(a) * cos(e), sin(e), sin(a) * cos(e)));

        f.phase = r5 * 6.2831853;
        f.len   = shortHalf * body_len * lerp(1.0, lerp(0.62, 1.45, r1), saturate(len_var));
        f.speed = swim_speed * lerp(1.0, lerp(0.65, 1.40, r4), saturate(speed_var));
        f.bank  = 0.0;
        f.seed  = s;

        // Colour drift around the authored body colour: value and a little hue rotation, so the
        // school reads as one species rather than as a bag of sweets.
        float3 bc = body_col;
        float v = lerp(0.72, 1.28, r2);
        float3 rot = float3(bc.r, lerp(bc.g, bc.b, 0.35 * (r0 - 0.5) + 0.5), bc.b);
        f.tint = lerp(bc, rot * v, saturate(col_var));
    }

    f.active = (i < n) ? 1.0 : 0.0;
    f.sweep  = beat_amp;      // published, so the renderer marches the amplitude authored here

    gF[i] = f;
    GroupMemoryBarrierWithGroupSync();

    if (i >= n)
    {
        Fish[i] = f;                                       // parked, but kept coherent
        return;
    }

    // ---- flocking -------------------------------------------------------------------------
    float3 sumDir = float3(0, 0, 0);
    float3 sumPos = float3(0, 0, 0);
    float3 sep    = float3(0, 0, 0);
    float  cnt    = 0.0;

    float rad = f_radius * shortHalf;
    float rad2 = rad * rad;

    [loop]
    for (uint j = 0u; j < TP_FISH_MAX; j++)
    {
        if (j >= n || j == i) continue;
        TpFish o = gF[j];
        if (o.active < 0.5) continue;

        float3 d = o.pos - f.pos;
        float d2 = dot(d, d);
        if (d2 > rad2 || d2 < 1e-9) continue;

        float dist = sqrt(d2);
        sumDir += o.dir;
        sumPos += o.pos;
        cnt += 1.0;

        // Separation falls off as 1/r, not 1/r^2 — the square law is so violent at contact that
        // a near miss fires a fish across the tank, and the school pops instead of parting.
        float personal = (f.len + o.len) * 0.9;
        if (dist < personal)
            sep -= d / dist * (personal - dist) / max(personal, 1e-4);
    }

    float3 steer = float3(0, 0, 0);

    if (cnt > 0.0)
    {
        float3 avgDir = sumDir / cnt;
        float3 avgPos = sumPos / cnt;
        if (dot(avgDir, avgDir) > 1e-8)
            steer += (normalize(avgDir) - f.dir) * f_align;
        float3 toC = avgPos - f.pos;
        if (dot(toC, toC) > 1e-8)
            steer += normalize(toC) * f_cohere;
    }
    steer += sep * f_separate;

    // ---- the envelope ---------------------------------------------------------------------
    // A steering force with a soft onset, not a clamp. Clamping pins fish flat against the glass
    // with their noses buried in it, which looks far worse than the occasional excursion this
    // allows — and the excursions are what make the boundary read as avoidance rather than as a
    // wall the fish are glued to.
    // THE SKIN MUST BE NARROWER THAN THE ENVELOPE, and this is the bug that flattened the school.
    //
    // The two terms below are meant to be one-sided: push up only near the floor, down only near
    // the ceiling, and leave a free interior between them. But the skin was a fixed fraction of
    // the TANK, while the vertical envelope is a fraction of a fraction of it — so the skin came
    // out wider than the band was tall, both terms were active everywhere at once, and their sum
    // reduced to (lo + hi - 2*pos)/skin. That is a spring pulling every fish to the exact centre
    // of the band. The school did not choose to swim on one plane; it was being held there, and
    // no amount of Depth Spread could help because widening the band widened the spring with it.
    //
    // Clamping the skin to a fraction of each axis's own extent restores the free interior.
    float3 ext = hi - lo;
    float3 skin = min(float3(shortHalf, half3.y, shortHalf) * 0.22, ext * 0.30);
    skin = max(skin, 1e-4);

    float3 push = float3(0, 0, 0);
    push += max(lo - f.pos + skin, 0.0) / skin;
    push -= max(f.pos - hi + skin, 0.0) / skin;
    steer += push * avoid_gain;

    // ---- roaming ---------------------------------------------------------------------------
    // A free interior is necessary but not sufficient: with nothing asking them to change depth,
    // fish settle at whatever height they were seeded at and stay there, and the school reads as
    // a layer rather than as a volume. So each fish carries its own slowly drifting preferred
    // depth, on its own period, and eases toward it. Individuals migrate up and down through the
    // whole envelope and pass each other while doing it, which is what actually makes the tank
    // look occupied rather than striped.
    float roamT = sin(t * 0.13 + f.seed * 1.9) * 0.5 + 0.5;
    float roamY = lerp(lo.y, hi.y, roamT);
    steer.y += (roamY - f.pos.y) / max(ext.y, 1e-4) * depth_roam;

    // ---- wander ---------------------------------------------------------------------------
    // Each fish gets its own irrational triple, so the school never falls into a shared rhythm.
    float w0 = sin(t * 0.73 + f.seed * 1.7) + 0.6 * sin(t * 1.61 + f.seed * 3.1);
    float w1 = sin(t * 0.57 + f.seed * 2.3) + 0.6 * sin(t * 1.29 + f.seed * 5.7);
    float w2 = sin(t * 0.91 + f.seed * 4.1) + 0.6 * sin(t * 1.87 + f.seed * 2.9);
    // The vertical term is no longer crushed to a third. Fish do not wander as freely up and
    // down as they do horizontally, but at 0.35 the vertical component was small enough that the
    // level-out term below overwhelmed it entirely and nothing ever changed depth.
    steer += float3(w0, w1 * 0.70, w2) * wander * 0.5;

    // ---- level out --------------------------------------------------------------------------
    // Fish swim level. Left free the heading wanders onto the vertical and stays there, and a
    // school hanging nose-down is both wrong and — see below — the worst-conditioned state the
    // steering can be in. This is a real behaviour, not a guard: it is why a shoal reads as a
    // horizontal band even while individual fish rise and dive through it.
    steer.y -= f.dir.y * level_bias;

    // ---- integrate the heading -------------------------------------------------------------
    // Remove the component along the current heading: steering turns a fish, it does not
    // throttle it. Leaving it in makes every avoidance also a brake, and the school stalls out
    // in the corners.
    //
    // BUT THAT PROJECTION HAS A HOLE IN IT, and it is the one that swallowed the school.
    // Steering exactly ANTI-PARALLEL to the heading has no perpendicular component at all, so
    // the projection deletes it entirely and the fish cannot turn. A fish pointing straight down
    // at a floor pushing straight up is precisely that case: the correction is real, large, and
    // invisible to the turn. Nose-down is therefore an attractor — once a fish tips past a
    // certain pitch the restoring force becomes less and less able to act on it — and the whole
    // school ends up parked on the bottom bound pointing at the tiles, held off them only by the
    // hard clamp. Nothing in the parameters can dig it out, because the term that would is being
    // discarded before it is used.
    //
    // So when the perpendicular part collapses, kick the fish sideways off the degenerate axis.
    // Direction of the kick does not matter; that it exists does.
    float3 perp  = steer - f.dir * dot(steer, f.dir);
    float  sLen2 = dot(steer, steer);
    if (sLen2 > 1e-8 && dot(perp, perp) < 0.02 * sLen2)
    {
        float3 kaxis = (abs(f.dir.y) > 0.9) ? float3(1, 0, 0) : float3(0, 1, 0);
        perp += normalize(cross(f.dir, kaxis)) * sqrt(sLen2) * 0.5;
    }
    steer = perp;

    float3 newDir = f.dir + steer * turn_rate * dt;
    if (dot(newDir, newDir) < 1e-8) newDir = f.dir;
    newDir = normalize(newDir);

    // Bank into the turn, from the sign of the turn about the fish's own up axis. This is what
    // stops a turning fish reading as a cutout being slid around.
    //
    // The reference axis has to be chosen away from the heading for the same reason as above —
    // cross(dir, up) degenerates to zero for a vertical fish and normalising it yields garbage
    // that then feeds the bank.
    float3 upW = (abs(f.dir.y) > 0.9) ? float3(1, 0, 0) : float3(0, 1, 0);
    float3 rgt = normalize(cross(f.dir, upW));
    float turnAmt = dot(newDir - f.dir, rgt) / max(dt, 1e-4);
    float targetBank = clamp(-turnAmt * 0.22, -0.9, 0.9);
    f.bank = lerp(f.bank, targetBank, saturate(dt * 6.0));

    f.dir = newDir;

    // Fish speed up in open water and ease off when they are crowded or turning hard.
    float crowd = saturate(cnt / 4.0);
    float target = f.speed * (1.0 - 0.25 * crowd - 0.15 * saturate(abs(turnAmt)));
    f.pos += f.dir * target * dt;

    // Last-resort containment. The steering above should make this unreachable; if it is ever
    // reached, being inside the tank matters more than the fish's dignity.
    float3 hardLo = float3(-half3.x, -half3.y, -half3.z) + f.len * 0.6;
    float3 hardHi = float3( half3.x, -half3.y * 0.02, half3.z) - f.len * 0.6;
    f.pos = clamp(f.pos, hardLo, max(hardHi, hardLo + 1e-3));

    // ---- tail ------------------------------------------------------------------------------
    // Beat rate follows speed. A fish sprinting with a lazy tail is uncanny in a way that is
    // hard to name and impossible to miss, so this is a coefficient and never an absolute.
    float rate = beat_rate * (0.35 + 0.65 * saturate(target / max(swim_speed, 1e-4)));
    f.phase += dt * rate * 6.2831853;
    f.phase = fmod(f.phase, 6.2831853);

    Fish[i] = f;
}
