// VT_Plan / plan.hlsl — authors the whole vitrine composition into one durable record buffer.
//
// Single-threaded on purpose: the layout is sequential and the viewport event queue must be
// reduced in order. 64 records is trivial work next to any render pass.
//
// Regeneration is signature-driven. A parameter (or the R-key salt) changing the signature
// rebuilds the plan from scratch; anything else preserves the buffer, so hand edits made by
// dragging survive across cooks, saves, presets and undo.
#include "../_shared/vitrine.hlsli"

RWStructuredBuffer<PlanRec> Plan : register(u0);

// The plan buffer is persistent and only rebuilds when its signature changes. Parameters feed
// that signature — SHADER EDITS DO NOT. Bump this whenever the layout algorithm below changes
// or a recompile will silently keep serving the previously generated plan.
#define PLAN_VERSION 1.8

// ---------------------------------------------------------------------------
// Archetype tables, transcribed from where the reference actually puts things.
// Stage space, origin top-left, +y down. Seed jitter moves them; dragging overrides them.
// ---------------------------------------------------------------------------

// masses: pos, (reserve radius, growth scale), kind, material, tone
static const float2 MASS_POS[16] = {
    float2(0.268, 0.372), float2(0.470, 0.150), float2(0.818, 0.092), float2(0.908, 0.142),
    float2(0.795, 0.545), float2(0.892, 0.812), float2(0.118, 0.818), float2(0.186, 0.088),
    float2(0.560, 0.640), float2(0.350, 0.880), float2(0.930, 0.330), float2(0.075, 0.520),
    float2(0.640, 0.795), float2(0.480, 0.460), float2(0.720, 0.905), float2(0.170, 0.640)
};
static const float2 MASS_SIZE[16] = {
    float2(0.143, 1.18), float2(0.082, 0.70), float2(0.044, 0.52), float2(0.041, 0.48),
    float2(0.170, 1.02), float2(0.128, 0.96), float2(0.062, 0.46), float2(0.050, 0.50),
    float2(0.090, 0.58), float2(0.075, 0.44), float2(0.068, 0.40), float2(0.062, 0.36),
    float2(0.085, 0.52), float2(0.058, 0.34), float2(0.066, 0.38), float2(0.072, 0.42)
};
static const float MASS_KIND[16] = {
    MK_MELT, MK_BLOB, MK_RIBBON, MK_RIBBON, MK_ARMS, MK_HAND, MK_STAR, MK_RIBBON,
    MK_BLOB, MK_STAR, MK_RIBBON, MK_MELT, MK_HAND, MK_BLOB, MK_STAR, MK_ARMS
};
static const float MASS_MAT[16] = {
    MAT_CLAY, MAT_FROST, MAT_CHROME, MAT_CHROME, MAT_CLAY, MAT_CLAY, MAT_GLOSS, MAT_CHROME,
    MAT_FROST, MAT_GLOSS, MAT_CHROME, MAT_CLAY, MAT_CLAY, MAT_FROST, MAT_GLOSS, MAT_CLAY
};
// tone indexes VT_BODY: 0 magenta, 1 frost, 2 chrome, 3 coral, 4 terracotta, 5 hot pink
static const float MASS_TONE[16] = {
    0.02, 0.20, 0.38, 0.38, 0.55, 0.72, 0.20, 0.38,
    0.20, 0.20, 0.38, 0.02, 0.72, 0.20, 0.20, 0.55
};

