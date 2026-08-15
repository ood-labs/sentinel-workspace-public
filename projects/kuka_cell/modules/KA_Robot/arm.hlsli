// KA_Robot / arm.hlsli — the machine itself, as a signed distance field.
//
// A six-axis arm read at forty pixels is legible or not depending almost entirely on whether
// its members are FLAT-ENDED SEGMENTS BETWEEN DRAWN JOINTS. A chain of round-capped capsules is
// a caterpillar; the same chain with a hub cylinder at every axis and a plain cut at every link
// end is a robot. So every joint is a visible drawn cylinder on its own axis, and no link ends
// in a round cap.
//
// Each member also has to answer the three questions a form has to answer:
//   MEET   the thigh roots into a shoulder flange, the forearm into the elbow cover plate
//   CARRY  the thigh has a deep side flute with a raised spine between two flat values;
//          the forearm has a segmented roll collar
//   END    the flange is a flat cut face with a raised boss, not a point
//
// Costing: the whole arm is behind one cylinder bound, and then behind three group bounds
// (base / thigh / forearm). A ray far from a group pays one capsule evaluation for it, not the
// eight primitives inside. That is what makes forty-eight arms affordable.
#ifndef KA_ARM_HLSLI
#define KA_ARM_HLSLI

#include "../_shared/cell.hlsli"

// material ids
#define KM_BODY   0.0   // the painted casting
#define KM_CAST   1.0   // matte black pedestal iron
#define KM_MACH   2.0   // machined steel ring / flange face
#define KM_SEAL   3.0   // blue-black joint seal
#define KM_CABLE  4.0   // corrugated conduit
#define KM_MOTOR  5.0   // dark drive housing

// ---------------------------------------------------------------------------
// primitives — all ka_-prefixed so nothing can collide with an injected feature library
// ---------------------------------------------------------------------------
float ka_smin(float a, float b, float k)
{
    float h = saturate(0.5 + 0.5 * (b - a) / max(k, 1e-5));
    return lerp(b, a, h) - k * h * (1.0 - h);
}
float ka_box(float3 p, float3 b, float r)
{
    float3 q = abs(p) - b + r;
    return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0) - r;
}
float ka_cylY(float3 p, float h, float r)
{
    float2 d = float2(length(p.xz) - r, abs(p.y) - h);
    return min(max(d.x, d.y), 0.0) + length(max(d, 0.0));
}
float ka_cylZ(float3 p, float h, float r)
{
    float2 d = float2(length(p.xy) - r, abs(p.z) - h);
    return min(max(d.x, d.y), 0.0) + length(max(d, 0.0));
}
float ka_seg(float3 p, float3 a, float3 b, float ra, float rb)
{
    float3 pa = p - a, ba = b - a;
    float h = saturate(dot(pa, ba) / max(dot(ba, ba), 1e-6));
    return length(pa - ba * h) - lerp(ra, rb, h);
}
float ka_torusZ(float3 p, float R, float r)
{
    float2 q = float2(length(p.xy) - R, p.z);
    return length(q) - r;
}

// Distance to a vertical cylinder bound — exact, so it is safe to march on directly.
float ka_boundCyl(float3 p, float2 base, float radius, float rise)
{
    float dx = length(p.xz - base) - radius;
    float dy = max(-p.y, p.y - rise);
    float2 d = float2(dx, dy);
    return min(max(d.x, d.y), 0.0) + length(max(d, 0.0));
}

