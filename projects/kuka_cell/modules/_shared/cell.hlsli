// cell.hlsli — the shared contract for the kuka_cell show.
//
// Four nodes read this file and nothing else defines these numbers:
//   KA_Cell   owns the arm records (where every base sits). Plan authority.
//   KA_Rally  owns the ball and the rally. Reads the cell, elects strikers.
//   KA_Pose   reads both, produces joint angles + forward kinematics.
//   KA_Robot  reads all three and draws.
//
// Link lengths live HERE rather than in the renderer because the plan draws reach circles,
// the pose node solves FK, and the renderer builds geometry — three consumers of one set of
// dimensions. Two of them disagreeing is how a reach circle stops meaning anything.
#ifndef KA_CELL_HLSLI
#define KA_CELL_HLSLI

#define KA_MAX_ARMS  48u
#define KA_HEADER     0u
#define KA_ARM_0      1u
// The Point At target lives in the CELL buffer, not in KA_Pose, because it is a place in the
// cell — and a place in the cell is the plan authority's to own. That is also what makes it
// draggable on the floor plan instead of being three numbers in a properties panel.
#define KA_TARGET    (KA_ARM_0 + KA_MAX_ARMS)
#define KA_RECORDS   (KA_TARGET + 1u)

#define KA_PI  3.14159265
#define KA_TAU 6.28318531
#define KA_D2R 0.01745329

// record flags
#define KF_EDITED    1u
#define KF_SELECTED  2u
#define KF_OVERLAP   4u   // derived every cook by KA_Cell: envelope intersects a neighbour
#define KF_OUTSIDE   8u   // derived every cook: base sits outside the declared cell

// alarm bits on the pose record
#define KA_ALARM_FLOOR  1u   // tool tip has gone below the floor plane
#define KA_ALARM_LIMIT  2u   // a joint is sitting on a limit
#define KA_ALARM_SELF   4u   // forearm has folded into the arm's own pedestal

// ---------------------------------------------------------------------------
// Records
// ---------------------------------------------------------------------------
// 12 floats / 48 bytes, tightly packed. float2 members sit on 8-byte offsets.
struct KaRec
{
    float2 pos;     // cell floor position, metres. x = right, y = depth (world Z)
    float2 size;    // x = model scale multiplier, y = pedestal height, metres
    float  yaw;     // base heading, radians. 0 faces +X
    float  grp;     // control channel 0..3
    float  kind;    // frame size 0 Compact / 1 Standard / 2 Heavy
    float  bias;    // per-arm choreography phase bias, 0..1. hand editable
    float  seed;
    float  flags;
    float  active;
    float  spare;
};

// header (index 0) field usage — kept in one place so the canvas and the state pass agree
//   pos.x   layout signature
//   pos.y   selected index + 1 (0 = nothing selected)
//   size.x  drag strip: 0 none, 1 plan, 2 elevation
//   size.y  grab offset x
//   yaw     grab offset y
//   grp     live arm count
//   kind    overlap pair count
//   bias    cell width  (republished for downstream + the canvas)
//   seed    reseed salt
//   flags   cell depth
//   active  1

// The renderer's durable UI state. One record, 16 bytes. Small because it should stay small:
// this is for things a KEY or a GESTURE changes, which cannot be parameters because a shader
// cannot write one. Anything a slider can express belongs in Properties instead.
struct KaUi
{
    float shown;        // is the Scope showing
    float prevParam;    // last seen scope_on, to detect the checkbox moving
    float init;         // 0 until the buffer has been adopted from the parameter once
    float timer;        // seconds in the current dwell, for the timed cycle
    float prevTouch;    // last seen cumulative contact count, for the per-volley cut
    float s1, s2, s3;
};

// 16 floats / 64 bytes. float3 members deliberately sit on 16-byte offsets.
struct KaPose
{
    float3 tool;    // world tool-flange centre, metres
    float  alarm;   // KA_ALARM_* bits
    float3 elbow;   // world elbow (A3) centre, metres
    float  live;    // 1 when this arm is active
    float  a1, a2, a3, a4;
    float  a5, a6;
    float  chan;    // which pattern channel drove this arm
    float  ph;      // the 0..1 phase this arm ran at, for the instrument
};

// ---------------------------------------------------------------------------
// Frame dimensions
// ---------------------------------------------------------------------------
// Derived from a KR QUANTEC-class 6-axis arm, in metres, at scale 1.
//   ped_r/ped_h   cast pedestal
//   turret        height of the A2 axis above the floor
//   off1          lateral offset of the A2 axis from the A1 column
//   l2            A2 -> A3   (the "thigh")
//   l3            A3 -> A5   (the forearm)
//   l4            A5 -> flange face
//   girth         overall casting thickness multiplier
struct KaSpec
{
    float ped_r, ped_h, turret, off1, l2, l3, l4, girth;
};

