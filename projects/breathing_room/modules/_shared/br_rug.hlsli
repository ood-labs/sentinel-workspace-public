// br_rug.hlsli -- a hand-knotted Persian rug, evaluated procedurally at the knot.
//
// The layout follows how a classical city rug is drawn, from the selvedge in:
//
//   overcast selvedge | outer guard (reciprocal "running dog" scroll between two fine lines) |
//   MAIN BORDER (a continuous scrolling vine carrying shah-abbasi palmettes and rosettes in
//   alternation, upright and inverted, with lancet leaves and tendrils; a rosette turns each
//   corner) | inner guard (a small meander of buds) | FIELD
//
// and three families of field (`style`):
//   0 TABRIZ   a scalloped central medallion (concentric ivory / indigo / red grounds, a ring of
//              palmettes, a rosette heart), lobed pendants with palmette finials on the long axis,
//              quarter medallions in the corners, and an all-over floral field round them
//   1 ISFAHAN  no medallion: the all-over floral field edge to edge, denser and finer
//   2 HERIZ    the village answer: an angular stepped medallion and spandrels, drawn on the knot
//              grid with straight lines, big and bold
//
// The all-over field is ONE mirrored tile (symmetric in both axes, as the rug is), so every vine
// that reaches a tile edge meets its own mirror and the field is continuous by construction:
// a rosette at each tile centre, a four-way palmette cluster at each tile corner, spiral vines
// joining them with lancet leaves.
//
// Then what makes it look made rather than printed: a brown-black outline (the corrosive dye that
// eats the wool) round every motif, ABRASH (dye-lot bands across the weave), knot quantisation
// (each knot one colour, once knots are resolvable), yarn-to-yarn variation, and traffic wear.
// Everything is anti-aliased against the pixel footprint `aa`, and detail smaller than a pixel
// fades to its average instead of shimmering.
//
// BR_Rug publishes the design records (palette, proportions, family, seed, abrash, wear);
// rugDefault() is the design the renderer uses until it is linked.
#ifndef BR_RUG_HLSLI
#define BR_RUG_HLSLI

struct BRRugDesign
{
    float3 field, border, ivory, gold, green, blue, outline, rose;   // linear
    float borderW;        // main border width, fraction of the short side
    float medallion;      // medallion size, fraction of the field's short side
    float motif;          // field tile scale (m)
    float abrash;         // 0..1
    float wear;           // 0..1
    float knot;           // knot pitch (m)
    float seed;
    int style;            // 0 Tabriz medallion, 1 Isfahan all-over, 2 Heriz geometric
    // THE TRIP (0 = the rug as woven; the renderer fills these, BR_Rug's editor leaves them 0).
    // The ornament comes alive rather than being warped: field flowers bloom and turn in rings
    // that leave the centre, the medallion's palmettes orbit it and its scallops ripple, the
    // border's vine travels round the rug with the guards running against it, and the dyes trade
    // places within the rug's own palette.
    float time;           // trip seconds
    float flow;           // the border and guards travelling; the abrash drifting (drift x dose)
    float bloom;          // flowers blooming, turning, orbiting (geometry x dose)
    float hue;            // colours trading places in the palette (colour x dose)
    float flowT, bloomT;  // BR_Trip's integrated clocks: distance travelled, angle turned
};
// the medallion's scallops ripple round it (rugMedSD reads this; rugDesign sets it)
static float g_rugScallop = 0.0;

float3 rugSrgb(float3 c) { return pow(max(c, 0.0), 2.2); }