// ---------------------------------------------------------------------------
// One arm, evaluated in ITS OWN local frame (x forward along the heading, y up, z lateral),
// with a1 already removed so the arm plane is x-y.
// ---------------------------------------------------------------------------
float2 ka_armLocal(float3 pa, float3 pb, KaSpec sp, float ped,
                   float a2, float a3, float a4, float a5, float a6, float cable, float toolR)
{
    float g = sp.girth;
    float s = max(sp.l2, 0.2);            // a size unit that tracks the frame
    float2 best = float2(1e9, KM_BODY);

    // ---------------- group 1: pedestal, base casting, carousel ----------------
    // pb keeps the base yaw but NOT a1, so the plate and the manifolds stay put while the
    // carousel above them turns — which is the single most important read of a live machine.
    {
        float top = ped + sp.ped_h;
        float gb = ka_boundCyl(pb, float2(0, 0), sp.ped_r * 1.75, top + sp.turret * 0.75);
        if (gb > 0.10)
        {
            if (gb < best.x) best = float2(gb, KM_CAST);
        }
        else
        {
            // cast foot: a low chamfered plate with slotted lightening cutouts. Sized close to
            // the base casting it carries — a plate much wider than the machine reads as a
            // display stand rather than as part of the robot.
            float plate = ka_box(pb - float3(0, sp.ped_h * 0.13, 0),
                                 float3(sp.ped_r * 1.16, sp.ped_h * 0.13, sp.ped_r * 1.16),
                                 sp.ped_h * 0.09);
            float3 sl = pb; sl.xz = abs(sl.xz);
            float slot = ka_box(sl - float3(sp.ped_r * 0.80, sp.ped_h * 0.13, 0.0),
                                float3(sp.ped_r * 0.26, sp.ped_h * 0.55, sp.ped_r * 0.17),
                                sp.ped_r * 0.07);
            float slot2 = ka_box(sl - float3(0.0, sp.ped_h * 0.13, sp.ped_r * 0.80),
                                 float3(sp.ped_r * 0.17, sp.ped_h * 0.55, sp.ped_r * 0.26),
                                 sp.ped_r * 0.07);
            plate = max(plate, -min(slot, slot2));

            // riser (only when the machine is stood on a pedestal) + the base casting
            float riser = ka_box(pb - float3(0, ped * 0.5 + sp.ped_h * 0.16, 0),
                                 float3(sp.ped_r * 0.72, max(ped * 0.5, 1e-4), sp.ped_r * 0.72),
                                 sp.ped_r * 0.16);
            float cast_ = ka_cylY(pb - float3(0, ped + sp.ped_h * 0.55, 0),
                                  sp.ped_h * 0.45, sp.ped_r * 0.94);
            float d1 = min(plate, ka_smin(riser, cast_, sp.ped_r * 0.12));
            if (d1 < best.x) best = float2(d1, KM_CAST);

            // the machined split ring the carousel turns on
            float ring = ka_cylY(pb - float3(0, top - sp.ped_h * 0.055, 0),
                                 sp.ped_h * 0.075, sp.ped_r * 0.99);
            if (ring < best.x) best = float2(ring, KM_MACH);

            // base ancillaries: the black manifold bottles and their bracket, off one side.
            // They are why the base of the reference does not read as a plain cylinder.
            if (cable > 0.01)
            {
                float3 pm = pb - float3(-sp.ped_r * 1.02, ped + sp.ped_h * 0.72, sp.ped_r * 0.22);
                float bot = ka_cylZ(pm, sp.ped_r * 0.30, sp.ped_r * 0.155);
                float bot2 = ka_cylZ(pm - float3(0, sp.ped_r * 0.42, 0), sp.ped_r * 0.26, sp.ped_r * 0.125);
                float brk = ka_box(pm - float3(sp.ped_r * 0.22, sp.ped_r * 0.2, 0),
                                   float3(sp.ped_r * 0.06, sp.ped_r * 0.42, sp.ped_r * 0.30), sp.ped_r * 0.03);
                float anc = min(min(bot, bot2), brk);
                if (anc < best.x) best = float2(anc, KM_MOTOR);
            }

            // A1 carousel, in the a1-rotated frame: a swelling casting that carries the
            // shoulder over to one side rather than a plain drum
            // A1 carousel: ONE swelling casting that leans the shoulder out over the column.
            // The blend radius is large on purpose — a tight smin between the drum and the yoke
            // leaves a saddle that reads as a bite taken out of the machine.
            float3 pc = pa - float3(0, top, 0);
            float drum = ka_cylY(pc - float3(0, sp.turret * 0.26, 0), sp.turret * 0.26, sp.ped_r * 0.88);
            float yoke = ka_box(pc - float3(sp.off1 * 0.62, sp.turret * 0.70, 0),
                                float3(sp.off1 * 0.58 + sp.ped_r * 0.26, sp.turret * 0.32,
                                       sp.ped_r * 0.50 * g),
                                sp.ped_r * 0.30);
            float car = ka_smin(drum, yoke, sp.ped_r * 0.62);
            if (car < best.x) best = float2(car, KM_BODY);
        }
    }

    // Planar chain, a1 already removed.
    KaChain ch = ka_chain(sp, ped, 0.0, a2, a3, a5);
    float hubR = s * 0.175 * g;
    float hubH = s * 0.185 * g;

    // ---------------- group 2: shoulder hub + the A2 thigh ----------------
    {
        float gbW = max(s * 0.30 * g, hubR * 1.5);
        float gb = ka_seg(pa, ch.shoulder, ch.elbow, gbW, gbW * 0.85);
        if (gb > 0.10)
        {
            if (gb < best.x) best = float2(gb, KM_BODY);
        }
        else
        {
            float3 d = normalize(ch.elbow - ch.shoulder);
            float3 n = float3(-d.y, d.x, 0.0);
            float L = length(ch.elbow - ch.shoulder);
            float3 q = pa - ch.shoulder;
            float3 lc = float3(dot(q, d), dot(q, n), q.z);
            float t = saturate(lc.x / max(L, 1e-4));

            // TAPER. The thigh is deep at the shoulder and slim at the elbow; that taper is
            // most of the reference's silhouette.
            float w = lerp(s * 0.255, s * 0.150, t) * g;      // in-plane half depth
            float th = lerp(s * 0.150, s * 0.105, t) * g;     // lateral half thickness
            // Rounding kept low: the reference casting has broad FLAT side faces meeting at a
            // crisp ridge, and a heavily rounded section turns the whole limb back into a tube
            // no matter how deep the flute is cut into it.
            float body = ka_box(float3(lc.x - L * 0.5, lc.y, lc.z),
                                float3(L * 0.5, w, th), min(w, th) * 0.30);

            // THE FLUTE. A deep concave channel down each side face, faded in at both ends so
            // it does not cut the flange or the elbow root. Without it the thigh is a bar.
            float win = smoothstep(0.04, 0.20, t) * (1.0 - smoothstep(0.74, 0.97, t));
            float fr = s * 0.215 * g;                 // tighter cylinder = a channel, not a dish
            float depth = s * 0.105 * g * win;
            float fd = length(float2(lc.y * 0.78, abs(lc.z) - (th + fr - depth))) - fr;
            body = max(body, -fd);

            // THE SPINE. A raised rib along the outer face, which is the ridge that splits the
            // casting into two values and is why the reference reads as formed rather than
            // extruded. Proud enough to catch its own highlight — a rib flush with the surface
            // is a line in the normal map and nothing in the silhouette.
            float ridge = ka_box(float3(lc.x - L * 0.52, lc.y - w * 0.97, lc.z),
                                 float3(L * 0.40, w * 0.22, th * 0.30), th * 0.22);
            body = ka_smin(body, ridge, s * 0.014);

            // ROOT: the shoulder bearing HOUSING is part of the casting and therefore painted.
            // The first build made the whole hub dark and it read as a hole punched through the
            // machine; on the reference only the small cover plate is dark.
            float flange = ka_cylZ(pa - ch.shoulder, th * 1.30, s * 0.225 * g);
            float housing = ka_cylZ(pa - ch.shoulder, hubH * 1.16, hubR * 1.12);
            body = ka_smin(body, flange, s * 0.030);
            body = ka_smin(body, housing, s * 0.035);
            if (body < best.x) best = float2(body, KM_BODY);

            // the bearing cover, proud of the housing, and the seal in the split line
            float cover = ka_cylZ(pa - ch.shoulder, hubH * 1.28, hubR * 0.56);
            if (cover < best.x) best = float2(cover, KM_MACH);
            float seal = ka_torusZ(pa - ch.shoulder, hubR * 0.86, s * 0.014);
            if (seal < best.x) best = float2(seal, KM_SEAL);

            // the A2 drive can, coaxial with the joint and sitting BEHIND it — the counterweight
            // mass that makes a shoulder look driven rather than hinged
            float motor = ka_cylZ(pa - (ch.shoulder - d * s * 0.30), hubH * 1.34, hubR * 0.74);
            if (motor < best.x) best = float2(motor, KM_MOTOR);
        }
    }

    // ---------------- group 3: elbow, forearm, wrist, flange ----------------
    {
        float gbW = max(s * 0.26 * g, hubR * 1.4);
        float gb = ka_seg(pa, ch.elbow, ch.flange, gbW, gbW);
        if (gb > 0.10)
        {
            if (gb < best.x) best = float2(gb, KM_BODY);
        }
        else
        {
            // elbow hub + its bolted cover plate: this is the biggest single joint read
            float ehub = ka_cylZ(pa - ch.elbow, hubH * 1.02, hubR * 1.00);
            if (ehub < best.x) best = float2(ehub, KM_BODY);
            float cover = ka_cylZ(pa - ch.elbow, hubH * 1.16, hubR * 0.60);
            if (cover < best.x) best = float2(cover, KM_MACH);
            float eseal = ka_torusZ(pa - ch.elbow, hubR * 0.80, s * 0.012);
            if (eseal < best.x) best = float2(eseal, KM_SEAL);

            float3 d = normalize(ch.wrist - ch.elbow);
            float3 n = float3(-d.y, d.x, 0.0);
            float L = length(ch.wrist - ch.elbow);
            float3 q = pa - ch.elbow;
            float3 lc = float3(dot(q, d), dot(q, n), q.z);
            float t = saturate(lc.x / max(L, 1e-4));

            // forearm: a tapered tube, squarer near the elbow and rounder at the wrist
            float w = lerp(s * 0.180, s * 0.108, t) * g;
            float th = lerp(s * 0.150, s * 0.098, t) * g;
            float rr = lerp(0.42, 0.92, t);
            float body = ka_box(float3(lc.x - L * 0.5, lc.y, lc.z),
                                float3(L * 0.5, w, th), min(w, th) * rr);
            // a shallow relief down the top face, the forearm's answer to "how do I carry"
            float rel = length(float2(lc.y - (w + s * 0.12 * g), lc.z * 0.7)) - s * 0.135 * g;
            body = max(body, -rel * smoothstep(0.10, 0.35, t) * (1.0 - smoothstep(0.60, 0.80, t)));
            if (body < best.x) best = float2(body, KM_BODY);

            // A4 ROLL COLLAR: a proud segmented band. a4 rotates the segmentation about the
            // forearm axis, so the roll axis is visibly doing something.
            {
                float ct = 0.615;
                float3 cl = float3(lc.x - L * ct, lc.y, lc.z);
                float cw = lerp(s * 0.180, s * 0.108, ct) * g * 1.14;
                float ang = atan2(cl.z, cl.y) + a4;
                float seg = abs(frac(ang / KA_TAU * 8.0) - 0.5) * 2.0;
                float band = ka_box(cl, float3(s * 0.055 * g, cw, cw * 0.92), cw * 0.55)
                           - seg * s * 0.006 * g;
                if (band < best.x) best = float2(band, KM_SEAL);
            }

            // WRIST: a compact yoke on the A5 axis, then the tool axis out to the flange
            float wr = ka_cylZ(pa - ch.wrist, s * 0.098 * g, s * 0.108 * g);
            float wbox = ka_box(pa - ch.wrist, float3(s * 0.10 * g, s * 0.10 * g, s * 0.088 * g), s * 0.05 * g);
            float wrist = ka_smin(wr, wbox, s * 0.02);
            if (wrist < best.x) best = float2(wrist, KM_BODY);

            // A6 flange: a flat cut face with a raised boss and a dark bolt ring. An arm that
            // ends in a round cap has no tool mount and reads as a tentacle.
            float3 td = normalize(ch.flange - ch.wrist);
            float3 tn = float3(-td.y, td.x, 0.0);
            float3 tq = pa - ch.wrist;
            float3 tl = float3(dot(tq, td), dot(tq, tn), tq.z);
            float tL = max(length(ch.flange - ch.wrist), 1e-4);
            float neck = ka_box(float3(tl.x - tL * 0.45, tl.y, tl.z),
                                float3(tL * 0.45, s * 0.080 * g, s * 0.080 * g), s * 0.055 * g);
            if (neck < best.x) best = float2(neck, KM_BODY);
            float2 fd2 = float2(length(tl.yz) - s * 0.098 * g, abs(tl.x - tL) - s * 0.028 * g);
            float face = min(max(fd2.x, fd2.y), 0.0) + length(max(fd2, 0.0));
            if (face < best.x) best = float2(face, KM_MACH);
            float2 bd2 = float2(length(tl.yz) - s * 0.048 * g, abs(tl.x - tL - s * 0.030 * g) - s * 0.016 * g);
            float boss = min(max(bd2.x, bd2.y), 0.0) + length(max(bd2, 0.0));
            if (boss < best.x) best = float2(boss, KM_MACH);

            // THE STRIKING HEAD — the collider, drawn.
            //
            // The rally sweeps a sphere of exactly toolR centred on this flange point, and
            // nothing rendered it, so the ball bounced off empty air a hand's width off the
            // machine and contact never quite looked like contact. This is that sphere, at that
            // radius, in that place: not a decoration sized to look about right, but the actual
            // collision volume made visible. Change Tool Radius and this follows, because it is
            // the same number.
            // It has to answer the same three questions every other member here answers. The
            // first attempt was a sphere with a smaller sphere for a pad, and two overlapping
            // spheres read as an EYE rather than as tooling — and, centred on the flange, the big
            // one swallowed the wrist so the neck appeared to poke through it.
            //
            // So: it MEETS with a machined collar fitted over the flange neck, deliberately
            // fatter than the neck so the junction is a shoulder rather than a surface just
            // clipping through; it CARRIES with one shallow drum on the tool axis; and it ENDS in
            // a flat pad, proud of the drum face and inset from its rim, which is the part that
            // actually hits the ball. One silhouette, no coincident spheres.
            //
            // Every dimension is a fraction of toolR, so the drawn striker and the collision
            // sphere stay the same object: the rim sits at 0.97 of the collider radius and the
            // pad face at 0.72 of it along the axis — the direction a ball is actually met from.
            if (toolR > 0.001)
            {
                // tool-local: origin at the flange, x along the tool axis. The permutation turns
                // ka_cylZ into a cylinder about that axis rather than about world z.
                float3 lp = float3(tl.x - tL, tl.y, tl.z);
                float3 xp = float3(lp.y, lp.z, lp.x);

                float collar = ka_cylZ(xp - float3(0, 0, -toolR * 0.34), toolR * 0.30, toolR * 0.46)
                             - toolR * 0.06;
                float drum   = ka_cylZ(xp - float3(0, 0,  toolR * 0.30), toolR * 0.20, toolR * 0.74)
                             - toolR * 0.18;
                float tool   = ka_smin(collar, drum, toolR * 0.18);
                if (tool < best.x) best = float2(tool, KM_MACH);

                float pad = ka_cylZ(xp - float3(0, 0, toolR * 0.56), toolR * 0.06, toolR * 0.66)
                          - toolR * 0.10;
                if (pad < best.x) best = float2(pad, KM_SEAL);
            }
        }
    }

    // ---------------- cable dressing ----------------
    // Silhouette-critical: the loop off the back of the base and up behind the thigh is a
    // large part of what makes the reference read as a working machine rather than a model.
    if (cable > 0.01)
    {
        // Evaluated ENTIRELY in the carousel frame. Anchoring the first segment to the base
        // frame is more literally correct and visibly tears the conduit in half the moment A1
        // turns, because the two frames are only aligned at a1 = 0. A KUKA dress pack rides the
        // rotating column anyway.
        float3 c0 = float3(-sp.ped_r * 0.62, ped + sp.ped_h * 0.90, sp.ped_r * 0.52);
        float3 c1 = float3(-sp.ped_r * 0.95, ped + sp.turret * 0.92, sp.ped_r * 0.58);
        float3 dq = normalize(ch.elbow - ch.shoulder);
        float3 nq = float3(-dq.y, dq.x, 0.0);
        float3 c2 = ch.shoulder - nq * s * 0.31 * sp.girth + float3(0, 0, sp.ped_r * 0.50);
        float3 c3 = lerp(ch.shoulder, ch.elbow, 0.55) - nq * s * 0.24 * sp.girth
                  + float3(0, 0, s * 0.16 * sp.girth);
        float3 c4 = ch.elbow - nq * s * 0.10 * sp.girth + float3(0, 0, s * 0.13 * sp.girth);

        float cr = s * 0.032 * sp.girth;
        float bnd = min(min(ka_seg(pa, c1, c2, cr * 3.0, cr * 3.0),
                            ka_seg(pa, c2, c3, cr * 3.0, cr * 3.0)),
                        min(ka_seg(pa, c0, c1, cr * 3.0, cr * 3.0),
                            ka_seg(pa, c3, c4, cr * 3.0, cr * 3.0)));
        if (bnd > 0.06)
        {
            if (bnd < best.x) best = float2(bnd, KM_CABLE);
        }
        else
        {
            float cd = min(min(ka_seg(pa, c0, c1, cr, cr), ka_seg(pa, c1, c2, cr, cr)),
                           min(ka_seg(pa, c2, c3, cr, cr), ka_seg(pa, c3, c4, cr, cr)));
            // corrugation, which is the whole reason a conduit reads as a conduit
            cd -= sin(length(pa - c2) / max(cr, 1e-4) * 1.9) * cr * 0.16;
            if (cd < best.x) best = float2(cd, KM_CABLE);
        }
    }

    return best;
}