KaSpec ka_spec(float kind, float scale)
{
    KaSpec s;
    int k = (int)clamp(kind, 0.0, 2.0);
    // Each frame gets its OWN proportions, not one silhouette scaled three ways: a compact arm
    // is relatively stubbier and thicker for its length, a heavy arm relatively longer-limbed.
    if (k == 0)      { s.ped_r = 0.30; s.ped_h = 0.20; s.turret = 0.50; s.off1 = 0.20; s.l2 = 0.62; s.l3 = 0.60; s.l4 = 0.14; s.girth = 1.20; }
    else if (k == 2) { s.ped_r = 0.62; s.ped_h = 0.34; s.turret = 0.92; s.off1 = 0.46; s.l2 = 1.62; s.l3 = 1.66; s.l4 = 0.34; s.girth = 1.14; }
    else             { s.ped_r = 0.46; s.ped_h = 0.26; s.turret = 0.68; s.off1 = 0.34; s.l2 = 1.15; s.l3 = 1.20; s.l4 = 0.24; s.girth = 1.00; }
    float m = max(scale, 0.05);
    s.ped_r *= m; s.ped_h *= m; s.turret *= m; s.off1 *= m;
    s.l2 *= m; s.l3 *= m; s.l4 *= m;
    return s;
}

// The live Point At target. Anchor + orbit, resolved from ONE record so the plan diagram, the
// pose solver and the renderer's scope all aim at the same place with no published second copy.
//   pos     orbit anchor on the floor (x, z)   size.x  height    size.y  orbit radius
//   yaw     orbit rate (rev/s)                 bias    orbit phase 0..1, integrated by KA_Cell
float3 ka_targetPos(KaRec t)
{
    float a = t.bias * KA_TAU;
    return float3(t.pos.x + cos(a) * t.size.y, t.size.x, t.pos.y + sin(a) * t.size.y);
}

// Horizontal reach: how far the flange can get from the A1 column. This is the radius the plan
// draws and the number the overlap test uses, so it is derived from the spec, never typed twice.
float ka_reach(KaSpec s) { return s.off1 + s.l2 + s.l3 + s.l4; }
float ka_reachOf(KaRec r) { return ka_reach(ka_spec(r.kind, r.size.x)); }

// Full standing height with the arm vertical — the elevation strip's envelope.
float ka_rise(KaSpec s, float pedestal) { return pedestal + s.turret + s.l2 + s.l3 + s.l4; }

// ---------------------------------------------------------------------------
// Home pose — transcribed from the reference photograph
// ---------------------------------------------------------------------------
// a1 base yaw, a2 shoulder pitch (0 = "thigh" straight up, + leans toward the heading),
// a3 elbow bend RELATIVE to the thigh (0 = straight continuation), a4 forearm roll,
// a5 wrist pitch, a6 flange roll. All radians.
#define KA_HOME_A1  0.0
#define KA_HOME_A2  (-15.0 * KA_D2R)
#define KA_HOME_A3  ( 70.0 * KA_D2R)
#define KA_HOME_A4  0.0
#define KA_HOME_A5  ( 45.0 * KA_D2R)
#define KA_HOME_A6  0.0

// MAXIMUM AXIS SPEEDS, rad/s. A KR QUANTEC-class arm does roughly 105/101/107/136/129/206 deg/s
// on A1..A6, and those are the numbers below.
//
// Without them an arm is a teleporter: the pose is whatever the IK returns this cook, so a
// change of role or of elected striker relocates the whole machine between two frames. It reads
// as snapping, and it is also what makes the tool velocity meaningless — half a metre in one
// frame differences to thirty metres per second.
//
// Rate limiting is what turns a sequence of commanded poses into a MOVEMENT, and it means an arm
// that is asked for too much simply does not get there in time. That is the honest failure and
// the one worth having.
static const float KA_VMAX[6] = { 1.833, 1.763, 1.868, 2.374, 2.251, 3.595 };

// Step one joint toward its target no faster than the motor allows.
float ka_rateStep(float target, float prev, float vmax, float dt)
{
    float d = target - prev;
    float m = max(vmax * dt, 1e-6);
    return prev + clamp(d, -m, m);
}
// A1 can wrap, so it takes the shortest arc rather than unwinding the long way round.
float ka_rateStepWrap(float target, float prev, float vmax, float dt)
{
    float d = atan2(sin(target - prev), cos(target - prev));
    float m = max(vmax * dt, 1e-6);
    return prev + clamp(d, -m, m);
}