BRRugDesign rugDefault()
{
    BRRugDesign d;
    d.field   = rugSrgb(float3(0.55, 0.12, 0.10));      // madder red
    d.border  = rugSrgb(float3(0.09, 0.11, 0.23));      // indigo
    d.ivory   = rugSrgb(float3(0.87, 0.81, 0.67));
    d.gold    = rugSrgb(float3(0.79, 0.58, 0.27));      // weld and walnut: camel gold
    d.green   = rugSrgb(float3(0.24, 0.40, 0.33));
    d.blue    = rugSrgb(float3(0.42, 0.55, 0.66));
    d.outline = rugSrgb(float3(0.11, 0.07, 0.05));      // the brown-black that eats the wool
    d.rose    = rugSrgb(float3(0.78, 0.44, 0.40));
    d.borderW = 0.115; d.medallion = 0.42; d.motif = 0.24; d.abrash = 0.5; d.wear = 0.3;
    d.knot = 0.0034; d.seed = 0.37; d.style = 0;
    d.time = 0.0; d.flow = 0.0; d.bloom = 0.0; d.hue = 0.0; d.flowT = 0.0; d.bloomT = 0.0;
    return d;
}
// a motif colour trading places with the next dye in the cycle gold -> rose -> blue -> gold, on
// its own slow phase (`ph`, radians); the rug's own dyes only, never an arbitrary hue
float3 rugTrade(float3 c, float3 next, BRRugDesign R, float ph)
{
    return lerp(c, next, R.hue * (0.5 + 0.5 * sin(R.time * 0.25 + ph)));
}

// ---------------------------------------------------------------------------------------------
// RUG BUFFER (BR_Rug, 16 records)
//   0       HEADER  head (ROLE_RUG, style, seed, version)  dims (borderW, medallion, motif, abrash)
//                   look (wear, knot pitch, palette preset, 0)  meta (rose rgb linear, 0)
//   1..7    COLOUR  dims.rgb linear: field, border, ivory, gold, green, blue, outline
//   8       EDITOR  BR_Rug private      9..15  DELTAS (BR_Rug private)
// The renderer copies records 0..7 into its scene buffer; define RUG_REC(i) to read them.
#define RUG_RECORDS 16
#define RUG_EDITOR  8
#define RUG_DELTA0  9
#define RUG_SLOTS   8          // colour slots: field, border, ivory, gold, green, blue, outline, rose

// The dyes each colour slot may take (sRGB), as a dyer would offer them. A palette preset is a
// dye index per slot; clicking a swatch in BR_Rug steps that slot along its own list.
static const float3 RUG_DYES[RUG_SLOTS * 6] = {
    // field: madder, rust, deep indigo, ivory, camel, aubergine
    float3(0.55, 0.12, 0.10), float3(0.62, 0.27, 0.13), float3(0.09, 0.11, 0.23), float3(0.86, 0.80, 0.66), float3(0.72, 0.55, 0.35), float3(0.30, 0.12, 0.18),
    // border: indigo, madder, ivory, dark green, brown-black, rust
    float3(0.09, 0.11, 0.23), float3(0.48, 0.10, 0.09), float3(0.85, 0.79, 0.65), float3(0.14, 0.24, 0.20), float3(0.13, 0.09, 0.07), float3(0.58, 0.25, 0.12),
    // ivory: ivory, cream, pale camel, undyed grey, ivory, cream
    float3(0.87, 0.81, 0.67), float3(0.92, 0.88, 0.76), float3(0.80, 0.70, 0.52), float3(0.72, 0.70, 0.64), float3(0.87, 0.81, 0.67), float3(0.92, 0.88, 0.76),
    // gold: camel gold, saffron, apricot, walnut, weld yellow, camel gold
    float3(0.79, 0.58, 0.27), float3(0.86, 0.66, 0.22), float3(0.85, 0.55, 0.35), float3(0.52, 0.36, 0.22), float3(0.84, 0.74, 0.34), float3(0.79, 0.58, 0.27),
    // green: green, olive, teal, sage, green, olive
    float3(0.24, 0.40, 0.33), float3(0.40, 0.42, 0.22), float3(0.18, 0.40, 0.42), float3(0.48, 0.55, 0.45), float3(0.24, 0.40, 0.33), float3(0.40, 0.42, 0.22),
    // blue: light blue, sky, slate, turquoise, light blue, sky
    float3(0.42, 0.55, 0.66), float3(0.55, 0.68, 0.78), float3(0.32, 0.40, 0.50), float3(0.30, 0.58, 0.60), float3(0.42, 0.55, 0.66), float3(0.55, 0.68, 0.78),
    // outline: brown-black, indigo-black, dark brown, brown-black, indigo-black, dark brown
    float3(0.11, 0.07, 0.05), float3(0.06, 0.07, 0.12), float3(0.20, 0.12, 0.08), float3(0.11, 0.07, 0.05), float3(0.06, 0.07, 0.12), float3(0.20, 0.12, 0.08),
    // rose: rose, pink, coral, madder pink, rose, pink
    float3(0.78, 0.44, 0.40), float3(0.86, 0.58, 0.58), float3(0.82, 0.40, 0.30), float3(0.70, 0.32, 0.34), float3(0.78, 0.44, 0.40), float3(0.86, 0.58, 0.58)
};
// palette presets (dye index per slot): Tabriz, Kashan, Isfahan, Heriz
static const int RUG_PRESET[4 * RUG_SLOTS] = {
    0, 0, 0, 0, 0, 0, 0, 0,
    2, 1, 1, 1, 2, 1, 1, 1,
    3, 0, 2, 0, 0, 2, 0, 3,
    1, 0, 0, 2, 1, 0, 0, 2
};
float3 rugDye(int slot, int idx) { return RUG_DYES[clamp(slot, 0, RUG_SLOTS - 1) * 6 + ((idx % 6) + 6) % 6]; }

