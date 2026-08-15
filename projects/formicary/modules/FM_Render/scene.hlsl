// FM_Render / scene.hlsl — the studio sweep and the ants, in ONE draw pass.
//
// One pass, not two, and the reason is worth recording. Sentinel gives every pass its own
// colour target and shares ONE depth buffer across draw passes. Two draw passes therefore
// depth-test against each other correctly and composite not at all: the ants' target would
// carry the ground's occlusion but none of its pixels. Putting the sweep's six vertices at the
// head of the same vertex range costs one branch in the vertex shader and removes the question.
//
// Vertex pulling: there is no vertex buffer. SV_VertexID decodes to "ground, or which ant,
// which body part, which quad", and the position is built on the spot.
#include "../_shared/formic.hlsli"
#include "antgeo.hlsli"

StructuredBuffer<FmRec>  PlanB : register(t0);
StructuredBuffer<FmAnt>  Ants  : register(t1);
StructuredBuffer<FmFoot> Feet  : register(t2);
// _Tex3 — the pheromone field from FM_Colony.

#define GROUND_V 6u

// ---------------------------------------------------------------------------
// THE DETAIL LADDER. Each rung re-parameterises every body of revolution with fewer slices and
// stacks, so the surface still CLOSES and the surplus vertices degenerate. Degenerating
// alternate quads of the full parameterisation instead would not make a coarser ant — it would
// make an ant with holes in it.
//
// The counts are now an explicit table rather than a halving of the declared capacity, and that
// is the point: rung 1 reproduces the ORIGINAL mesh exactly — 16x10 gaster, 12x8 body, 12x4
// nodes, 6-sided tubes — so raising the ceiling for a Hero tier did not silently move every
// other rung underneath it.
//
//   0 Hero     the new ceiling. Twelve-sided limbs; the six-sided ones read as hexagonal
//              prisms in any close shot and that is the thing that looked cheap.
//   1 Full     the original mesh, unchanged.
//   2 Reduced  indistinguishable below about 40 px an ant. The working default.
//   3 Distant  legs to three sides, mandibles gone. For a full plate.
// ---------------------------------------------------------------------------
uint2 agGasterRings(int lod)
{
    if (lod <= 0) return uint2(GAS_SL, GAS_ST);          // 24 x 14
    if (lod == 1) return uint2(16u, 10u);                // the original
    if (lod == 2) return uint2(8u, 5u);
    return uint2(6u, 4u);
}
uint2 agBodyRings(int lod)
{
    if (lod <= 0) return uint2(BOD_SL, BOD_ST);          // 16 x 10
    if (lod == 1) return uint2(12u, 8u);                 // the original
    if (lod == 2) return uint2(6u, 4u);
    return uint2(5u, 4u);
}
uint2 agNodeRings(int lod)
{
    if (lod <= 0) return uint2(NOD_SL, NOD_ST);          // 14 x 6
    if (lod == 1) return uint2(12u, 4u);                 // the original
    return uint2(6u, 3u);                                // already tiny; one step only
}
uint agTubeSides(int lod)
{
    if (lod <= 0) return TUB_S;                          // 12
    if (lod == 1) return 6u;                             // the original
    if (lod == 2) return 4u;
    return 3u;
}

struct VS_OUTPUT
{
    float4 Position : SV_POSITION;
    float3 WorldPos : TEXCOORD0;
    float3 Normal   : NORMAL;
    float3 Tint     : COLOR0;
    // x = material id (-1 = ground), y = gloss scale, z = spare
    float3 Mat      : TEXCOORD1;
};

VS_OUTPUT degenerate()
{
    VS_OUTPUT o;
    o.Position = float4(0, 0, -999, 1);
    o.WorldPos = 0; o.Normal = float3(0, 1, 0); o.Tint = 0; o.Mat = 0;
    return o;
}