// The same limits read FORWARDS: how many seconds this arm needs to get from where it is to a
// pose, when every axis moves flat out. The slowest axis decides, because they travel together.
//
// This is what lets the election ask the only question that matters to a machine with speed
// limits — "can you actually be there?" — instead of the question a point mass would ask, which
// is "are you nearest?". Those give different answers surprisingly often: the arm standing
// closest to where the ball will land is frequently facing the wrong way, and 185 degrees of A1
// at 105 deg/s is 1.8 seconds it does not have, while an arm a metre further away is already
// pointing at the spot.
// The longest stroke window any arm may claim. A ceiling rather than a setting: past about two
// seconds the arm is no longer swinging, it is standing in the finished pose waiting for the ball
// to catch up, and a stationary tool cannot impart an impulse.
static const float KA_LEAD_MAX = 2.0;

float ka_travelTime(float c1, float c2, float c3, float c4, float c5, float c6,
                    float t1, float t2, float t3, float t4, float t5, float t6,
                    float mspd)
{
    float d[6];
    d[0] = abs(atan2(sin(t1 - c1), cos(t1 - c1)));   // A1 takes the short way round
    d[1] = abs(t2 - c2);
    d[2] = abs(t3 - c3);
    d[3] = abs(t4 - c4);
    d[4] = abs(t5 - c5);
    d[5] = abs(t6 - c6);
    float worst = 0.0;
    for (int i = 0; i < 6; i++)
        worst = max(worst, d[i] / max(KA_VMAX[i] * max(mspd, 0.01), 1e-4));
    return worst;
}

// Joint limits, KUKA-plausible and applied in KA_Pose so no pattern can produce a pose the
// renderer would have to draw as a broken machine.
static const float2 KA_LIM[6] = {
    float2(-185.0, 185.0) * KA_D2R,
    float2( -70.0, 115.0) * KA_D2R,
    float2( -30.0, 150.0) * KA_D2R,
    float2(-350.0, 350.0) * KA_D2R,
    float2(-125.0, 125.0) * KA_D2R,
    float2(-350.0, 350.0) * KA_D2R
};

// ---------------------------------------------------------------------------
// Forward kinematics. ONE implementation: the pose node publishes the results, the plan draws
// them, the renderer builds its links from the same chain.
// ---------------------------------------------------------------------------
float2x2 ka_rot2(float a) { float c = cos(a), s = sin(a); return float2x2(c, -s, s, c); }

// Rotate a vector about world +Y by `a`.
float3 ka_yaw(float3 v, float a)
{
    float c = cos(a), s = sin(a);
    return float3(v.x * c + v.z * s, v.y, -v.x * s + v.z * c);
}

// Joint centres in the arm's LOCAL frame (x = along the heading, y = up, z = lateral),
// before the base yaw and the cell position are applied.
struct KaChain
{
    float3 shoulder;   // A2
    float3 elbow;      // A3
    float3 wrist;      // A5
    float3 flange;     // A6 face centre
    float3 fwdArm;     // unit direction of the forearm (A3 -> A5)
    float3 fwdThigh;   // unit direction of the thigh (A2 -> A3)
    float3 fwdTool;    // unit direction of the tool axis (A5 -> flange)
};

KaChain ka_chain(KaSpec s, float pedestal, float a1, float a2, float a3, float a5)
{
    KaChain c;
    // The arm plane. a2 is measured from straight up, toward +x.
    float2 dThigh = float2(sin(a2), cos(a2));
    float2 dArm   = float2(sin(a2 + a3), cos(a2 + a3));
    float2 dTool  = float2(sin(a2 + a3 + a5), cos(a2 + a3 + a5));

    float2 sh = float2(s.off1, pedestal + s.turret);
    float2 el = sh + dThigh * s.l2;
    float2 wr = el + dArm * s.l3;
    float2 fl = wr + dTool * s.l4;

    c.shoulder = float3(sh.x, sh.y, 0.0);
    c.elbow    = float3(el.x, el.y, 0.0);
    c.wrist    = float3(wr.x, wr.y, 0.0);
    c.flange   = float3(fl.x, fl.y, 0.0);
    c.fwdThigh = float3(dThigh.x, dThigh.y, 0.0);
    c.fwdArm   = float3(dArm.x, dArm.y, 0.0);
    c.fwdTool  = float3(dTool.x, dTool.y, 0.0);

    // a1 swings the whole plane about the column.
    c.shoulder = ka_yaw(c.shoulder, a1);
    c.elbow    = ka_yaw(c.elbow, a1);
    c.wrist    = ka_yaw(c.wrist, a1);
    c.flange   = ka_yaw(c.flange, a1);
    c.fwdThigh = ka_yaw(c.fwdThigh, a1);
    c.fwdArm   = ka_yaw(c.fwdArm, a1);
    c.fwdTool  = ka_yaw(c.fwdTool, a1);
    return c;
}