float rugHash(float2 p) { return frac(sin(dot(p, float2(127.1, 311.7))) * 43758.5453); }
// anti-aliased fill of a signed distance (metres) given the pixel footprint
float rugFill(float sd, float aa) { return 1.0 - smoothstep(-aa, aa, sd); }
// a motif with a dark outline: the shape grown by `w` in the outline colour, then the fill
void rugInk(inout float3 col, float sd, float3 c, float3 lineC, float w, float aa)
{
    col = lerp(col, lineC, rugFill(sd - w, aa));
    col = lerp(col, c, rugFill(sd, aa));
}
float2 rugRot(float2 p, float a) { float c = cos(a), s = sin(a); return float2(c * p.x - s * p.y, s * p.x + c * p.y); }
float rugSeg(float2 p, float2 a, float2 b) { float2 pa = p - a, ba = b - a; float h = saturate(dot(pa, ba) / max(dot(ba, ba), 1e-9)); return length(pa - ba * h); }

// ---------------------------------------------------------------------------------------------
// MOTIFS (signed distances in metres; q in the motif's own frame, +y its "up")
// A rosette: an outer ring of petals, an inner ring offset half a petal, a heart.
float rugPetals(float2 q, float r, float n, float rot)
{
    float a = atan2(q.y, q.x + 1e-7) + rot;
    float rr = r * (0.70 + 0.30 * pow(abs(cos(a * n * 0.5)), 0.6));
    return length(q) - rr;
}
// A shah-abbasi palmette: a broad fan of lobes rising from a cup, a pointed tongue through it.
float rugFanSD(float2 q, float s)
{
    float2 u = q / s;
    float2 c = u - float2(0.0, -0.05);
    float r = length(c);
    float a = atan2(c.x, c.y);                              // 0 = straight up
    float lobes = 0.60 * (0.80 + 0.20 * pow(abs(cos(a * 3.5)), 0.5));
    float fan = max(r - lobes, (abs(a) - 1.75) * max(r, 0.05));  // seven lobes, open below
    fan = max(fan, -(u.y + 0.10));                          // the fan sits on the cup
    float cup = length((u - float2(0.0, -0.22)) * float2(1.0, 1.7)) - 0.34;
    float stem = rugSeg(u, float2(0.0, -0.45), float2(0.0, -0.80)) - 0.05;
    return min(min(fan, cup), stem) * s;
}
// its tongue: a pointed flame up the middle of the fan (drawn in a second colour)
float rugTongueSD(float2 q, float s)
{
    float2 u = q / s - float2(0.0, 0.05);
    float w = 0.16 * (1.0 - saturate((u.y + 0.15) / 0.62));
    return max(abs(u.x) - w, abs(u.y - 0.16) - 0.31) * s;
}
// A lancet leaf (a vesica) of length L and width W along +y, from the origin.
float rugLeaf(float2 q, float L, float W)
{
    q.y -= L * 0.5;
    float R = (L * L * 0.25 + W * W * 0.25) / W;            // circle radius through the tips
    float off = R - W * 0.5;
    return max(length(q - float2(off, 0.0)), length(q + float2(off, 0.0))) - R;
}