// strokes: pos, half-extent, kind, accent tone
static const float2 STROKE_POS[16] = {
    float2(0.280, 0.660), float2(0.420, 0.860), float2(0.630, 0.235), float2(0.440, 0.350),
    float2(0.600, 0.930), float2(0.665, 0.900), float2(0.880, 0.620), float2(0.700, 0.350),
    float2(0.155, 0.930), float2(0.520, 0.760), float2(0.815, 0.960), float2(0.360, 0.180),
    float2(0.930, 0.480), float2(0.245, 0.470), float2(0.545, 0.560), float2(0.760, 0.700)
};
static const float2 STROKE_SIZE[16] = {
    float2(0.255, 0.275), float2(0.230, 0.155), float2(0.090, 0.165), float2(0.105, 0.048),
    float2(0.100, 0.045), float2(0.062, 0.038), float2(0.100, 0.220), float2(0.058, 0.140),
    float2(0.075, 0.040), float2(0.070, 0.055), float2(0.070, 0.035), float2(0.055, 0.045),
    float2(0.060, 0.120), float2(0.050, 0.060), float2(0.055, 0.042), float2(0.065, 0.070)
};
static const float STROKE_KIND[16] = {
    SK_BRANCH, SK_BRANCH, SK_BUNDLE, SK_BUNDLE, SK_TANGLE, SK_TANGLE, SK_ARC, SK_ARC,
    SK_TANGLE, SK_SQUIGGLE, SK_TANGLE, SK_SQUIGGLE, SK_ARC, SK_SQUIGGLE, SK_SQUIGGLE, SK_ARC
};
// tone indexes VT_ACCENT: 0 green 1 cyan 2 orange 3 red 4 yellow 5 blue 6 black 7 neon
static const float STROKE_TONE[16] = {
    0.80, 0.28, 0.10, 0.30, 0.55, 0.68, 0.42, 0.14,
    0.55, 0.68, 0.05, 0.30, 0.42, 0.80, 0.14, 0.10
};
// Stroke weight multiplier against VT_Growth's absolute base tube radius (0.014 stage units).
// The black vein network and the orange gradient tube are heavy; everything else is a hairline.
static const float STROKE_WEIGHT[16] = {
    1.00, 1.70, 0.30, 0.28, 0.26, 0.24, 0.32, 0.28,
    0.26, 0.30, 0.24, 0.26, 0.28, 0.26, 0.24, 0.30
};

// plates: pos, half-extent, kind, tone, front flag
static const float2 PLATE_POS[8] = {
    float2(0.170, 0.380), float2(0.760, 0.470), float2(0.300, 0.508), float2(0.360, 0.700),
    float2(0.245, 0.630), float2(0.295, 0.600), float2(0.360, 0.578), float2(0.450, 0.552)
};
static const float2 PLATE_SIZE[8] = {
    float2(0.130, 0.290), float2(0.112, 0.160), float2(0.190, 0.012), float2(0.152, 0.019),
    float2(0.024, 0.040), float2(0.022, 0.033), float2(0.030, 0.037), float2(0.028, 0.030)
};
static const float PLATE_KIND[8] = {
    PK_GRIDPLATE, PK_STARPANEL, PK_SHELF, PK_CHECKER, PK_BEAN, PK_BEAN, PK_BEAN, PK_BEAN
};
static const float PLATE_TONE[8] = { 0.00, 0.00, 0.00, 0.00, 0.90, 0.90, 0.90, 0.90 };
static const float PLATE_FRONT[8] = { 0.0, 0.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0 };