// Local -> world for one arm record.
float3 ka_toWorld(KaRec r, float3 local_)
{
    float3 v = ka_yaw(local_, r.yaw);
    return float3(v.x + r.pos.x, v.y, v.z + r.pos.y);
}

// ===========================================================================
// THE RALLY
// ===========================================================================
// A beach ball kept in the air by a crowd of machines. This is not a pattern: a pattern is a
// per-arm function of phase, while a ball is ONE SHARED OBJECT with its own state, and "who
// hits it next" is a global decision. So it gets its own authority, KA_Rally, and the pose node
// executes whatever assignment it is handed.
//
// THE WHOLE SHOT IS DECIDED AT CONTACT. When an arm strikes, KA_Rally picks the receiver,
// computes the launch velocity, and then forward-simulates to find when and where the ball will
// descend through strike height near that receiver. That becomes the next contact. The receiver
// therefore knows its cue the instant the ball leaves the previous arm, which is the whole
// reason it has time to wind up — a reactive "hit it when it gets close" scheme gives an arm no
// warning and reads as twitching.
//
// It also means the ball's future is never in doubt, so the court diagram can draw the real
// trajectory rather than a guess.

#define KA_ROLE_NONE     0.0   // not on the court
#define KA_ROLE_WATCH    1.0   // playing, tracking the ball, not its turn
#define KA_ROLE_RECEIVE  2.0   // elected, contact is far enough away to be ready
#define KA_ROLE_STRIKE   3.0   // elected, inside the approach window
#define KA_ROLE_RECOVER  4.0   // just hit it, following through

#define KA_PLAY_IDLE     0.0   // no ball in play
#define KA_PLAY_LIVE     1.0   // in flight with a striker elected
#define KA_PLAY_DROP     2.0   // in flight and nobody can reach it

// The rally buffer: header, per-arm assignments, then the predicted trajectory as records.
// The trajectory is stored rather than recomputed by the canvas because a per-pixel forward
// integration is not a thing you can do, and because the diagram MUST draw the same simulation
// the election used — a court that draws a different arc from the one the arms are playing is
// worse than one that draws no arc.
#define KA_TRAJ_0        (KA_ARM_0 + KA_MAX_ARMS)
#define KA_TRAJ_N        40u

// ONE RECORD OF INSTRUMENTATION, past the end of the drawn data.
//
// Added after a long tuning session went wrong for want of it. The header's `shots` counter was
// read as "strokes attempted" and used to compute a whiff rate, but it only ever increments on a
// SERVE and inside the struck branch — it is serves plus contacts, so the "43% of strokes miss"
// that drove three rounds of election work was an artefact of the metric, not a property of the
// simulation. The honest lesson is that a derived statistic nobody wrote down deliberately will
// be read as whatever the reader is looking for. These are written down deliberately:
//
//   a1  plane crossings   ball fell past the strike height, descending
//   a2  whiffs            ...and no tool touched it on that crossing
//   a3  end: out          rallies that ended by leaving the floor bounds
//   a4  end: grounded     rallies that ended by dying on the deck
//   a5  sum of miss       tool-to-ball distance at each whiffed crossing
//   a6  worst miss        the single worst of those
//
// Whiffs over crossings is the real miss rate. Sum over whiffs is the average miss distance,
// which is the number that says whether the arms are missing by centimetres or by metres — and
// those two want completely different fixes.
#define KA_STATS         (KA_TRAJ_0 + KA_TRAJ_N)
#define KA_BALL_RECORDS  (KA_STATS + 1u)