// ---------------------------------------------------------------------------------------------
// THE ALL-OVER FIELD: the HERATI, one tile mirrored in both axes: a rosette inside a lozenge of
// vine, lancet leaves lying along the lozenge's sides, a small palmette at each of its points,
// and a four-way rosette cluster where tiles meet. Returns the colour over `ground`.
float3 rugFieldTile(float2 f, float3 ground, BRRugDesign R, float aa, float sc)
{
    float2 T = float2(0.21, 0.27) * (R.motif / 0.24) * sc;
    float2 cell = floor(f / T + 0.5);
    float2 u = abs(f - cell * T);                            // fold into one quarter of the tile
    float2 Th = T * 0.5;
    float hs = rugHash(cell + R.seed * 13.0);
    float3 col = ground;
    float3 L = R.outline;
    float lw = max(0.0016, aa * 0.55);
    // THE TRIP: rings of bloom leave the centre of the rug; in each, the flowers swell and turn,
    // the palmettes lift, and a tile's colours trade places on its own phase
    float dc = length(cell * T);
    float wave = sin(R.time * 0.9 - dc * 9.0);
    float bl = 1.0 + 0.22 * R.bloom * wave;
    float spin = R.bloomT * 0.25 + R.bloom * 0.6 * wave;
    float pl = 1.0 + 0.12 * R.bloom * wave;
    float tph = hs * 6.2831853 - dc * 4.0;
    // the lozenge: a fine vine joining the palmette points
    float2 nrm = normalize(float2(1.0 / Th.x, 1.0 / Th.y));
    float loz = abs(dot(u, nrm) - 0.78 * dot(float2(Th.x, 0.0), nrm)) - 0.0022;
    col = lerp(col, R.gold * 0.9, rugFill(loz, aa));
    // lancet leaves on the lozenge's sides, pointing out along it
    float2 mid = float2(Th.x, Th.y) * 0.39;
    float ang = atan2(Th.x, -Th.y);
    float2 lq = rugRot(u - mid, -ang);
    rugInk(col, rugLeaf(lq + float2(0.0, Th.y * 0.20), Th.y * 0.42, Th.x * 0.15), R.green, L, lw, aa);
    // small palmettes at the lozenge's points, pointing outward along the axes
    float2 px1 = rugRot(u - float2(Th.x * 0.78, 0.0), 1.5708);
    rugInk(col, rugFanSD(px1, Th.x * 0.36 * pl), rugTrade(R.rose, R.blue, R, tph), L, lw, aa);
    rugInk(col, rugTongueSD(px1, Th.x * 0.36 * pl), R.gold, L, lw * 0.7, aa);
    float2 py1 = u - float2(0.0, Th.y * 0.78);
    rugInk(col, rugFanSD(py1, Th.x * 0.36 * pl), (hs > 0.5) ? rugTrade(R.blue, R.gold, R, tph + 2.1) : rugTrade(R.gold, R.rose, R, tph + 2.1), L, lw, aa);
    rugInk(col, rugTongueSD(py1, Th.x * 0.36 * pl), R.field * 1.25, L, lw * 0.7, aa);
    // the rosette at the heart
    float3 rc = (hs < 0.5) ? rugTrade(R.gold, R.rose, R, tph + 4.2) : rugTrade(R.rose, R.blue, R, tph + 4.2);
    rugInk(col, rugPetals(u, Th.x * 0.30 * bl, 8.0, 0.3927 + spin), rc, L, lw, aa);
    rugInk(col, rugPetals(u, Th.x * 0.15 * bl, 6.0, -spin * 1.5), R.border, L, lw * 0.8, aa);
    col = lerp(col, R.gold, rugFill(length(u) - Th.x * 0.045 * bl, aa));
    // the cluster where four tiles meet
    float2 cq = u - Th;
    rugInk(col, rugPetals(cq, Th.x * 0.24 * bl, 8.0, -spin), rugTrade(R.blue, R.gold, R, tph + 1.0), L, lw, aa);
    col = lerp(col, R.ivory, rugFill(length(cq) - Th.x * 0.07, aa));
    // the field's ornament is drawn a step quieter than the medallion's, so the medallion reads first
    return lerp(ground, col, 0.72);
}

