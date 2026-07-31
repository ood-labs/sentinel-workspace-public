// VT_Plates / plates_body.hlsli — the flat graphic family.
//
// The reference mixes sculpture with pure graphic design: a pink grid-textured cutout, a
// checkerboard strip in slight perspective, a starfield portal panel, a translucent glass
// shelf, glossy bean pebbles and scattered confetti dashes. None of these want to be 3D — they
// are plates, and drawing them as plates keeps them crisp and costs almost nothing.
//
// Two lanes are published because the starfield panel is largely BLACK. Against a dark stage
// its colour is indistinguishable from nothing, so coverage has to be its own output.
#include "../_shared/vitrine.hlsli"

StructuredBuffer<PlanRec> Plan : register(t0);

// ---------------------------------------------------------------------------
// Per-kind fills. `q` is local to the plate: [-1,1] on both axes.
// ---------------------------------------------------------------------------
float3 fillGridPlate(float2 q, float2 halfsz, float sd, float px, out float ink)
{
    // pink slab with a raised mortar grid, exactly the "tiled wall" texture in the reference
    float2 cells = float2(round(halfsz.x * grid_density * 2.0), round(halfsz.y * grid_density * 2.0));
    cells = max(cells, 1.0);
    float2 g = abs(frac(q * cells * 0.5) - 0.5);
    float lw = grid_weight * 0.045;
    float mortar = 1.0 - smoothstep(lw * 0.5, lw * 1.6, min(g.x, g.y));

    float3 base = plate_col.rgb;
    float3 col = base * (1.0 - 0.42 * mortar);
    // soft interior relief so the slab is not a flat swatch
    col *= 0.92 + 0.16 * vt_fbm2(q * 5.0 + 3.1, 3);
    // lit top edge
    col += base * smoothstep(0.0, 0.35, -q.y) * 0.10;
    ink = 1.0;
    return col;
}

float3 fillChecker(float2 q, out float ink)
{
    // slight perspective: the strip tilts away, so the squares compress upward
    float persp = 1.0 / (1.0 + checker_tilt * (q.y * 0.5 + 0.5));
    float2 p = float2(q.x * persp, q.y);
    float2 c = floor(float2(p.x * checker_count, p.y * 1.0 + 0.5));
    float odd = fmod(c.x + c.y, 2.0);
    float3 col = lerp(float3(0.045, 0.045, 0.050), C_PAPER, odd);
    ink = 1.0;
    return col;
}

float3 fillStarPanel(float2 q, float sdv, out float ink)
{
    // A portal: black star field on top, a saturated band, then a pale textured base. It reads
    // as a picture hung in the room rather than an object in it.
    float3 col;
    float band1 = star_split;
    float band2 = star_split + 0.22;
    float y = q.y * 0.5 + 0.5;

    if (y < band1)
    {
        col = float3(0.012, 0.012, 0.018);
        // stars: sparse, hard, unblurred points
        float2 cell = q * 26.0;
        float2 id = floor(cell);
        float2 f = frac(cell) - 0.5;
        float2 jitter = (vt_hash22(id + 11.3) - 0.5) * 0.7;
        float d = length(f - jitter);
        float bright = vt_hash21(id * 1.7 + 4.2);
        if (bright > 0.62)
            col += float3(1, 1, 1) * smoothstep(0.16, 0.02, d) * (0.35 + 0.65 * bright);
        // a pale organic shape floating in the field
        float blob = length(q * float2(1.0, 1.5) - float2(0.15, -0.45)) - 0.42;
        col = lerp(col, C_PAPER * 0.92, smoothstep(0.02, -0.02, blob));
    }
    else if (y < band2)
    {
        col = lerp(C_CORAL, C_PAPER, step(0.5, frac((y - band1) / 0.22 * 2.0)));
    }
    else
    {
        col = C_PAPER * (0.86 + 0.20 * vt_fbm2(q * 9.0 + 7.7, 3));
    }
    ink = 1.0;
    return col;
}