// 24 floats / 96 bytes. Every float3 sits on a 16-byte offset and the float4 on 48.
// Index 0 is the header (the ball). Indices 1..48 are the per-arm assignments, and the field
// names carry a second meaning there — spelled out per field below.
//
// The arm records now carry the RATE-LIMITED JOINT ANGLES, and that is the point of the widening.
// KA_Rally integrates them, so there is exactly one integrator for a player's body: it limits,
// stores, and derives the tool position from the limited angles, and KA_Pose reads those angles
// straight out rather than recomputing anything. Two nodes each running their own limiter from
// their own history would agree only until one of their buffers was reset by a recompile or a
// preset recall, and would then disagree silently forever — colliding the ball against an arm
// that is not where it is drawn.
struct KaBall
{
    float3 pos;        // header: ball centre, world   | arm: TOOL contact point
    float  radius;     // header: ball radius          | arm: seconds to contact (<0 = since)
    float3 vel;        // header: ball velocity        | arm: swing direction, unit
    float  role;       // header: KA_PLAY_*            | arm: KA_ROLE_*
    float3 spin;       // header: spin axis * angle    | arm: tool world position, PREVIOUS cook
    float  power;      // header: completed strikes    | arm: swing speed at contact, m/s
    float  a1, a2, a3, a4;  // header: unused          | arm: joints, RATE LIMITED
    float  a5;         // header: unused               | arm: joint a5, rate limited
    float  a6;         // header: unused               | arm: joint a6, rate limited
    float  strikerIdx; // header: elected arm slot, -1 for none
    float  lastIdx;    // header: previous striker
    float  rallyCount; // header: consecutive hits     | arm: this arm's hit tally
    float  serveTimer; // header: seconds to next serve | arm: follow-through timer
    float  aimIdx;     // header: predicted striker    | arm: chosen receiver
    float  dropFlag;   // header: nobody can reach it  | arm: stroke committed
};

// ---------------------------------------------------------------------------
// REAL CONTACT
// ---------------------------------------------------------------------------
// The ball is not told where to go. It is hit.
//
// The loop is circular — joint angles decide the tool position, the tool hits the ball, the ball
// decides the next intent — and the graph refuses a feedback link, so it is closed INSIDE this
// header instead: KA_Rally evaluates the players' poses with the SAME functions KA_Pose will,
// from the same records in the same cook, and therefore knows exactly where every tool is. No
// link, no frame of lag, and no second implementation to drift.
//
// The consequence that matters: the IK below clamps to the joint limits, so an arm asked for a
// point outside its envelope genuinely does not get there, the spheres genuinely do not overlap,
// and the ball genuinely is not hit. Misses are real because nothing anywhere is pretending.

// Two-link aim. Wrist and tool fold into one rigid extension, exact while a5 holds at zero.
void ka_aimAt(KaRec rec, KaSpec sp, float3 tgt, out float a1, out float a2, out float a3)
{
    float3 loc = ka_yaw(tgt - float3(rec.pos.x, 0.0, rec.pos.y), -rec.yaw);
    a1 = atan2(-loc.z, loc.x);
    float dh = length(float2(loc.x, loc.z)) - sp.off1;
    float hy = loc.y - (rec.size.y + sp.turret);
    float L1 = max(sp.l2, 0.01), L2 = max(sp.l3 + sp.l4, 0.01);
    float r = clamp(length(float2(dh, hy)), abs(L1 - L2) + 0.02, L1 + L2 - 0.02);
    float phi = atan2(dh, hy);
    float beta = acos(clamp((L1 * L1 + r * r - L2 * L2) / (2.0 * L1 * r), -1.0, 1.0));
    a2 = phi - beta;
    a3 = KA_PI - acos(clamp((L1 * L1 + L2 * L2 - r * r) / (2.0 * L1 * L2), -1.0, 1.0));
}

// How long the swing takes. Derived from the commanded speed so the stroke is always about the
// same LENGTH — a fast swing is short and sharp, a slow one is long and lazy, and neither ever
// asks the arm to travel further than it can.
float ka_swingWindow(float speed) { return clamp(0.85 / max(speed, 0.5), 0.10, 0.42); }