// ---------------------------------------------------------------------------------------------
// THE MEDALLION (Tabriz): a scalloped superellipse with concentric grounds.
float rugMedSD(float2 f, float2 M, float lobes)
{
    float2 q = f / M;
    float a = atan2(q.x, q.y);
    float base = pow(pow(abs(q.x), 1.35) + pow(abs(q.y), 1.35), 1.0 / 1.35);
    float sc = 0.030 * cos(a * lobes + g_rugScallop);       // soft scallops, not a saw
    return (base - 1.0 + sc) * min(M.x, M.y);
}

float3 rugMedallion(float2 f, float3 col, float2 fh, BRRugDesign R, float aa)
{
    float3 L = R.outline;
    float lw = max(0.0022, aa * 0.6);
    // THE TRIP: the medallion breathes, its ring of palmettes orbits it, its heart's rosettes turn
    // against each other (and its scallops ripple round it: g_rugScallop)
    float ms = min(fh.x, fh.y) * R.medallion * (1.0 + 0.03 * R.bloom * sin(R.time * 0.5));
    float2 M = float2(ms, ms * 1.42);
    float orbit = R.bloomT * 0.06;
    float turn = R.bloomT * 0.15;
    // pendants on the long axis: a lobed cartouche and a palmette finial beyond it
    float2 pq = float2(f.x, abs(f.y) - M.y * 1.12);
    float pend = rugMedSD(pq, float2(ms * 0.26, ms * 0.17), 10.0);
    rugInk(col, pend, R.ivory, L, lw, aa);
    rugInk(col, rugPetals(pq, ms * 0.10, 8.0, 0.0), R.border, L, lw, aa);
    float2 fq = float2(f.x, abs(f.y) - M.y * 1.36);
    rugInk(col, rugFanSD(fq, ms * 0.16), R.gold, L, lw, aa);
    // the medallion's grounds, outer to inner
    float m0 = rugMedSD(f, M, 16.0);
    rugInk(col, m0, R.ivory, L, lw * 1.4, aa);
    // a ring of small palmettes in the ivory band, pointing out
    float a = atan2(f.x, f.y);
    float k = 12.0;
    float aSec = (floor((a + orbit) / 6.2831853 * k + 0.5) / k) * 6.2831853 - orbit;
    float2 rq = rugRot(f, aSec);                            // into the sector's frame: +y outward
    float ringR = ms * 1.05;
    float2 pp = rq - float2(0.0, ringR * lerp(1.0, 1.42, saturate(abs(cos(aSec)))) * 0.80);
    float band = -rugMedSD(f, M * 0.80, 16.0);              // inside m0, outside the next ground
    // a scroll running round the band, and the palmettes on it (clipped to the band)
    float scrollB = abs(rugMedSD(f, M * 0.89, 16.0)) - 0.0028;
    col = lerp(col, R.gold * 0.9, rugFill(max(scrollB, band), aa) * rugFill(m0, aa));
    float palm = max(rugFanSD(pp, ms * 0.13), band);
    rugInk(col, palm, rugTrade(R.rose, R.gold, R, aSec * 3.0), L, lw, aa);
    rugInk(col, max(rugTongueSD(pp, ms * 0.13), band), R.border, L, lw * 0.7, aa);
    float m1 = rugMedSD(f, M * 0.78, 16.0);
    rugInk(col, m1, R.border, L, lw * 1.2, aa);
    // in the indigo: a gold scroll ring
    float scroll = abs(rugMedSD(f, M * 0.62, 16.0)) - 0.0035;
    col = lerp(col, R.gold, rugFill(scroll, aa));
    float m2 = rugMedSD(f, M * 0.48, 12.0);
    rugInk(col, m2, R.field * 1.05, L, lw, aa);
    // the heart: a double rosette
    rugInk(col, rugPetals(f, ms * 0.24, 8.0, 0.3927 + turn), R.ivory, L, lw, aa);
    rugInk(col, rugPetals(f, ms * 0.14, 8.0, -turn * 1.6), rugTrade(R.blue, R.rose, R, 0.0), L, lw, aa);
    rugInk(col, rugPetals(f, ms * 0.07, 6.0, turn * 2.4), R.gold, L, lw * 0.8, aa);
    // the corner spandrels: quarter medallions in indigo with a gold rim and a palmette
    float2 cq = fh - abs(f);
    float2 cM = float2(ms * 0.92, ms * 1.25);
    float sp = rugMedSD(cq, cM, 16.0);
    rugInk(col, sp, R.border, L, lw * 1.4, aa);
    col = lerp(col, R.gold, rugFill(abs(rugMedSD(cq, cM * 0.80, 16.0)) - 0.0035, aa) * rugFill(sp, aa));
    float2 cp = rugRot(cq - cM * float2(0.22, 0.22), 0.7854);
    rugInk(col, rugFanSD(cp, ms * 0.17), R.rose, L, lw, aa);
    return col;
}