// ---------------------------------------------------------------------------
// Layout presets. Each is a different structural placement strategy applied on top of the
// archetype tables, so kinds, materials and palette survive a preset change.
// ---------------------------------------------------------------------------
float2 applyPreset(float2 p, uint slot, float s, out float scaleMul)
{
    int pre = (int)layout_preset;
    scaleMul = 1.0;
    float2 c = float2(0.5, 0.5);

    if (pre == 1)
    {
        // Salon Wall — everything snaps to a 4x4 hang. Each ROLE gets the full grid with its
        // own half-cell offset, otherwise the low slot indices of a short cast all land in the
        // top rows and the bottom of the wall stays empty.
        // The odd multipliers are coprime with 16, so a SHORT cast (say 8 masses) still spreads
        // over all four rows instead of stacking into the top two.
        uint local = (slot * 5u) & 15u;
        float2 bias = float2(0.0, 0.0);
        if (slot >= 32u)      { local = ((slot - 32u) * 3u) & 15u; bias = float2(-0.082, 0.052); }
        else if (slot >= 16u) { local = ((slot - 16u) * 7u) & 15u; bias = float2(0.098, 0.086); }
        uint col = local & 3u;
        uint row = (local >> 2) & 3u;
        float2 g = float2(0.150 + 0.233 * (float)col, 0.165 + 0.228 * (float)row) + bias;
        float2 j = (vt_hash22(float2(s * 3.1 + (float)slot, 11.0)) - 0.5) * 0.045;
        scaleMul = 0.92;
        return g + j;
    }
    if (pre == 2)
    {
        // Diagonal Drift — the whole cast strung along a descending diagonal, scale ramping
        // with position so it reads as a procession receding to the lower right.
        uint local = (slot >= 32u) ? (slot - 32u) : ((slot >= 16u) ? (slot - 16u) : slot);
        // Deterministic march along the diagonal with a small per-role phase, so the procession
        // reads as a procession. A random-dominated t just clumps.
        float rolePhase = (slot >= 32u) ? 0.052 : ((slot >= 16u) ? 0.026 : 0.0);
        float t = frac((float)local * 0.0781 + rolePhase + vt_rnd(s + (float)slot * 2.3, 4.0) * 0.075);
        float2 g = lerp(float2(0.115, 0.130), float2(0.900, 0.905), t);
        float off = (vt_rnd(s + (float)slot, 9.0) - 0.5) * 0.24;
        g += float2(-off * 0.55, off);
        scaleMul = lerp(1.25, 0.62, t);
        return g;
    }
    if (pre == 3)
    {
        // Column Rack — three tall bays, elements stacked inside a bay. The vertical rhythm
        // of the reference's rainbow bundle applied to the whole composition.
        uint local = (slot >= 32u) ? (slot - 32u) : ((slot >= 16u) ? (slot - 16u) : slot);
        uint bay = local % 3u;
        float bx = 0.185 + 0.315 * (float)bay;
        float ty = frac(vt_rnd(s + (float)slot * 1.7, 6.0) + (float)(local / 3u) * 0.19);
        float2 g = float2(bx + (vt_rnd(s + (float)slot, 2.0) - 0.5) * 0.115,
                          0.115 + ty * 0.780);
        scaleMul = lerp(0.80, 1.15, vt_rnd(s + (float)slot, 8.0));
        return g;
    }

    // 0 Vitrine — the transcribed reference arrangement, breathed in or out from centre.
    float2 j = (vt_hash22(float2(s * 5.7 + (float)slot * 3.3, 2.9)) - 0.5) * 2.0 * jitter;
    return c + (p - c) * spread + j;
}

// Stratified placement for the randomizer.
//
// A uniform random draw clumps: with 16 records you reliably get three in one corner and a bare
// third of the stage. Assigning each record a distinct cell of a 4x4 grid and jittering INSIDE
// that cell guarantees coverage while still being random. `stride` must be coprime with 16 so
// the permutation is a bijection; each role uses a different one so masses, strokes and plates
// interleave across the stage instead of stacking in the same cells.
float2 stratified(uint slot, uint stride, float s, float rs, float inset)
{
    uint cell = (slot * stride + (uint)(vt_rnd(s, 77.0) * 16.0)) & 15u;
    float cx = (float)(cell & 3u);
    float cy = (float)((cell >> 2) & 3u);
    float2 jit = float2(vt_rnd(rs, 41.0), vt_rnd(rs, 42.0));
    return (float2(cx, cy) + inset + (1.0 - 2.0 * inset) * jit) * 0.25;
}