float3 fillShelf(float2 q, out float ink)
{
    // a thin translucent slab seen almost edge-on: bright leading edge, faint body
    float body = 0.22 + 0.30 * smoothstep(1.0, 0.0, abs(q.y));
    float3 col = C_HORIZON * body * 0.55 + C_PAPER * 0.10;
    col += C_PAPER * smoothstep(0.55, 1.0, -q.y) * 0.75;      // lit top lip
    ink = 0.55;                                               // genuinely semi-transparent
    return col;
}

float3 fillBean(float2 q, float sdv, float rad, out float ink)
{
    // glossy pebble: sphere-normal fake from the plate's own distance field
    float nz = sqrt(saturate(1.0 - dot(q, q)));
    float3 n = normalize(float3(q * 0.85, max(nz, 0.05)));
    float3 L = normalize(float3(-0.45, -0.55, 0.70));
    float lam = saturate(dot(n, L));
    float3 base = C_NEON;
    float3 col = base * (0.32 + 0.80 * lam);
    float3 hv = normalize(L + float3(0, 0, 1));
    col += float3(1, 1, 1) * pow(saturate(dot(n, hv)), 34.0) * 0.85;
    col += base * pow(saturate(1.0 - nz), 3.0) * 0.35;        // rim
    ink = 1.0;
    return col;
}

float3 fillDash(float2 q, float tone, out float ink)
{
    float nz = sqrt(saturate(1.0 - q.y * q.y));
    float3 c = vt_accent(tone);
    ink = 1.0;
    return c * (0.70 + 0.45 * nz);
}

// Draws only the plates belonging to one layer. `wantFront` selects the F_FRONT half, which is
// what lets VT_Composite put the sculpted masses BETWEEN the hung panels and the objects
// standing in front of them.
void drawPlates(float2 uv, float px, bool wantFront, out float3 outCol, out float outCov)
{
    float3 col = float3(0, 0, 0);
    float cov = 0.0;

    [loop]
    for (uint i = 0u; i < PLAN_PLATES; i++)
    {
        PlanRec r = Plan[PLAN_PLATE_0 + i];
        if (r.active < 0.5) continue;
        bool isFront = ((((uint)r.flags) & F_FRONT) != 0u);
        if (isFront != wantFront) continue;

        int kind = (int)r.kind;
        float2 e = max(r.size, 0.002);
        float2 d2 = uv - r.pos;
        if (kind == PK_DASH) d2 = vt_rot2(d2, -r.phase);

        // quick reject
        if (abs(d2.x) > e.x + 0.02 || abs(d2.y) > e.y + 0.02) continue;

        float round_r = 0.0;
        if (kind == PK_BEAN)      round_r = min(e.x, e.y) * 0.98;
        else if (kind == PK_DASH) round_r = min(e.x, e.y) * 0.95;
        else if (kind == PK_GRIDPLATE) round_r = min(e.x, e.y) * 0.22;
        else if (kind == PK_STARPANEL) round_r = min(e.x, e.y) * 0.30;

        float sd = vt_dRBox(d2, e, round_r);
        float a = vt_fill(sd, px);
        if (a <= 0.001) continue;

        float2 q = d2 / e;
        float ink = 1.0;
        float3 c;

        if (kind == PK_GRIDPLATE)      c = fillGridPlate(q, e, sd, px, ink);
        else if (kind == PK_CHECKER)   c = fillChecker(q, ink);
        else if (kind == PK_STARPANEL) c = fillStarPanel(q, sd, ink);
        else if (kind == PK_SHELF)     c = fillShelf(q, ink);
        else if (kind == PK_BEAN)      c = fillBean(q, sd, min(e.x, e.y), ink);
        else                           c = fillDash(q, r.tone, ink);

        float aa = a * ink;
        col = col * (1.0 - aa) + c * aa;
        cov = cov + (1.0 - cov) * aa;
    }

    outCol = col * exposure;
    outCov = cov;
}