// The player's pose. Called by KA_Rally to find out where its tool actually is, and by KA_Pose
// to drive the arm. Identical inputs must give identical output, so this takes no time-varying
// state beyond what the record carries.
//
// Record fields, for a playing arm:
//   pos    the TOOL's target at contact (already backed off the ball by ballR + toolR)
//   radius seconds to contact (negative = seconds since)
//   vel    swing direction, unit
//   power  swing speed at contact, m/s
//
// This is the TARGET pose. What the arm actually reaches is this run through the rate limiter,
// which is a different thing and the reason the motion reads as movement rather than as cuts.
void ka_rallyPose(KaBall rb, float3 ball, KaRec rec, KaSpec sp, float lead, float follow, float t,
                  out float a1, out float a2, out float a3,
                  out float a4, out float a5, out float a6)
{
    float3 base = float3(rec.pos.x, 0.0, rec.pos.y);
    float3 locB = ka_yaw(ball - base, -rec.yaw);
    float watchYaw = atan2(-locB.z, locB.x);
    float bob = sin(t * 1.7 + rec.seed) * 0.035;

    // the ready stance every player holds while the ball is somebody else's problem
    a1 = watchYaw;
    a2 = 12.0 * KA_D2R + bob;
    a3 = 92.0 * KA_D2R - bob * 0.6;
    a4 = 0.0; a5 = 28.0 * KA_D2R; a6 = 0.0;
    if (rb.role == KA_ROLE_WATCH || rb.role == KA_ROLE_NONE) return;

    float3 n = rb.vel;
    float s = max(rb.power, 0.0);
    float3 C = rb.pos;                       // where the TOOL must be at contact
    float w = ka_swingWindow(s);
    float3 start = C - n * (s * w);          // where the stroke begins
    float3 aimPt = start;

    if (rb.role == KA_ROLE_STRIKE)
    {
        float tc = rb.radius;
        if (tc <= w)
        {
            // Inside the window the tool travels along n at CONSTANT speed s, arriving at C
            // exactly at contact. Constant velocity is the point: an eased arrival would be
            // slowest precisely where the impulse is taken, and the ball would barely move.
            aimPt = C - n * (s * max(tc, 0.0));
        }
        else
        {
            // gather: ease from the ready crouch back to the start of the stroke
            float g = saturate(1.0 - (tc - w) / max(lead, 0.05));
            float3 ready = C - n * (s * w) - float3(0, 0.55, 0);
            aimPt = lerp(ready, start, smoothstep(0.0, 1.0, g));
        }
    }
    else if (rb.role == KA_ROLE_RECEIVE)
    {
        aimPt = C - n * (s * w) - float3(0, 0.55, 0);
    }
    else if (rb.role == KA_ROLE_RECOVER)
    {
        float fu = saturate(1.0 - (-rb.radius) / max(follow, 0.05));
        float3 thru = C + n * (s * w * 0.55);
        aimPt = lerp(thru, C - n * (s * w) - float3(0, 0.55, 0), smoothstep(0.0, 1.0, fu));
    }

    // Never aim the tool at or below the floor. Backing the stroke off the ball along the swing
    // line, and then dropping a further half metre to gather, puts the ready position under the
    // ground for a normal overhead contact — the IK then clamps, the arm sits in a strained
    // pose, and the stroke starts from somewhere it was never asked to be.
    aimPt.y = max(aimPt.y, rec.size.y + 0.45);

    float b1, b2, b3;
    ka_aimAt(rec, sp, aimPt, b1, b2, b3);
    a1 = b1; a2 = b2; a3 = b3;
    a5 = clamp(-(a2 + a3), KA_LIM[4].x, KA_LIM[4].y);
    a4 = 0.0; a6 = 0.0;
}

// THE TOOL SIZE IS PUBLISHED, NOT DUPLICATED.
//
// KA_Rally writes its Tool Radius — in metres, the exact sphere its sweep tests against — into
// the instrumentation record, and KA_Robot reads it from here to draw the striking head. One
// owner, one value.
//
// The renderer deliberately does NOT get its own head-size parameter. A second knob is a second
// place to be wrong: an earlier attempt gave each node its own multiplier, and they drifted by a
// factor of five within a single edit, so the arms swung a visible puck around a collider the
// size of a walnut. A shared sizing function over two independently-stored inputs does not
// prevent drift, it only makes the drift harder to see.
//
// Falls back to the manifest default when the buffer has not been written yet, so a fresh graph
// still draws real heads instead of none.
// Clamped, not merely defaulted. This is data published by another node, so it can be stale,
// zero, or left over from a build where the field meant something else — and an out-of-range
// radius does not draw a big tool, it poisons the distance field with NaN, at which point every
// arm silently stops rendering while the analytic floor carries on as if nothing were wrong.
float ka_toolDrawR(KaBall stats)
{
    float r = stats.vel.x;
    if (!(r > 0.001 && r < 2.0)) return 0.22;   // NaN-safe: the negated test catches NaN too
    return r;
}

// The world tool position this pose actually produces, AFTER the joint limits have had their
// say. This is the number the collision uses, which is why a limited arm really does miss.
float3 ka_toolOf(KaRec rec, KaSpec sp, float a1, float a2, float a3, float a5)
{
    float c1 = clamp(a1, KA_LIM[0].x, KA_LIM[0].y);
    float c2 = clamp(a2, KA_LIM[1].x, KA_LIM[1].y);
    float c3 = clamp(a3, KA_LIM[2].x, KA_LIM[2].y);
    float c5 = clamp(a5, KA_LIM[4].x, KA_LIM[4].y);
    KaChain ch = ka_chain(sp, rec.size.y, c1, c2, c3, c5);
    return ka_toWorld(rec, ch.flange);
}

