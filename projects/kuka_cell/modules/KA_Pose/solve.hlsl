// KA_Pose / solve.hlsl — six joint angles per machine, every cook.
//
// Single-threaded over 48 arms. Each one costs a handful of trig calls; the render pass costs
// several orders of magnitude more.
//
// THE PHASE FIELDS ARE DERIVED FROM PLACEMENT. A wave is not "index * constant" — it is a
// function of where the machine actually stands, so dragging one arm across the cell changes
// when it moves as well as where it is. Five fields are computed from the cell records and each
// pattern picks the one that makes it mean what its name says.
//
// The clock is integrated against _DeltaTime and measured in CYCLES, never rate x absolute time,
// so changing a rate mid-show accelerates the motion instead of teleporting it.
#include "../_shared/cell.hlsli"

StructuredBuffer<KaRec> Cell : register(t0);
StructuredBuffer<KaBall> Rally : register(t1);
RWStructuredBuffer<KaPose> Pose : register(u0);

#define PAT_HOLD    0
#define PAT_WAVE    1
#define PAT_RIPPLE  2
#define PAT_SPIRAL  3
#define PAT_CANON   4
#define PAT_BREATHE 5
#define PAT_AIM     6
#define PAT_SCAN    7
#define PAT_SWAY    8
#define PAT_DRIFT   9
#define PAT_SALUTE  10
#define PAT_FOLD    11

struct KaField
{
    float idx;   // ordinal along the live set
    float rad;   // distance from the cell centre, normalized
    float ang;   // bearing around the cell centre, 0..1
    float axi;   // position along world X, normalized
    float dep;   // position along world Z, normalized
};

struct KaChan { int pat; float rate; float amp; float spread; };

KaChan chanOf(int c)
{
    KaChan k;
    if (c == 1)      { k.pat = (int)pat_b; k.rate = rate_b; k.amp = amp_b; k.spread = spread_b; }
    else if (c == 2) { k.pat = (int)pat_c; k.rate = rate_c; k.amp = amp_c; k.spread = spread_c; }
    else if (c == 3) { k.pat = (int)pat_d; k.rate = rate_d; k.amp = amp_d; k.spread = spread_d; }
    else             { k.pat = (int)pat_a; k.rate = rate_a; k.amp = amp_a; k.spread = spread_a; }
    return k;
}