void buildMasses(float s)
{
    uint want = (uint)clamp((float)mass_count, 0.0, 16.0);
    float v = saturate(variation);
    for (uint i = 0u; i < PLAN_MASSES; i++)
    {
        PlanRec r = (PlanRec)0;
        // A randomization stream kept separate from r.seed, so re-rolling ONE record with N
        // does not shift what every other record drew.
        float rs = s * 11.7 + (float)i * 29.3 + 101.0;

        // Position goes fully free. SIZE does not: the table already encodes the composition's
        // hierarchy (one hero mass, two supports, the rest incidental), and a flat random size
        // draw destroys that hierarchy and reads as noise. Randomizing the MAGNITUDE around
        // each slot's rank keeps a random arrangement composed.
        float2 rndPos = stratified(i, 7u, s, rs, 0.18);
        float2 rndSz  = MASS_SIZE[i] * float2(lerp(0.70, 1.45, vt_rnd(rs, 3.0)),
                                              lerp(0.75, 1.30, vt_rnd(rs, 4.0)));

        // `variation` blends the transcribed reference arrangement into a free draw from the
        // same vocabulary. At 0 the tables are used verbatim, so the default look is exact.
        float2 pos = lerp(MASS_POS[i], rndPos, v);
        float2 sz  = lerp(MASS_SIZE[i], rndSz, v);
        float kind = (vt_rnd(rs, 5.0) < v) ? min(floor(vt_rnd(rs, 6.0) * (float)MK_KINDS), (float)(MK_KINDS - 1)) : MASS_KIND[i];
        float mat  = (vt_rnd(rs, 7.0) < v) ? min(floor(vt_rnd(rs, 8.0) * (float)MAT_COUNT), (float)(MAT_COUNT - 1)) : MASS_MAT[i];
        float tone = lerp(MASS_TONE[i], vt_rnd(rs, 9.0), v);

        float sm;
        r.pos  = clamp(applyPreset(pos, i, s, sm), 0.05, 0.95);
        r.size = float2(sz.x * scale_master * sm, sz.y * scale_master * sm);
        r.role = ROLE_MASS;
        r.kind = kind;
        r.seed = s * 3.3 + (float)i * 17.0 + 1.0;
        r.tone = tone;
        // depth band: bigger masses sit nearer, plus a per-record spread
        r.grp = saturate(lerp(0.5, sz.y * 0.7 + vt_rnd(r.seed, 1.0) * 0.4, depth_spread));
        r.phase = vt_rnd(r.seed, 5.0);
        r.active = (i < want) ? 1.0 : 0.0;
        // Material lives in the high bits of flags, on its own axis, so K can cycle kind
        // without destroying the surface assignment.
        r.flags = (float)(((uint)mat) << 8);
        Plan[PLAN_MASS_0 + i] = r;
    }
}

// Push overlapping mass anchors apart using the reserve radii they already carry.
//
// This is the difference between "randomized" and "usable". A free positional draw piles two or
// three masses on the same spot roughly every other seed, and the result reads as a mistake
// rather than as a new arrangement. A few relaxation passes over 16 records costs nothing and
// makes every seed presentable. It runs ONLY when variation is engaged, so the reference
// arrangement is never nudged off its transcribed positions.
void relaxMasses()
{
    for (uint iter = 0u; iter < 6u; iter++)
    {
        for (uint a = 0u; a < PLAN_MASSES; a++)
        {
            PlanRec ra = Plan[PLAN_MASS_0 + a];
            if (ra.active < 0.5) continue;
            for (uint b = a + 1u; b < PLAN_MASSES; b++)
            {
                PlanRec rb = Plan[PLAN_MASS_0 + b];
                if (rb.active < 0.5) continue;

                float2 d = ra.pos - rb.pos;
                float dist = length(d);
                float minD = (ra.size.x + rb.size.x) * spacing;
                if (dist < minD && dist > 1e-5)
                {
                    float2 push = (d / dist) * (minD - dist) * 0.5;
                    ra.pos = clamp(ra.pos + push, 0.06, 0.94);
                    rb.pos = clamp(rb.pos - push, 0.06, 0.94);
                    Plan[PLAN_MASS_0 + b] = rb;
                }
            }
            Plan[PLAN_MASS_0 + a] = ra;
        }
    }
}

void buildStrokes(float s)
{
    uint want = (uint)clamp((float)stroke_count, 0.0, 16.0);
    float v = saturate(variation);
    for (uint i = 0u; i < PLAN_STROKES; i++)
    {
        PlanRec r = (PlanRec)0;
        float rs = s * 13.1 + (float)i * 37.7 + 211.0;

        float2 rndPos = stratified(i, 11u, s, rs, 0.12);
        float2 rndSz  = STROKE_SIZE[i] * float2(lerp(0.70, 1.40, vt_rnd(rs, 3.0)),
                                                lerp(0.70, 1.40, vt_rnd(rs, 4.0)));

        float2 pos = lerp(STROKE_POS[i], rndPos, v);
        float2 sz  = lerp(STROKE_SIZE[i], rndSz, v);
        float kind = (vt_rnd(rs, 5.0) < v) ? min(floor(vt_rnd(rs, 6.0) * (float)SK_KINDS), (float)(SK_KINDS - 1)) : STROKE_KIND[i];
        float tone = lerp(STROKE_TONE[i], vt_rnd(rs, 7.0), v);
        // Weight stays BIMODAL under randomization: a couple of heavy marks and the rest
        // hairlines. Drawing weight uniformly makes every random seed read as flat spaghetti.
        float rndW = (vt_rnd(rs, 8.0) < 0.20) ? lerp(0.95, 1.80, vt_rnd(rs, 9.0))
                                              : lerp(0.22, 0.36, vt_rnd(rs, 10.0));
        float wgt  = lerp(STROKE_WEIGHT[i], rndW, v);

        float sm;
        r.pos  = clamp(applyPreset(pos, i + 16u, s, sm), 0.04, 0.96);
        r.size = float2(sz.x * scale_master * sm, sz.y * scale_master * sm);
        r.role = ROLE_STROKE;
        r.kind = kind;
        r.seed = s * 7.1 + (float)i * 23.0 + 5.0;
        r.tone = tone;
        r.grp = saturate(0.35 + vt_rnd(r.seed, 3.0) * 0.5 * depth_spread);
        // stroke weight lives in phase: consumers read it as the tube radius multiplier
        r.phase = wgt * stroke_weight;
        r.flags = 0.0;
        r.active = (i < want) ? 1.0 : 0.0;
        Plan[PLAN_STROKE_0 + i] = r;
    }
}