// THE HERIZ MEDALLION: angular, stepped, drawn on a coarse grid.
float3 rugHeriz(float2 f, float3 col, float2 fh, BRRugDesign R, float aa)
{
    float3 L = R.outline;
    float g = 0.035;                                         // the cartoon's grid
    float2 s = (floor(f / g) + 0.5) * g;                     // stepped edges
    float ms = min(fh.x, fh.y) * R.medallion;
    float rh = abs(s.x) / ms + abs(s.y) / (ms * 1.5);        // a rhombus...
    float hook = step(0.82, rh) * step(rh, 1.0) * step(0.5, frac(s.x / (g * 2.0) + s.y / (g * 3.0)));
    if (rh < 1.0)
    {
        col = (rh > 0.86) ? L : R.border;
        if (rh < 0.70) col = R.ivory;
        if (rh < 0.56) col = R.field * 1.05;
        if (rh < 0.30) col = R.border;
        if (rh < 0.16) col = R.gold;
        col = lerp(col, R.gold, hook);
    }
    // stepped spandrels
    float2 c = (fh - abs(s)) / (ms * float2(0.8, 1.1));
    float cr = c.x + c.y;
    if (cr < 1.0) col = (cr > 0.88) ? L : ((cr > 0.70) ? R.gold : R.border);
    // the field: scattered small geometric florets on the knot grid
    float2 fc = floor(f / (g * 4.0));
    float2 fq = f - (fc + 0.5) * g * 4.0;
    float fl = abs(fq.x) + abs(fq.y);
    if (rh >= 1.0 && cr >= 1.0 && fl < g * 1.2 && rugHash(fc + R.seed) > 0.45) col = (fl < g * 0.6) ? R.ivory : R.blue;
    return col;
}

#ifdef RUG_REC
// The design BR_Rug published, or the default while it is unlinked.
BRRugDesign rugFromRecs()
{
    BRRugDesign d = rugDefault();
    BRRec h = RUG_REC(0);
    if (abs(h.head.x - ROLE_RUG) > 0.5) return d;
    d.style = clamp((int)round(h.head.y), 0, 2); d.seed = h.head.z;
    d.borderW = clamp(h.dims.x, 0.04, 0.25); d.medallion = clamp(h.dims.y, 0.2, 0.8);
    d.motif = clamp(h.dims.z, 0.12, 0.45); d.abrash = saturate(h.dims.w);
    d.wear = saturate(h.look.x); d.knot = clamp(h.look.y, 0.002, 0.008);
    d.field = RUG_REC(1).dims.rgb; d.border = RUG_REC(2).dims.rgb; d.ivory = RUG_REC(3).dims.rgb;
    d.gold = RUG_REC(4).dims.rgb; d.green = RUG_REC(5).dims.rgb; d.blue = RUG_REC(6).dims.rgb;
    d.outline = RUG_REC(7).dims.rgb; d.rose = h.meta.rgb;
    return d;
}
#endif