void patternPose(int pat, float w, float amp, float spread, KaField f,
                 KaRec rec, KaSpec sp, KaRec trec,
                 out float a1, out float a2, out float a3,
                 out float a4, out float a5, out float a6)
{
    a1 = KA_HOME_A1; a2 = KA_HOME_A2; a3 = KA_HOME_A3;
    a4 = KA_HOME_A4; a5 = KA_HOME_A5; a6 = KA_HOME_A6;
    float sd = rec.seed;

    if (pat == PAT_WAVE)
    {
        float ph = w - f.axi * spread * KA_TAU;
        a1 += amp * 0.35 * sin(ph * 0.5);
        a2 += amp * 0.55 * sin(ph);
        a3 += -amp * 0.75 * sin(ph + 0.70);
        a4 += amp * 1.20 * sin(ph * 0.5 + 0.30);
        a5 += amp * 0.60 * sin(ph + 1.40);
        a6 += amp * 1.60 * sin(ph * 0.35);
    }
    else if (pat == PAT_RIPPLE)
    {
        float ph = w - f.rad * spread * KA_TAU;
        a2 += amp * 0.62 * sin(ph);
        a3 += -amp * 0.85 * sin(ph + 0.55);
        a5 += amp * 0.70 * sin(ph + 1.10);
        a4 += amp * 1.40 * sin(ph * 0.6);
    }
    else if (pat == PAT_SPIRAL)
    {
        float ph = w + f.ang * spread * KA_TAU;
        a1 += amp * 1.60 * sin(ph);
        a2 += amp * 0.40 * cos(ph);
        a3 += amp * 0.50 * sin(ph * 0.5);
        // sin rather than an accumulating spin: an unbounded roll would sit on its limit
        // forever and light the limit alarm on every arm, which is noise, not information
        a4 += amp * 3.00 * sin(w * 0.5);
        a6 += amp * 2.40 * sin(w * 0.7 + 1.0);
    }
    else if (pat == PAT_CANON)
    {
        // one phrase, entered at different times. The stagger comes from the ordinal, so the
        // entrance really does travel along the run the layout built.
        float ph = frac((w / KA_TAU) - f.idx * spread * 0.25 + 8.0);
        float env = 0.5 - 0.5 * cos(ph * KA_TAU);
        env = env * env;
        a2 += amp * 0.95 * env;
        a3 += -amp * 1.00 * env;
        a5 += amp * 0.85 * env;
        a4 += amp * 1.80 * env;
    }
    else if (pat == PAT_BREATHE)
    {
        float e = sin(w);
        a2 += amp * 0.38 * e;
        a3 += amp * 0.58 * e;
        a5 += amp * 0.42 * e;
    }
    else if (pat == PAT_AIM)
    {
        // Every arm converges on one moving place. Spread lags each arm around the target's own
        // orbit, so the fleet trails the mark like a comet instead of snapping to it in unison.
        KaRec lag = trec;
        lag.bias = frac(trec.bias - f.idx * spread * 0.055 + 4.0);
        float a1t, a2t, a3t;
        ka_aimAt(rec, sp, ka_targetPos(lag), a1t, a2t, a3t);
        float k = saturate(amp);
        a1 = lerp(a1, a1t, k);
        a2 = lerp(a2, a2t, k);
        a3 = lerp(a3, a3t, k);
        a5 = lerp(a5, 0.0, k);
    }
    else if (pat == PAT_SCAN)
    {
        float ph = w + f.axi * spread * KA_TAU;
        a1 += amp * 1.70 * sin(ph);
        a5 += amp * 0.35 * sin(w * 2.0);
        a4 += amp * 2.00 * sin(w * 0.7);
    }
    else if (pat == PAT_SWAY)
    {
        // a pendulum whose elbow counter-rotates, so the tool stays roughly level while the
        // body leans — the difference between a machine swaying and a machine flailing
        float s = amp * 0.50 * sin(w + f.dep * spread * KA_TAU);
        a2 += s;
        a3 -= s;
        a5 += s * 0.25;
    }
    else if (pat == PAT_DRIFT)
    {
        a1 += amp * 0.90 * sin(w * 0.31 + sd * 1.7);
        a2 += amp * 0.40 * sin(w * 0.23 + sd * 3.1);
        a3 += amp * 0.50 * sin(w * 0.19 + sd * 5.3);
        a4 += amp * 1.50 * sin(w * 0.27 + sd * 2.2);
        a5 += amp * 0.50 * sin(w * 0.37 + sd * 7.1);
        a6 += amp * 2.00 * sin(w * 0.13 + sd * 4.4);
    }
    else if (pat == PAT_SALUTE)
    {
        // fast up, slow down. A symmetric sine cannot make a snap read as a snap.
        float ph = frac((w / KA_TAU) - f.idx * spread * 0.20 + 8.0);
        float env = smoothstep(0.0, 0.10, ph) * (1.0 - smoothstep(0.16, 0.90, ph));
        a2 += -amp * 0.60 * env;
        a3 += amp * 0.55 * env;
        a5 += -amp * 0.95 * env;
        a6 += amp * 2.20 * env;
    }
    else if (pat == PAT_FOLD)
    {
        // a folding front travelling across the cell along X
        float ph = frac((w / KA_TAU) - f.axi * spread * 0.5 + 8.0);
        float fr = saturate(1.0 - abs(ph - 0.5) * 3.2);
        float k = saturate(amp) * fr;
        a2 = lerp(a2, 25.0 * KA_D2R, k);
        a3 = lerp(a3, 138.0 * KA_D2R, k);
        a5 = lerp(a5, -60.0 * KA_D2R, k);
    }
}