// A randomized plate must take its extent from its KIND, not from whatever the slot used to
// hold — a bean wearing a wall panel's dimensions reads as a bug, not as variety.
float2 plateSizeForKind(int k, float rs)
{
    if (k == PK_GRIDPLATE) return float2(lerp(0.070, 0.155, vt_rnd(rs, 20.0)), lerp(0.120, 0.300, vt_rnd(rs, 21.0)));
    if (k == PK_STARPANEL) return float2(lerp(0.070, 0.140, vt_rnd(rs, 22.0)), lerp(0.090, 0.200, vt_rnd(rs, 23.0)));
    if (k == PK_SHELF)     return float2(lerp(0.100, 0.220, vt_rnd(rs, 24.0)), lerp(0.008, 0.016, vt_rnd(rs, 25.0)));
    if (k == PK_CHECKER)   return float2(lerp(0.080, 0.180, vt_rnd(rs, 26.0)), lerp(0.012, 0.026, vt_rnd(rs, 27.0)));
    if (k == PK_BEAN)      { float b = lerp(0.018, 0.036, vt_rnd(rs, 28.0)); return float2(b, b * lerp(0.75, 1.45, vt_rnd(rs, 29.0))); }
    float d = lerp(0.010, 0.030, vt_rnd(rs, 30.0));
    return float2(d, d * 0.24);
}

void buildPlates(float s)
{
    uint wantDash = (uint)clamp((float)confetti, 0.0, 16.0);
    float v = saturate(variation);
    for (uint i = 0u; i < PLAN_PLATES; i++)
    {
        PlanRec r = (PlanRec)0;
        r.role = ROLE_PLATE;
        float sd = s * 2.7 + (float)i * 13.37 + 3.0;
        float rs = s * 17.3 + (float)i * 41.9 + 331.0;
        r.seed = sd;

        if (i < 8u)
        {
            bool swapped = (vt_rnd(rs, 5.0) < v);
            int k = swapped ? (int)min(floor(vt_rnd(rs, 6.0) * (float)PK_KINDS), (float)(PK_KINDS - 1))
                            : (int)PLATE_KIND[i];
            float2 kSz = plateSizeForKind(k, rs);
            float2 sz  = swapped ? kSz : lerp(PLATE_SIZE[i], kSz, v);
            float2 rndPos = stratified(i, 5u, s, rs, 0.15);
            float2 pos = lerp(PLATE_POS[i], rndPos, v);

            // Layer membership follows the KIND, so a randomized panel still hangs behind the
            // masses and a randomized pebble still stands in front of them.
            bool front = !(k == PK_GRIDPLATE || k == PK_STARPANEL);

            float sm;
            r.pos  = clamp(applyPreset(pos, i + 32u, s, sm), 0.03, 0.97);
            r.size = sz * scale_master * sm;
            r.kind = (float)k;
            r.tone = (k == PK_BEAN) ? 0.90 : lerp(PLATE_TONE[i], vt_rnd(rs, 9.0), v);
            r.grp  = front ? 0.75 : 0.20;
            r.phase = vt_rnd(sd, 2.0);
            r.flags = front ? (float)F_FRONT : 0.0;
            r.active = 1.0;
        }
        else
        {
            // Confetti dashes. At variation 0 they sit in the reference's upper-left field;
            // as it rises the scatter opens out across the whole stage.
            uint k = i - 8u;
            float2 h = vt_hash22(float2(sd, 4.4));
            float2 base = float2(0.055 + h.x * 0.42, 0.030 + h.y * 0.34);
            if ((k & 3u) == 3u) base = float2(0.10 + h.x * 0.80, 0.020 + h.y * 0.16);
            float2 wide = float2(0.04 + h.x * 0.92, 0.03 + h.y * 0.94);
            base = lerp(base, wide, v);

            float2 j = (vt_hash22(float2(sd * 1.9, 8.1)) - 0.5) * 2.0 * jitter;
            r.pos  = clamp(base + j, 0.02, 0.98);
            float ln = lerp(0.010, 0.030, vt_rnd(sd, 6.0)) * scale_master;
            r.size = float2(ln, ln * 0.24);
            r.kind = PK_DASH;
            r.tone = vt_rnd(sd, 7.0);
            r.grp  = 0.85;
            r.phase = (vt_rnd(sd, 9.0) - 0.5) * 3.14159;   // dash rotation
            r.flags = (float)F_FRONT;
            r.active = (k < wantDash) ? 1.0 : 0.0;
        }
        Plan[PLAN_PLATE_0 + i] = r;
    }
}