VS_OUTPUT VSMain(uint vid : SV_VertexID)
{
    VS_OUTPUT o;

    // ---- THE SWEEP
    if (vid < GROUND_V)
    {
        FmRec arena = PlanB[FM_ARENA];
        // Well past the arena, so the frame is filled at any camera angle. The arena is where
        // the ants are, not where the paper ends.
        float2 e = fmArenaHalf(arena) * 4.5;

        float2 c;
        if (vid == 0u) c = float2(-1, -1);
        else if (vid == 1u) c = float2(1, -1);
        else if (vid == 2u) c = float2(1, 1);
        else if (vid == 3u) c = float2(-1, -1);
        else if (vid == 4u) c = float2(1, 1);
        else c = float2(-1, 1);

        float3 wp = float3(c.x * e.x, 0.0, c.y * e.y);
        o.Position = mul(_ViewProjMatrix, float4(wp, 1.0));
        o.WorldPos = wp;
        o.Normal = float3(0, 1, 0);
        o.Tint = arena.tint;
        o.Mat = float3(-1.0, 0.0, 0.0);
        return o;
    }

    uint v = vid - GROUND_V;
    uint ai = v / VERTS_PER_ANT;
    uint local = v - ai * VERTS_PER_ANT;

    if (ai >= FM_MAX_ANTS) return degenerate();
    FmAnt a = Ants[ai];
    if (a.active < 0.5) return degenerate();

    // ---- EMERGENCE. An ant released by an emitter comes UP OUT OF THE GROUND and one taken by
    // a sink goes back down into it. Presence is the colony's measurement; the renderer only
    // obeys it. The body sinks below y = 0 and the opaque sweep hides the buried part, so the
    // effect costs one offset and no alpha blending, no sorting and no second pass.
    float pres = saturate(a.fade);
    if (pres <= 0.012) return degenerate();

    float grow = lerp(0.42, 1.0, pres * pres * (3.0 - 2.0 * pres));
    float L = max(a.size, 0.1) * grow;
    float sinkY = -(1.0 - pres) * max(a.size, 0.1) * 1.7;

    // ---- THE DETAIL LADDER, per ant.
    //
    // Projected size is measured by PROJECTING, not by dividing by distance and a field of
    // view: the fov is not a shader constant here, and deriving it from the combined
    // view-projection is exactly the kind of thing that silently stops being true the day
    // somebody switches to an external camera. Two extra transforms per vertex is nothing
    // against what the branch below saves.
    // 4 rungs now. The auto-drop below still applies on top of whichever the user picked.
    int lod = (int)ant_detail;
    {
        float4 q0 = mul(_ViewProjMatrix, float4(a.pos, 1.0));
        float4 q1 = mul(_ViewProjMatrix, float4(a.pos + float3(0.0, max(a.size, 0.1), 0.0), 1.0));
        float px = abs(q1.y / max(abs(q1.w), 1e-4) - q0.y / max(abs(q0.w), 1e-4)) * 0.5 * _Resolution.y;
        // A colony spread in depth is mostly far away. An ant behind the camera reports
        // nonsense here, which the clip stage throws away anyway.
        if (px < detail_px)        lod = min(lod + 1, 3);
        if (px < detail_px * 0.45) lod = 3;
    }
    uint tubeSides = agTubeSides(lod);

    // The body frame. One heading is enough: an ant walks on a plane and has no roll to carry.
    float3 F = normalize(float3(a.dir.x, 0.0, a.dir.z) + float3(1e-5, 0, 0));
    float3 U = float3(0, 1, 0);
    float3 R = normalize(cross(U, F));

    // A gait-synced heave and roll. Real insects pitch and heave a little on each tripod;
    // without it the body glides above the legs like a puck, and the legs then read as
    // decoration attached to something that is not actually walking.
    float bobPh = a.gait * 6.2831853;
    float bob = sin(bobPh * 2.0) * L * 0.018 * body_bob;
    float roll = sin(bobPh) * 0.055 * body_bob;
    float3 origin = a.pos + U * (bob + sinkY);
    float3 Rr = normalize(R * cos(roll) + U * sin(roll));
    float3 Ur = normalize(cross(F, Rr));

    float3 tintGaster = PlanB[FM_PAL_0 + FM_PAL_GASTER].tint;
    float3 tintThorax = a.tint;
    float3 tintLimb = PlanB[FM_PAL_0 + FM_PAL_LIMB].tint;

    float3 lp, ln;
    float2 uvq;
    float3 tint = tintThorax;
    float mat = MAT_THORAX;
    float gloss = 1.0;

    if (local < OFF_MESO)
    {
        // The gaster: the biggest mass and by far the glossiest thing on the animal, and
        // therefore the part that keeps the most rings when the ladder drops.
        uint2 r = agGasterRings(lod); uint sl = r.x, st = r.y;
        uint idx = local - OFF_GASTER;
        if (idx >= sl * st * 6u) return degenerate();
        agEllipsoid(idx, sl, st, P_GAS_C * L, P_GAS_R * L, 0.38, lp, ln, uvq);
        tint = tintGaster; gloss = 1.55;
    }
    else if (local < OFF_HEAD)
    {
        uint2 r = agBodyRings(lod); uint sl = r.x, st = r.y;
        uint idx = local - OFF_MESO;
        if (idx >= sl * st * 6u) return degenerate();
        agEllipsoid(idx, sl, st, P_MESO_C * L, P_MESO_R * L, -0.22, lp, ln, uvq);
        tint = tintThorax; gloss = 0.85;
    }
    else if (local < OFF_PET)
    {
        uint2 r = agBodyRings(lod); uint sl = r.x, st = r.y;
        uint idx = local - OFF_HEAD;
        if (idx >= sl * st * 6u) return degenerate();
        agEllipsoid(idx, sl, st, P_HEAD_C * L, P_HEAD_R * L, 0.30, lp, ln, uvq);
        tint = tintThorax * 0.92; gloss = 1.15;
    }
    else if (local < OFF_POST)
    {
        // The two waist nodes are the silhouette signature and they are already tiny. They drop
        // one rung at most, or an ant stops being an ant and becomes a beetle.
        uint2 r = agNodeRings(lod); uint sl = r.x, st = r.y;
        uint idx = local - OFF_PET;
        if (idx >= sl * st * 6u) return degenerate();
        agEllipsoid(idx, sl, st, P_PET_C * L, P_PET_R * L, 0.0, lp, ln, uvq);
        tint = tintThorax * 0.88; gloss = 0.9;
    }
    else if (local < OFF_LEGS)
    {
        uint2 r = agNodeRings(lod); uint sl = r.x, st = r.y;
        uint idx = local - OFF_POST;
        if (idx >= sl * st * 6u) return degenerate();
        agEllipsoid(idx, sl, st, P_POST_C * L, P_POST_R * L, 0.0, lp, ln, uvq);
        tint = tintThorax * 0.86; gloss = 0.9;
    }
    else if (local < OFF_ANTN)
    {
        // ---- LEGS, SOLVED TO THE PUBLISHED FOOT POSITIONS.
        //
        // Not procedural decoration driven off a clock: a two-bone IK solve from the hip to the
        // exact world point FM_Colony has that tarsus planted at. This is the entire reason the
        // feet were published as a buffer.
        uint li = local - OFF_LEGS;
        uint leg = li / (LEG_SEG * TUB_V);
        uint rest = li - leg * (LEG_SEG * TUB_V);
        uint seg = rest / TUB_V;
        uint sv = rest - seg * TUB_V;

        if (sv >= tubeSides * 6u) return degenerate();

        float3 hipL = agLegHip(leg, L);
        float3 hipW = origin + Rr * hipL.x + Ur * hipL.y + F * hipL.z;
        // The foot descends WITH the body. The gait pass plants tarsi on the ground plane and
        // knows nothing about emergence, so a body sinking on its own would stretch six legs
        // up to feet still standing on the surface above it.
        float3 footW = Feet[ai * FM_LEGS + leg].pos + float3(0.0, sinkY, 0.0);

        float tarsus = 0.22 * L;

        // The tarsus lies DOWN toward the ground, so the ankle sits above and behind the tip.
        // That is what produces the splayed, flat-footed contact in the photograph instead of a
        // leg that spears the ground at a single point.
        float3 outDir = normalize(float3(footW.x - origin.x, 0.0, footW.z - origin.z) + float3(1e-5, 0, 0));
        float3 ankle = footW + float3(0, 1, 0) * tarsus * 0.72 - outDir * tarsus * 0.52;

        // Bones AFTER the ankle, because they are now derived from the distance they have to
        // cover rather than authored as a fraction of the body. Surplus bone length has to go
        // somewhere and it goes into the knee — up and out, over the back, which is the single
        // strongest spider cue there is.
        float2 bones = agLegBones(length(ankle - hipW));
        float3 knee = agSolveKnee(hipW, ankle, bones.x, bones.y, 0.28);

        // Thicker than the first pass. At 0.030 L a femur is 0.13 mm on a 4.2 mm worker, which
        // renders as wire and reads as a spider; the photograph's legs are visibly substantial
        // where they leave the body and taper hard only through the tarsus.
        //
        // A FRACTION OF BODY LENGTH, NOT OF LEG LENGTH, and that is deliberate. It means
        // shortening the stance leaves the tubes as thick as they were and the legs get
        // relatively STUBBIER on their own, which is the direction an ant wants — a spider's
        // legs are long AND thin, and the two cues reinforce each other. Scaling thickness with
        // leg length instead would have preserved the spidery proportion exactly while making
        // the whole animal smaller.
        // The JUDGED radii, baked in from a side-by-side at a fixed macro camera, so Leg
        // Thickness = 1.0 is the shipped animal.
        float tk = max(leg_thick, 0.05);
        float3 A, B; float ra, rb;
        if (seg == 0u)      { A = hipW;  B = knee;  ra = 0.0540 * L * tk; rb = 0.0365 * L * tk; }
        else if (seg == 1u) { A = knee;  B = ankle; ra = 0.0365 * L * tk; rb = 0.0230 * L * tk; }
        else                { A = ankle; B = footW; ra = 0.0230 * L * tk; rb = 0.0108 * L * tk; }

        agTubeN(sv, A, B, ra, rb, tubeSides, lp, ln);
        o.Position = mul(_ViewProjMatrix, float4(lp, 1.0));
        o.WorldPos = lp;
        o.Normal = normalize(ln);
        o.Tint = tintLimb;
        o.Mat = float3(MAT_LIMB, 0.65, 0.0);
        return o;
    }
    else if (local < OFF_MAND)
    {
        // ---- ANTENNAE, geniculate: a long scape out of the head, an elbow, then the funiculus
        // with its club. With the two-node waist, this is the silhouette signature — which is
        // why they are two segments and not one curved whip.
        uint ii = local - OFF_ANTN;
        uint anten = ii / (ANT_SEG * TUB_V);
        uint rest = ii - anten * (ANT_SEG * TUB_V);
        uint seg = rest / TUB_V;
        uint sv = rest - seg * TUB_V;
        float sgn = (anten == 0u) ? -1.0 : 1.0;

        // Swept on the SAME phase the colony steers on, so the antennae are visibly sampling
        // the ground the ant is actually following rather than waving on their own clock.
        // Contact with a neighbour lifts and spreads them — antennation.
        float ph = a.antenna * 6.2831853 + (anten == 0u ? 0.0 : 2.1);
        float sweep = sin(ph) * antenna_swing;
        float lift = 0.32 + 0.30 * a.contact + 0.14 * cos(ph * 1.3);

        // Length and thickness are separate controls for the same reason the legs' are: with
        // the legs pulled in, the antennae became the longest appendages on the animal by a
        // clear margin, and a long thin whip is the cue that was left over from the spider.
        // Scaling BOTH segments keeps the elbow at the same fraction along, so the geniculate
        // silhouette — the thing that says antenna rather than leg — survives any length.
        float alen = max(antenna_len, 0.05);
        float atk  = max(antenna_thick, 0.05);

        float3 baseL = float3(sgn * 0.055 * L, 0.035 * L, 0.385 * L);
        float3 scapeEnd = baseL + normalize(float3(sgn * (0.60 + sweep * 0.45), 0.30 * lift, 0.86)) * 0.34 * L * alen;
        float3 funEnd = scapeEnd + normalize(float3(sgn * (0.30 + sweep * 0.80), -0.30 + lift * 0.55, 0.92)) * 0.30 * L * alen;

        float3 A, B; float ra, rb;
        // The club: the funiculus THICKENS toward its tip, the opposite of every other limb on
        // the animal, and exactly what makes it read as an antenna. The ratio is preserved
        // through the thickness control rather than the tip being given a flat radius, or the
        // club vanishes the moment anyone thins the antennae.
        if (seg == 0u) { A = baseL;    B = scapeEnd; ra = 0.016 * L * atk; rb = 0.012 * L * atk; }
        else           { A = scapeEnd; B = funEnd;   ra = 0.012 * L * atk; rb = 0.019 * L * atk; }

        if (sv >= tubeSides * 6u) return degenerate();

        float3 tp, tn;
        agTubeN(sv, A, B, ra, rb, tubeSides, tp, tn);
        float3 wp = origin + Rr * tp.x + Ur * tp.y + F * tp.z;
        o.Position = mul(_ViewProjMatrix, float4(wp, 1.0));
        o.WorldPos = wp;
        o.Normal = normalize(Rr * tn.x + Ur * tn.y + F * tn.z);
        o.Tint = tintLimb * 0.92;
        o.Mat = float3(MAT_LIMB, 0.7, 0.0);
        return o;
    }
    else
    {
        // ---- MANDIBLES. Short, opposed, darker than the head.
        // At the bottom rung the mandibles go entirely. They are 0.115 body lengths long, so
        // below the cutoff they are a fraction of a pixel and all they contribute is aliasing.
        if (lod >= 3) return degenerate();

        uint mi = local - OFF_MAND;
        uint mand = mi / TUB_V;
        uint sv = mi - mand * TUB_V;
        if (sv >= tubeSides * 6u) return degenerate();
        float sgn = (mand == 0u) ? -1.0 : 1.0;

        float openA = 0.35 + 0.45 * a.contact;
        float3 A = float3(sgn * 0.058 * L, -0.015 * L, 0.400 * L);
        float3 B = A + normalize(float3(sgn * openA, -0.18, 1.0)) * 0.115 * L;

        float3 tp, tn;
        agTubeN(sv, A, B, 0.020 * L, 0.008 * L, tubeSides, tp, tn);
        float3 wp = origin + Rr * tp.x + Ur * tp.y + F * tp.z;
        o.Position = mul(_ViewProjMatrix, float4(wp, 1.0));
        o.WorldPos = wp;
        o.Normal = normalize(Rr * tn.x + Ur * tn.y + F * tn.z);
        o.Tint = tintGaster * 0.85;
        o.Mat = float3(MAT_THORAX, 1.2, 0.0);
        return o;
    }

    // body masses fall through
    float3 wp = origin + Rr * lp.x + Ur * lp.y + F * lp.z;
    o.Position = mul(_ViewProjMatrix, float4(wp, 1.0));
    o.WorldPos = wp;
    o.Normal = normalize(Rr * ln.x + Ur * ln.y + F * ln.z);
    o.Tint = tint;
    o.Mat = float3(mat, gloss, 0.0);
    return o;
}