[numthreads(1, 1, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    KaPose hdr = Pose[KA_HEADER];

    // FOUR CLOCKS, ONE PER CHANNEL, each wrapped at its own cycle. A single wrapping master
    // clock multiplied by a per-channel rate looks right and is not: at rate 0.7 the product
    // jumps from 0.7 to 0 when the master wraps, and every arm on that channel snaps. Giving
    // each channel its own accumulator also makes `phase` 0 -> 1 exactly one loop for EVERY
    // channel regardless of rate, which is what a motion proof needs.
    float4 acc = float4(hdr.tool.x, hdr.tool.y, hdr.tool.z, hdr.elbow.x);
    float dtc = _DeltaTime * master_rate;
    acc.x = frac(acc.x + dtc * max(rate_a, 0.0) + 1.0);
    acc.y = frac(acc.y + dtc * max(rate_b, 0.0) + 1.0);
    acc.z = frac(acc.z + dtc * max(rate_c, 0.0) + 1.0);
    acc.w = frac(acc.w + dtc * max(rate_d, 0.0) + 1.0);
    float4 chW = (acc + phase.xxxx) * KA_TAU;

    // ---- scan the cell for the phase fields ----
    float minX = 1e9, maxX = -1e9, minZ = 1e9, maxZ = -1e9, maxR = 0.001;
    uint liveN = 0u;
    for (uint i = 0u; i < KA_MAX_ARMS; i++)
    {
        KaRec r = Cell[KA_ARM_0 + i];
        if (r.active < 0.5) continue;
        liveN++;
        minX = min(minX, r.pos.x); maxX = max(maxX, r.pos.x);
        minZ = min(minZ, r.pos.y); maxZ = max(maxZ, r.pos.y);
        maxR = max(maxR, length(r.pos));
    }
    if (liveN == 0u) { minX = -1.0; maxX = 1.0; minZ = -1.0; maxZ = 1.0; }

    KaRec trec = Cell[KA_TARGET];
    float3 ballPos = Rally[KA_HEADER].pos;

    // exponential settle, expressed as a time constant so the smoothing does not change
    // character when the cook rate does
    float tau = max(settle, 0.0) * 0.30;
    float k = (tau > 1e-4) ? exp(-max(_DeltaTime, 1e-5) / tau) : 0.0;

    uint alarms = 0u, floors = 0u, limits = 0u, ord = 0u;
    float maxTool = 0.0;

    for (uint j = 0u; j < KA_MAX_ARMS; j++)
    {
        KaRec r = Cell[KA_ARM_0 + j];
        KaPose p = Pose[KA_ARM_0 + j];

        if (r.active < 0.5)
        {
            p.live = 0.0; p.alarm = 0.0;
            Pose[KA_ARM_0 + j] = p;
            continue;
        }

        KaField f;
        f.idx = (liveN > 1u) ? ((float)ord / (float)(liveN - 1u)) : 0.0;
        f.rad = saturate(length(r.pos) / maxR);
        f.ang = (atan2(r.pos.y, r.pos.x) + KA_PI) / KA_TAU;
        f.axi = saturate((r.pos.x - minX) / max(maxX - minX, 0.001));
        f.dep = saturate((r.pos.y - minZ) / max(maxZ - minZ, 0.001));
        ord++;

        int c = (int)clamp(r.grp, 0.0, 3.0);
        KaChan ch = chanOf(c);
        // The arm's own hand-editable bias rides on top of whichever field the pattern uses,
        // which is what makes "re-roll this one arm" a musically useful edit rather than a
        // cosmetic one.
        float w = ((c == 1) ? chW.y : (c == 2) ? chW.z : (c == 3) ? chW.w : chW.x)
                + r.bias * KA_TAU;
        float amp = ch.amp * master_amp;

        KaSpec sp0 = ka_spec(r.kind, r.size.x);
        KaBall rb = Rally[KA_ARM_0 + j];
        float t1, t2, t3, t4, t5, t6;
        float kUse = k;

        if (rb.role != KA_ROLE_NONE)
        {
            // On the court: the rally assignment REPLACES this arm's channel pattern. Whether
            // an arm plays is KA_Rally's decision, made once, so there is no second switch here
            // that could disagree with it.
            //
            // READ, do not recompute. KA_Rally integrated these joints through the per-axis rate
            // limiter, derived the tool position from them, and bounced the ball off that. There
            // is exactly one integrator for a player's body and this is not it — recomputing the
            // pose here, or smoothing what comes back, would put the drawn arm somewhere the ball
            // was never tested against.
            t1 = rb.a1; t2 = rb.a2; t3 = rb.a3;
            t4 = rb.a4; t5 = rb.a5; t6 = rb.a6;
            kUse = 0.0;
        }
        else
        {
            patternPose(ch.pat, w, amp, ch.spread, f, r, sp0, trec,
                        t1, t2, t3, t4, t5, t6);
        }

        // settle
        t1 = lerp(t1, p.a1, kUse); t2 = lerp(t2, p.a2, kUse); t3 = lerp(t3, p.a3, kUse);
        t4 = lerp(t4, p.a4, kUse); t5 = lerp(t5, p.a5, kUse); t6 = lerp(t6, p.a6, kUse);

        // joint limits. No pattern is allowed to produce a pose the renderer would have to
        // draw as a broken machine, so the clamp is here and the fact that it fired is
        // reported rather than hidden.
        uint al = 0u;
        float c1 = clamp(t1, KA_LIM[0].x, KA_LIM[0].y);
        float c2 = clamp(t2, KA_LIM[1].x, KA_LIM[1].y);
        float c3 = clamp(t3, KA_LIM[2].x, KA_LIM[2].y);
        float c4 = clamp(t4, KA_LIM[3].x, KA_LIM[3].y);
        float c5 = clamp(t5, KA_LIM[4].x, KA_LIM[4].y);
        float c6 = clamp(t6, KA_LIM[5].x, KA_LIM[5].y);
        if (abs(c1 - t1) + abs(c2 - t2) + abs(c3 - t3) +
            abs(c4 - t4) + abs(c5 - t5) + abs(c6 - t6) > 1e-4) al |= KA_ALARM_LIMIT;

        KaSpec sp = ka_spec(r.kind, r.size.x);
        KaChain chn = ka_chain(sp, r.size.y, c1, c2, c3, c5);
        float3 tool  = ka_toWorld(r, chn.flange);
        float3 elbow = ka_toWorld(r, chn.elbow);

        if (tool.y < 0.04) al |= KA_ALARM_FLOOR;
        if (length(chn.flange.xz) < sp.ped_r * 1.15 && tool.y < r.size.y + sp.ped_h + 0.25)
            al |= KA_ALARM_SELF;

        if (al != 0u) alarms++;
        if ((al & KA_ALARM_FLOOR) != 0u) floors++;
        if ((al & KA_ALARM_LIMIT) != 0u) limits++;
        maxTool = max(maxTool, tool.y);

        p.tool = tool; p.elbow = elbow;
        p.alarm = (float)al;
        p.live = 1.0;
        p.a1 = c1; p.a2 = c2; p.a3 = c3; p.a4 = c4; p.a5 = c5; p.a6 = c6;
        p.chan = (float)c;
        p.ph = frac(w / KA_TAU + 8.0);
        Pose[KA_ARM_0 + j] = p;
    }

    hdr.tool  = acc.xyz;
    hdr.elbow = float3(acc.w, (float)liveN, (float)alarms);
    hdr.alarm = (float)floors;
    hdr.live  = (float)limits;
    hdr.a1 = (float)(int)pat_a; hdr.a2 = (float)(int)pat_b;
    hdr.a3 = (float)(int)pat_c; hdr.a4 = (float)(int)pat_d;
    hdr.a5 = maxTool;
    hdr.a6 = 0.0;
    hdr.chan = 0.0;
    hdr.ph = frac(phase);
    Pose[KA_HEADER] = hdr;
}