// Nearest pickable record under a stage-space point. Smallest hit wins so a dash sitting on a
// big plate stays reachable; masses and strokes win inside their core disc.
uint pickRecord(float2 p)
{
    uint best = 0u; float bestScore = 1e9;
    for (uint m = 0u; m < PLAN_MASSES; m++)
    {
        PlanRec r = Plan[PLAN_MASS_0 + m];
        if (r.active < 0.5) continue;
        float d = length(p - r.pos);
        if (d < r.size.x * 0.55 && d < bestScore) { bestScore = d; best = PLAN_MASS_0 + m + 1u; }
    }
    if (best != 0u) return best;
    for (uint st = 0u; st < PLAN_STROKES; st++)
    {
        PlanRec r = Plan[PLAN_STROKE_0 + st];
        if (r.active < 0.5) continue;
        float d = length((p - r.pos) / max(r.size, 0.01));
        if (d < 1.0 && d < bestScore) { bestScore = d; best = PLAN_STROKE_0 + st + 1u; }
    }
    if (best != 0u) return best;
    for (uint i = 0u; i < PLAN_PLATES; i++)
    {
        PlanRec r = Plan[PLAN_PLATE_0 + i];
        if (r.active < 0.5) continue;
        float2 q = abs(p - r.pos) - r.size - 0.006;
        if (max(q.x, q.y) < 0.0)
        {
            float area = r.size.x * r.size.y;
            if (area < bestScore) { bestScore = area; best = PLAN_PLATE_0 + i + 1u; }
        }
    }
    return best;
}