// ---------------------------------------------------------------------------------------------
// Returns linear albedo; `pile` 0..1 (worn to full) for the shading; `p` in metres from the rug
// centre with x along the rug's width and y along its length; `halfSz` the half size; `aa` the
// footprint in metres (patterns fade by it, so a distant rug is not a moire).
float3 rugDesign(float2 p, float2 halfSz, BRRugDesign R, float aa, out float pile)
{
    // orient so y runs along the LONG axis
    bool swap = halfSz.x > halfSz.y;
    float2 q = swap ? p.yx : p;
    float2 h = swap ? halfSz.yx : halfSz;
    float shortH = h.x;
    // knot quantisation (each knot one colour) when knots are resolvable
    float2 kq = q;
    if (aa < R.knot * 0.8) kq = (floor(q / R.knot) + 0.5) * R.knot;
    aa = max(aa, R.knot * 0.5);
    float3 L = R.outline;
    float lw = max(0.0022, aa * 0.6);

    // distances in from the edges
    float dX = h.x - abs(kq.x), dY = h.y - abs(kq.y);
    float dEdge = min(dX, dY);
    bool sideLong = dX < dY;                                 // on a long side's border
    float along = sideLong ? kq.y : kq.x;
    float sel = 0.010;
    float og = shortH * 0.045, mb = shortH * 2.0 * R.borderW, ig = shortH * 0.032;
    float b0 = sel, b1 = b0 + og, b2 = b1 + mb, b3 = b2 + ig;
    // THE TRIP: the border travels round the rug (one way round on every side), the guards run
    // against it, the abrash bands drift down its length, the medallion's scallops ripple
    float circ = sideLong ? ((kq.x >= 0.0) ? 1.0 : -1.0) : ((kq.y >= 0.0) ? -1.0 : 1.0);
    float run = R.flowT;
    g_rugScallop = R.bloomT * 0.4;

    float3 col;
    // abrash: bands of a slightly different dye lot across the weave (along the long axis)
    float yA = kq.y + h.y + run * 0.012;
    float bandW = 0.11 + 0.17 * rugHash(float2(floor(yA / 0.21), R.seed));
    float band = floor(yA / bandW);
    float ab = (rugHash(float2(band, R.seed * 7.0)) - 0.5) * R.abrash * 0.35;

    if (dEdge < b0)
    {
        col = L * 1.6;                                       // the overcast selvedge
    }
    else if (dEdge < b1)
    {
        // outer guard: a "running dog" scroll, ivory on red, between two fine indigo lines
        float u = (dEdge - b0) / og;                         // 0 outer .. 1 inner
        float per = og * 1.6;
        float t = frac((along + run * 0.035 * circ) / per);
        float wave = abs((u - 0.5) - 0.32 * sin(t * 6.2831853)) - 0.10;
        float hookC = abs(length(float2((t - 0.75) * per, (u - 0.5 - 0.22) * og)) - og * 0.16) - og * 0.05;
        col = R.field * 0.9;
        col = lerp(col, R.ivory, rugFill(min(wave * og, hookC), aa));
        col = lerp(col, R.border, rugFill(min(u, 1.0 - u) * og - og * 0.09, aa));
    }
    else if (dEdge < b2)
    {
        // MAIN BORDER on indigo: a scrolling vine with palmettes and rosettes, leaves, tendrils
        along -= run * 0.05 * circ;                          // (the trip: it travels round)
        float across = (dEdge - b1) - mb * 0.5;              // metres across, 0 at the centre line
        float rep = mb * 2.0;
        float cellI = floor(along / rep);
        float tt = (frac(along / rep) - 0.5) * rep;
        float phase = along / rep * 6.2831853;
        float vineY = sin(phase) * mb * 0.20;
        float slope = cos(phase) * mb * 0.20 * 6.2831853 / rep;
        float vine = abs(across - vineY) / sqrt(1.0 + slope * slope) - mb * 0.022;
        col = R.border;
        // tendrils curling off the vine between the motifs
        float2 tq = float2(tt - rep * 0.25, across + mb * 0.10 * sign(sin(phase + 1.0)));
        float tend = max(abs(length(tq) - mb * 0.07) - mb * 0.010, -tq.y * sign(sin(phase + 1.0)));
        col = lerp(col, R.green, rugFill(min(vine, tend), aa));
        // lancet leaves along the vine
        float2 lq = rugRot(float2(tt + rep * 0.30, across - vineY), 0.9);
        rugInk(col, rugLeaf(lq, mb * 0.30, mb * 0.11), R.green, L, lw, aa);
        float2 lq2 = rugRot(float2(tt - rep * 0.30, across - vineY), -2.2);
        rugInk(col, rugLeaf(lq2, mb * 0.26, mb * 0.10), R.blue, L, lw, aa);
        // the motif in this cell, sitting on the vine: palmettes (upright / inverted) and rosettes
        bool palm = fmod(abs(cellI), 2.0) < 0.5;
        float2 mq = float2(tt, across - vineY * 0.3);
        if (palm)
        {
            float flip = (fmod(abs(cellI), 4.0) < 2.0) ? 1.0 : -1.0;
            float2 pq = float2(mq.x, mq.y * flip);
            rugInk(col, rugFanSD(pq, mb * 0.36), R.field * 1.05, L, lw, aa);
            rugInk(col, rugFanSD(pq + float2(0.0, mb * 0.02), mb * 0.22), R.gold, L, lw, aa);
            rugInk(col, rugTongueSD(pq, mb * 0.36), R.ivory, L, lw * 0.8, aa);
        }
        else
        {
            float rs = R.bloomT * 0.3;                       // (the trip: the rosettes turn as they travel)
            rugInk(col, rugPetals(mq, mb * 0.24, 8.0, 0.3927 + rs), rugTrade(R.gold, R.rose, R, cellI * 1.7), L, lw, aa);
            rugInk(col, rugPetals(mq, mb * 0.15, 8.0, -rs), rugTrade(R.rose, R.blue, R, cellI * 1.7 + 2.0), L, lw, aa);
            rugInk(col, rugPetals(mq, mb * 0.07, 6.0, rs * 2.0), R.ivory, L, lw * 0.8, aa);
        }
        // the corners: a large rosette turns each corner (and turns, in the trip)
        float2 cq = float2(dX, dY) - (b1 + mb * 0.5);
        float cro = rugPetals(cq, mb * 0.34, 12.0, R.bloomT * 0.2);
        if (max(dX, dY) < b2 + mb * 0.6)
        {
            rugInk(col, cro, R.gold, L, lw * 1.2, aa);
            rugInk(col, rugPetals(cq, mb * 0.24, 8.0, 0.3927 - R.bloomT * 0.3), R.field, L, lw, aa);
            col = lerp(col, R.gold, rugFill(length(cq) - mb * 0.08, aa));
        }
        // fine ivory lines where the border meets its guards
        col = lerp(col, R.ivory, rugFill(abs(abs(across) - mb * 0.47) - mb * 0.012, aa));
    }
    else if (dEdge < b3)
    {
        // inner guard: a small meander of buds, gold on red (in the trip, running against the border)
        along += run * 0.03 * circ;
        float u = (dEdge - b2) / ig - 0.5;
        float per = ig * 1.8;
        float t = (frac(along / per) - 0.5) * per;
        float meander = abs(u * ig - sin(along / per * 6.2831853) * ig * 0.22) - ig * 0.06;
        float bud = length(float2(t, u * ig - ig * 0.18 * sign(sin(along / per * 3.14159)))) - ig * 0.17;
        col = R.field * 0.82;
        col = lerp(col, R.gold, rugFill(min(meander, bud), aa));
    }
    else
    {
        // FIELD
        float2 fh = h - b3;
        float2 f = kq;
        float3 ground = R.field * (1.0 + ab);
        if (R.style == 2)
        {
            col = rugHeriz(f, ground, fh, R, aa);
        }
        else
        {
            col = rugFieldTile(f, ground, R, aa, (R.style == 1) ? 0.8 : 1.0);
            if (R.style == 0) col = rugMedallion(f, col, fh, R, aa);
        }
        // a fine double line where the field meets the inner guard
        col = lerp(col, R.ivory, rugFill(abs(dEdge - b3 - 0.006) - 0.0016, aa));
    }

    // yarn-to-yarn variation, and wear: thinner pile in the traffic zone shows the warp's ivory
    float2 kn = floor(kq / R.knot);
    col *= 0.93 + 0.14 * rugHash(kn + R.seed);
    float2 uw = q / max(h, 0.1);
    float traffic = exp(-dot(uw * float2(1.4, 0.9), uw * float2(1.4, 0.9)) * 1.6);
    float wn = rugHash(floor(kq / 0.02) + 3.1);
    float worn = saturate(traffic * R.wear * (0.6 + 0.6 * wn));
    pile = 1.0 - worn * 0.7;
    col = lerp(col, lerp(col, R.ivory * 0.75, 0.45), worn * 0.55);
    return col;
}

#endif