// The three world points a ball can realistically come off: the flange, the wrist and the elbow.
// A machine is not a floating tool — most of what is standing in the ball's way is the arm — and
// a ball that visibly passes THROUGH a forearm is the single most obviously wrong thing the
// simulation can do. Angles are clamped here so the points match the drawn pose exactly.
void ka_armPoints(KaRec rec, KaSpec sp, float a1, float a2, float a3, float a5,
                  out float3 elbowW, out float3 wristW, out float3 flangeW)
{
    float c1 = clamp(a1, KA_LIM[0].x, KA_LIM[0].y);
    float c2 = clamp(a2, KA_LIM[1].x, KA_LIM[1].y);
    float c3 = clamp(a3, KA_LIM[2].x, KA_LIM[2].y);
    float c5 = clamp(a5, KA_LIM[4].x, KA_LIM[4].y);
    KaChain ch = ka_chain(sp, rec.size.y, c1, c2, c3, c5);
    elbowW  = ka_toWorld(rec, ch.elbow);
    wristW  = ka_toWorld(rec, ch.wrist);
    flangeW = ka_toWorld(rec, ch.flange);
}

// Earliest time in [0, dt] at which two moving spheres touch, or -1. Solving the quadratic
// rather than testing the endpoints is not optional: a tool swinging at 6 m/s crosses a 0.55 m
// ball in under a frame, and endpoint tests tunnel straight through it.
float ka_sweepHit(float3 pa, float3 va, float ra, float3 pb, float3 vb, float rb_, float dt)
{
    float3 dp = pa - pb, dv = va - vb;
    float R = ra + rb_;
    float a = dot(dv, dv);
    float b = 2.0 * dot(dp, dv);
    float c = dot(dp, dp) - R * R;
    if (c <= 0.0) return 0.0;                       // already overlapping
    if (a < 1e-8) return -1.0;
    float disc = b * b - 4.0 * a * c;
    if (disc < 0.0) return -1.0;
    float tHit = (-b - sqrt(disc)) / (2.0 * a);
    return (tHit >= 0.0 && tHit <= dt) ? tHit : -1.0;
}

// Impulse off a moving surface. `e` is how bouncy the flange is, `fric` how much of the tool's
// sideways motion it drags the ball along with.
float3 ka_bounce(float3 bv, float3 toolVel, float3 n, float e, float fric)
{
    float3 vRel = bv - toolVel;
    float vn = dot(vRel, n);
    if (vn >= 0.0) return bv;                       // separating already
    float3 vt = vRel - n * vn;
    return bv - n * ((1.0 + e) * vn) - vt * saturate(fric);
}

// The swing that WOULD produce a wanted outcome, solved rather than guessed.
//
// For an impulse off a surface moving at u = s*n:
//     v_out = v_in - (1+e)((v_in - u).n) n
// so (v_out - v_in) must be parallel to n, which fixes the direction outright, and the speed
// falls straight out of the magnitude. This is what lets an arm aim: it presents its tool along
// the line it wants the ball to leave on, and swings hard enough to send it that far.
void ka_solveSwing(float3 vIn, float3 vOut, float e, out float3 n, out float s)
{
    float3 d = vOut - vIn;
    float dl = length(d);
    n = (dl > 1e-4) ? (d / dl) : float3(0, 1, 0);
    s = dl / (1.0 + max(e, 0.0)) + dot(vIn, n);
}

// One physics substep. Quadratic drag, because that is what makes a beach ball a beach ball:
// linear drag gives a heavy ball that falls, quadratic drag gives one that accelerates to a
// low terminal speed and then FLOATS, which is the entire character of the object.
void ka_ballStep(inout float3 p, inout float3 v, float dt, float g, float drag)
{
    float s = length(v);
    v -= v * min(drag * s * dt, 0.9);
    v.y -= g * dt;
    p += v * dt;
}

// Floor bounce. Beach balls keep most of their energy vertically and shed it horizontally.
void ka_ballFloor(inout float3 p, inout float3 v, float r, float restitution)
{
    if (p.y < r)
    {
        p.y = r;
        if (v.y < 0.0) v.y = -v.y * restitution;
        v.xz *= 0.82;
    }
}