[numthreads(1, 1, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    PlanRec hdr = Plan[PLAN_HEADER];
    float initFlag = hdr.tone;
    float salt     = hdr.seed;
    float sel      = hdr.pos.y;      // selected index + 1, 0 = nothing
    float dragOn   = hdr.size.x;
    float2 grab    = float2(hdr.size.y, hdr.kind);

    uint n = min((uint)_ViewportEventCount, 64u);

    // --- pass 1: keys. R changes the salt, so it must land before the signature test.
    for (uint e = 0u; e < n; e++)
    {
        ViewportEvent ev = _ViewportEvents[e];
        if (ev.type != 4u || ev.phase != 1u) continue;
        uint c = (uint)ev.code;
        if (c == 18u) salt += 1.0;                                   // R  reseed
        else if (c == 3u) sel = 0.0;                                 // C  clear selection
        else if (sel > 0.5)
        {
            uint idx = (uint)(sel - 1.0);
            PlanRec r = Plan[idx];
            uint fl = (uint)r.flags;
            if (c == 11u)                                            // K  cycle kind
            {
                if (r.role == ROLE_PLATE)       r.kind = fmod(r.kind + 1.0, (float)PK_KINDS);
                else if (r.role == ROLE_STROKE) r.kind = fmod(r.kind + 1.0, (float)SK_KINDS);
                else                            r.kind = fmod(r.kind + 1.0, (float)MK_KINDS);
                r.flags = (float)(fl | F_EDITED);
            }
            else if (c == 13u)                                       // M  cycle material
            {
                uint mat = (fl >> 8) & 15u;
                mat = (mat + 1u) % (uint)MAT_COUNT;
                r.flags = (float)((fl & 0xFFu) | (mat << 8) | F_EDITED);
            }
            else if (c == 24u)                                       // X  toggle active
            {
                r.active = (r.active > 0.5) ? 0.0 : 1.0;
                r.flags = (float)(fl | F_EDITED);
            }
            else if (c == 14u)                                       // N  re-roll this record
            {
                r.seed += 7.77;
                r.tone = vt_rnd(r.seed, 1.0);
                r.phase = vt_rnd(r.seed, 2.0);
                r.flags = (float)(fl | F_EDITED);
            }
            Plan[idx] = r;
        }
    }

    float sig = seed * 7.31 + (float)layout_preset * 37.7 + (float)mass_count * 1.13
              + (float)stroke_count * 2.17 + (float)confetti * 3.31 + spread * 53.1
              + scale_master * 97.3 + depth_spread * 31.7 + jitter * 61.3
              + stroke_weight * 43.9 + variation * 137.9 + spacing * 71.3
              + salt * 101.3 + PLAN_VERSION * 911.7;

    if (initFlag < 0.5 || abs(sig - hdr.pos.x) > 1e-4)
    {
        float s = seed + salt * 3.19;
        buildMasses(s);
        if (variation > 0.001) relaxMasses();
        buildStrokes(s);
        buildPlates(s);
        sel = 0.0; dragOn = 0.0;
    }

    // --- pass 2: pointer. Selection and drag share pickRecord()/stage space with the canvas.
    for (uint e2 = 0u; e2 < n; e2++)
    {
        ViewportEvent ev = _ViewportEvents[e2];
        if (ev.type != 5u) continue;
        float2 p = ev.position;
        if (ev.code == 1u && ev.phase == 7u)
        {
            sel = (float)pickRecord(p);
        }
        else if (ev.code == 3u)
        {
            if (ev.phase == 5u)
            {
                uint hit = pickRecord(p);
                sel = (float)hit;
                if (hit != 0u) { dragOn = 1.0; grab = Plan[hit - 1u].pos - p; }
            }
            else if (ev.phase == 6u && dragOn > 0.5 && sel > 0.5)
            {
                uint idx = (uint)(sel - 1.0);
                PlanRec r = Plan[idx];
                r.pos = clamp(p + grab, 0.02, 0.98);
                r.flags = (float)(((uint)r.flags) | F_EDITED);
                Plan[idx] = r;
            }
            else { dragOn = 0.0; }
        }
    }

    // selection flag is derived, never stored twice
    for (uint i = 0u; i < PLAN_RECORDS - 1u; i++)
    {
        PlanRec r = Plan[i];
        uint f = (uint)r.flags;
        f = (sel > 0.5 && (uint)(sel - 1.0) == i) ? (f | F_SELECTED) : (f & ~F_SELECTED);
        r.flags = (float)f;
        Plan[i] = r;
    }

    uint liveM = 0u, liveS = 0u, liveP = 0u;
    for (uint a = 0u; a < PLAN_MASSES;  a++) if (Plan[PLAN_MASS_0 + a].active   > 0.5) liveM++;
    for (uint b = 0u; b < PLAN_STROKES; b++) if (Plan[PLAN_STROKE_0 + b].active > 0.5) liveS++;
    for (uint d = 0u; d < PLAN_PLATES;  d++) if (Plan[PLAN_PLATE_0 + d].active  > 0.5) liveP++;

    // Global stage geometry, published every cook so a horizon tweak is live without a rebuild.
    PlanRec st = (PlanRec)0;
    st.pos = float2(horizon, room_depth);
    st.role = ROLE_HEADER;
    st.active = 1.0;
    Plan[PLAN_STAGE] = st;

    hdr.pos    = float2(sig, sel);
    hdr.size   = float2(dragOn, grab.x);
    hdr.role   = ROLE_HEADER;
    hdr.kind   = grab.y;
    hdr.seed   = salt;
    hdr.tone   = 1.0;
    hdr.grp    = (float)liveM;
    hdr.phase  = (float)liveS;
    hdr.flags  = (float)liveP;
    hdr.active = 1.0;
    Plan[PLAN_HEADER] = hdr;
}
