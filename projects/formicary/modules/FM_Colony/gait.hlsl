// FM_Colony / gait.hlsl — where the feet go.
//
// One thread per ant, six legs each. Runs after walk.hlsl because it reads the ant's updated
// position and heading; that ordering is guaranteed by BUFFER DEPENDENCY (this pass reads
// `ants`, which walk writes) rather than by manifest order, which is not an ordering at all.
//
// THE CONTRACT: a planted foot is stored in WORLD space and does not move while it is planted.
// A leg drawn from a body-relative offset slides across the ground with the body, and no amount
// of shading fixes it, because the error is not that the leg looks wrong — it is that the foot
// is not a foot.
//
// The alternating tripod is {left front, left rear, right middle} against {left middle, right
// front, right rear}, half a cycle apart, with a duty factor above 0.5 so the two tripods
// overlap and there is always a moment of six-leg support at the hand-over. That overlap is
// what real insects do and what stops the body reading as though it were falling between steps.
#include "../_shared/formic.hlsli"
#include "colony.hlsli"

RWStructuredBuffer<FmFoot> Feet : register(u0);
StructuredBuffer<FmCtl> Ctl   : register(t1);
StructuredBuffer<FmAnt> Ants  : register(t2);

[numthreads(64, 1, 1)]
void main(uint3 DTid : SV_DispatchThreadID, uint3 GTid : SV_GroupThreadID)
{
    // DISPATCH thread id. With sixteen groups the group-local id would hand every group the
    // same sixty-four ants, so fifteen sixteenths of the feet would never be written at all —
    // and unwritten feet in a persistent buffer stay wherever they last were, which reads as
    // most of the colony dragging a set of legs anchored somewhere across the arena.
    uint i = DTid.x;
    if (i >= FM_MAX_ANTS) return;

    FmCtl ctl = Ctl[0];
    float dt = clamp(ctl.dt, 0.0, 0.05);
    FmAnt a = Ants[i];

    float2 p = a.pos.xz;
    float2 fwd = normalize(a.dir.xz + float2(1e-5, 0.0));
    float beta = clamp(duty, 0.5, 0.85);
    float stride = max(stride_frac, 0.05) * a.size;

    for (uint lg = 0u; lg < FM_LEGS; lg++)
    {
        uint fi = i * FM_LEGS + lg;
        FmFoot f = Feet[fi];

        f.home = fmLegHome(lg, a.size);
        float2 homeW = p + fmRot(float2(f.home.x, f.home.z), fwd);
        float reach = fmLegReach(lg, a.size);

        // On a rebuild — or when a persistent buffer comes back with something impossible in
        // it, which is not a hypothetical for a buffer that survives project reloads — the foot
        // is planted at its neutral point and the cycle starts clean.
        bool bad = !(dot(f.pos, f.pos) < 1e12);

        // TELEPORTED. An emitter releases an ant at a station, which moves the body across the
        // arena in one cook while its feet are still planted where it went dormant. The stance
        // correction below then drags every tarsus the whole distance and MEASURES it as slip —
        // which is exactly right as a measurement and completely wrong as a fact, because the
        // ant did not scuff, it was reseated. Measured before this guard: mean slip 0.48 mm and
        // peaks of 6.58 mm on a 1.5 mm animal, with the gait chart solid red.
        //
        // Six reaches is far beyond anything walking can produce in one cook and far below the
        // width of the arena, so it separates a release from a hard turn without a flag.
        float2 dHome = f.pos.xz - homeW;
        bool teleported = dot(dHome, dHome) > (reach * 6.0) * (reach * 6.0);

        if (ctl.rebuild > 0.5 || bad || teleported || a.active < 0.5)
        {
            f.pos = float3(homeW.x, 0.0, homeW.y);
            f.lift = f.pos;
            f.stance = 1.0;
            f.slip = 0.0;
            f.phase = 0.0;
            Feet[fi] = f;
            continue;
        }

        float lp = frac(a.gait + 0.5 * (float)fmLegGroup(lg));
        f.phase = lp;

        bool wasStance = f.stance > 0.5;
        bool isStance = (lp < beta);

        if (isStance)
        {
            // PLANTED. The foot does not move. The one thing that can move it is running out
            // of leg, and when that happens the distance is MEASURED rather than absorbed —
            // which is the difference between a diagnostic and a fudge.
            //
            // This is not a rare path. On a hard turn the outer legs have further to travel
            // than the stride was sized for, so the correction fires and the gait chart shows
            // slip exactly where the ant turned. That is honest: the ant really did scuff.
            float2 d = f.pos.xz - homeW;
            float l = length(d);
            if (l > reach)
            {
                float2 corrected = homeW + d / max(l, 1e-5) * reach;
                f.slip = length(corrected - f.pos.xz);
                f.pos = float3(corrected.x, 0.0, corrected.y);
            }
            else f.slip = 0.0;

            f.pos.y = 0.0;
            f.stance = 1.0;
        }
        else
        {
            if (wasStance) f.lift = f.pos;      // the swing starts where the step ended

            float st = saturate((lp - beta) / max(1.0 - beta, 1e-3));

            // The target is the ANTERIOR EXTREME POSITION: the neutral point carried half a
            // stride forward along the heading. Aiming at the neutral point instead lands every
            // foot half a stride short, and the ant then walks with its legs permanently
            // trailing behind it — which reads as being dragged rather than walking.
            float2 aep = homeW + fwd * stride * 0.5;

            float2 sw = lerp(f.lift.xz, aep, smoothstep(0.0, 1.0, st));
            // The lift arc. A tarsus that slides flat along the ground during its swing is the
            // other half of the skating look, even when the stance is perfect.
            f.pos = float3(sw.x, sin(3.14159265 * st) * max(step_height, 0.0) * a.size, sw.y);
            f.stance = 0.0;
            f.slip = 0.0;
        }

        Feet[fi] = f;
    }
}