// ---------------------------------------------------------------------------
// Deterministic hash. Shared so the canvas can rebuild exactly what the layout drew.
// ---------------------------------------------------------------------------
float ka_rnd(float s, float k)
{
    return frac(sin(s * 12.9898 + k * 78.233) * 43758.5453);
}
float ka_rnd2(float2 s)
{
    return frac(sin(dot(s, float2(12.9898, 78.233))) * 43758.5453);
}
// Signed, mean-zero.
float ka_srnd(float s, float k) { return ka_rnd(s, k) * 2.0 - 1.0; }

// ---------------------------------------------------------------------------
// Arrangements. The layout is a LATTICE, so a re-roll perturbs the lattice, not the records.
// Kept here because the canvas draws the armature from exactly this function with no seed.
// ---------------------------------------------------------------------------
#define KA_ARR_LINE   0
#define KA_ARR_GRID   1
#define KA_ARR_RING   2
#define KA_ARR_ARC    3
#define KA_ARR_TWIN   4
#define KA_ARR_SPUR   5
#define KA_ARR_COUNT  6

// Lattice parameters, all of which the randomizer is allowed to move.
struct KaLattice
{
    float pitch;    // spacing along a run, metres
    float rows;     // how many runs
    float stagger;  // lateral offset applied to every other run, as a fraction of pitch
    float radius;   // ring / arc radius
    float span;     // arc angular span, radians
    float skew;     // run heading rotation, radians
    float conv;     // heading convergence: 0 = all parallel, 1 = all face the cell centre
};

// Where arm `i` of `n` sits, and which way it faces, for a given arrangement + lattice.
void ka_station(int arrangement, uint i, uint n, KaLattice L, out float2 p, out float heading)
{
    float fi = (float)i;
    float fn = max((float)n, 1.0);
    p = float2(0.0, 0.0);
    heading = 0.0;

    if (arrangement == KA_ARR_RING)
    {
        float a = (fi / fn) * KA_TAU;
        p = float2(cos(a), sin(a)) * L.radius;
        heading = a + KA_PI;                       // face inward
    }
    else if (arrangement == KA_ARR_ARC)
    {
        float t = (fn > 1.0) ? (fi / (fn - 1.0) - 0.5) : 0.0;
        float a = t * L.span;
        p = float2(sin(a), cos(a) * -1.0) * L.radius;
        heading = a + KA_PI * 0.5;
        heading = atan2(-p.y, -p.x);               // face the arc centre
    }
    else if (arrangement == KA_ARR_TWIN)
    {
        // two facing rows down a corridor — the assembly-line read
        float half_ = ceil(fn * 0.5);
        float side = (fi < half_) ? -1.0 : 1.0;
        float k = (fi < half_) ? fi : (fi - half_);
        float cnt = (fi < half_) ? half_ : (fn - half_);
        float t = k - (max(cnt, 1.0) - 1.0) * 0.5;
        p = float2(t * L.pitch + ((side > 0.0) ? L.stagger * L.pitch : 0.0), side * L.radius);
        heading = (side > 0.0) ? -KA_PI * 0.5 : KA_PI * 0.5;
    }
    else if (arrangement == KA_ARR_SPUR)
    {
        // a spine with alternating spurs — the one arrangement that is not a regular field
        float k = floor(fi * 0.5);
        float side = (fmod(fi, 2.0) < 0.5) ? -1.0 : 1.0;
        p = float2((k - (fn * 0.25 - 0.5)) * L.pitch, side * L.radius * 0.55);
        heading = (side > 0.0) ? -KA_PI * 0.5 : KA_PI * 0.5;
    }
    else if (arrangement == KA_ARR_GRID)
    {
        float cols = max(ceil(fn / max(L.rows, 1.0)), 1.0);
        float rr = floor(fi / cols);
        float cc = fi - rr * cols;
        float sgx = fmod(rr, 2.0) < 0.5 ? 0.0 : L.stagger * L.pitch;
        p = float2((cc - (cols - 1.0) * 0.5) * L.pitch + sgx,
                   (rr - (max(L.rows, 1.0) - 1.0) * 0.5) * L.pitch);
        heading = 0.0;
    }
    else // KA_ARR_LINE
    {
        p = float2((fi - (fn - 1.0) * 0.5) * L.pitch, 0.0);
        heading = 0.0;
    }

    // Run skew, then heading convergence. Both are lattice-level, which is why a re-roll of
    // them still reads as an arrangement.
    p = mul(ka_rot2(L.skew), p);
    heading += L.skew;
    if (L.conv > 0.0001)
    {
        float toCentre = atan2(-p.y, -p.x);
        // shortest-arc blend so convergence never spins an arm the long way round
        float d = toCentre - heading;
        d = atan2(sin(d), cos(d));
        heading += d * L.conv;
    }
}

#endif