// World-space entry point for one arm. Returns (distance, material).
float2 ka_arm(float3 p, KaRec r, KaPose q, float cable, float toolR)
{
    KaSpec sp = ka_spec(r.kind, r.size.x);
    float rise = ka_rise(sp, r.size.y);
    float reach = ka_reach(sp);

    // One exact bound for the whole machine — the cheap test forty-eight arms need.
    //
    // The threshold is 2.0 m, not a few centimetres, and that is a shading correctness matter
    // rather than a performance one. This cylinder has the arm's full REACH as its radius, so
    // returning its distance hands every shadow and AO ray a phantom drum three metres wide
    // around each machine; the first build did exactly that and drew concentric ripples across
    // the whole floor. Past two metres nothing can shade — soft shadow k*h/t and an AO radius of
    // 0.12 both saturate — so the loose value is safe there and only used to skip empty space.
    // Inside two metres the tight per-group capsule bounds below do the work.
    float bd = ka_boundCyl(p, r.pos, reach * 1.02, rise * 1.05);
    if (bd > 2.0) return float2(bd, KM_BODY);

    float3 rel = float3(p.x - r.pos.x, p.y, p.z - r.pos.y);
    float3 pb = ka_yaw(rel, -r.yaw);         // base frame: plate, ancillaries, cast
    float3 pa = ka_yaw(pb, -q.a1);           // carousel frame: everything that turns with A1
    return ka_armLocal(pa, pb, sp, r.size.y, q.a2, q.a3, q.a4, q.a5, q.a6, cable, toolR);
}

#endif