// ---------------------------------------------------------------------------
// CONTACT SHADOWS — sampled, not computed.
//
// This was a per-pixel loop over the whole population: for every shaded point on the sweep,
// project each body along the light onto the plane and take the darkest. At 64 ants that was
// 59 M iterations a frame and payable. At 1024 it is 943 M, each loading a 96-byte record.
//
// The loop was not made cheaper, it was DELETED. The answer never depended on the camera: a
// contact shadow on a flat ground plane is a property of the arena, and it was being recomputed
// from scratch for every pixel that happened to look at the same square millimetre. FM_Colony
// now bakes it once over the arena — it owns the bucket grid that makes the query local — and
// this is a texture fetch.
//
// _Tex4 is that field. Bilinear, because the sweep is shaded at a far finer pitch than the
// field's 0.44 mm texel and a point sample would show its lattice on a perfectly flat surface,
// which reads as a rendering fault rather than as a resolution limit.
float sceneShadow(float2 w, FmRec arena)
{
    float2 uv = fmWorldToFieldUV(w, arena);
    if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) return 0.0;
    return _Tex4.SampleLevel(LinearSampler, uv, 0).r;
}

float4 PSMain(VS_OUTPUT In) : SV_TARGET
{
    FmRec arena = PlanB[FM_ARENA];
    FmRec lightR = PlanB[FM_LIGHT];
    float3 Ldir = normalize(lightR.pos);
    float3 N = normalize(In.Normal);
    float3 V = normalize(_CameraPos - In.WorldPos);

    // EYE DEPTH TRAVELS IN THE ALPHA CHANNEL, in millimetres.
    //
    // The obvious route — a second pass reading `source: "depth"` and linearizing — does not
    // work here, and the way it fails is instructive. Passes are scheduled by BUFFER
    // DEPENDENCY, and `source: "depth"` declares no relationship to the draw that fills the
    // depth buffer, so the reader is free to run first and sample a buffer still cleared to 1.0.
    // Measured through a banded diagnostic view, every pixel came back at the far plane, and
    // FM_Post's depth of field consequently blurred the entire frame uniformly at every
    // aperture — which reads as a broken lens and is a scheduling bug. Adding an explicit
    // `pass:scene` input to force the ordering did not fix it either.
    //
    // Writing the depth from the pass that already KNOWS the world position removes the whole
    // question: there is no second pass, no ordering, and no projection to invert. The alpha of
    // this target is otherwise unused — FM_Scope composites its own coverage and FM_Post reads
    // only rgb — and the working format is RGBA16F, which carries a few hundred millimetres
    // with room to spare.
    float eyeZ = length(In.WorldPos - _CameraPos);

    if (view_mode == 1) return float4(N * 0.5 + 0.5, eyeZ);

    // ---------------------------------------------------------------------------
    // THE SWEEP
    // ---------------------------------------------------------------------------
    if (In.Mat.x < -0.5)
    {
        float2 w = In.WorldPos.xz;
        float2 ahalf = fmArenaHalf(arena);
        float3 base = arena.tint;

        // Falloff. A studio sweep is blown out where the light lands and drops away toward the
        // edges; a perfectly flat white field reads as a matte rather than as a surface.
        float2 q = w / max(ahalf * 1.9, 1.0);
        base *= lerp(1.0, 1.0 - saturate(dot(q, q)) * arena.p1, 0.9);

        // Tooth. Paper at four-millimetres-per-ant has visible grain, and it is what stops the
        // sweep reading as a rendered gradient.
        base *= 1.0 - (fbm2D(w * 0.85, 3) * 0.5) * arena.p0 * 0.42;

        // PHEROMONE STAINING. Where the traffic has actually been, the substrate is slightly
        // darker and less even. Deliberately subtle: a trail you can SEE as a stripe is a
        // graphic, but one you can only just make out is a photograph of a trail.
        float2 fuv = fmWorldToFieldUV(w, arena);
        float4 fld = _Tex3.SampleLevel(LinearSampler, saturate(fuv), 0);
        float wear = saturate((fld.r * 0.75 + fld.g * 0.35) * stain_gain);
        if (abs(fuv.x - 0.5) > 0.5 || abs(fuv.y - 0.5) > 0.5) wear = 0.0;
        base *= lerp(1.0, 0.90, wear);

        float shadow = sceneShadow(w, arena);
        if (view_mode == 3) return float4(1.0 - shadow.xxx, eyeZ);
        if (view_mode == 4) return float4(fld.r, fld.g, fld.b * 0.3, eyeZ);

        float3 col = base * (lightR.p0 * saturate(Ldir.y) + lightR.p1);
        col *= lerp(1.0, 1.0 - shadow, shadow_gain);
        return float4(col * exposure, eyeZ);
    }

    if (view_mode == 3 || view_mode == 4) return float4(0.02, 0.02, 0.02, eyeZ);

    // ---------------------------------------------------------------------------
    // CHITIN
    //
    // A dielectric shell over pigment: coloured diffuse plus a NEUTRAL specular. Tinting the
    // highlight with the body colour is what makes CG insects look like painted plastic — a
    // highlight is a reflection of the light, not of the pigment.
    // ---------------------------------------------------------------------------
    float3 base = In.Tint;

    // A big softbox is not a point. Wrapping the diffuse round the terminator is what gives
    // macro insect photography its soft shoulder instead of a hard black edge.
    float wrapK = max(lightR.p1, 0.0) * 0.5;
    float diff = saturate((dot(N, Ldir) + wrapK) / (1.0 + wrapK));

    float3 H = normalize(Ldir + V);
    float spec = pow(saturate(dot(N, H)), max(lightR.p3, 8.0) * In.Mat.y);

    float sky = 0.5 + 0.5 * N.y;
    // Bounce off the white sweep, from below. Without it the undersides go dead black and the
    // legs disappear into their own shadows — on a white ground that is conspicuously wrong.
    float bounce = saturate(-N.y) * ground_bounce;

    float3 col = base * (diff * lightR.p0 * lightR.tint
                       + sky * lightR.p1 * float3(0.92, 0.95, 1.00)
                       + bounce * float3(1.00, 0.98, 0.95));

    col += lightR.tint * spec * spec_gain * In.Mat.y;

    // A narrow rim: at macro scale this is the light wrapping round a very small subject.
    col += pow(1.0 - saturate(dot(N, V)), 4.0) * rim_gain * float3(0.95, 0.96, 1.00);

    return float4(col * exposure, eyeZ);
}
