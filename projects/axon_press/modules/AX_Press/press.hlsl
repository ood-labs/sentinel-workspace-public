// AX_Press / press.hlsl — the axonometric octave renderer.
//
// Draws AX_Plan's record set at `levels` scales at once about the focus and composites them far
// to near. There is no camera and no perspective: the reference's identity is that parallel
// edges stay parallel, and flying a perspective camera through it destroys exactly that. The
// flight is a uniform scale of the drawing instead.
//
// WHY THE LAYER INDEXING LOOKS THE WAY IT DOES. A layer is identified by its BIRTH index
// n = floor(travel) - j, not by its screen slot j. Indexing content by the screen slot makes
// every layer change its paper simultaneously each time travel crosses an integer, which is a
// hard pop across the whole frame. Indexing by birth means a layer keeps its identity for its
// whole life, layers simply renumber as one dies at the near end and one is born at the deep
// end, and the frame at travel = t and travel = t + period is bit-identical. Everything that
// varies per octave routes through axSlotMod(n, period) — an INTEGER reduced mod an integer.
// Nothing here may hash a float derived from travel; that is what strobes at the wrap.
//
// Layer SCALE uses frac(travel) for the same reason. Together the two give a genuinely endless
// fall with no seam, no teleport and no repeat inside the period.
#include "../_shared/plates.hlsli"

StructuredBuffer<AxRec> Plate : register(t0);
RWTexture2D<float4> OutputUAV : register(u0);

// extra octaves drawn beyond scale 1 so the nearest layer overruns the frame instead of
// popping in at the corners
#define AX_OUTER 2

struct LayerHit
{
    float3 col;
    float  cov;
};

// Facet material selection. `facet_mode` is the exploration axis: what decides which plate a
// given face wears. Per Facet is the reference's own answer — every facet of every box is a
// different scrap — and the others are the disciplined alternatives.
void facetPlate(AxRec r, uint idx, int face, int slot, float2 t01, out int mat, out int cidx)
{
    float hs = r.seed;
    if (facet_mode == 1)            // Per Volume — the whole box is one scrap
    {
        mat = (int)r.mat; cidx = (int)r.col;
    }
    else if (facet_mode == 2)       // Per Axis — tops one stock, rights another, lefts a third
    {
        mat  = (int)fmod(r.mat + (float)face * 2.0, (float)AX_MATS);
        cidx = (int)fmod(r.col + (float)face * 3.0, (float)AX_COLS);
    }
    else if (facet_mode == 3)       // Split — every facet cut on its diagonal into two scraps
    {
        float half_ = step(1.0, t01.x + t01.y);
        mat  = (int)fmod(r.mat + half_ * 3.0 + (float)face, (float)AX_MATS);
        cidx = (int)fmod(r.col + half_ * 5.0 + (float)face * 2.0, (float)AX_COLS);
    }
    else                            // Per Facet
    {
        // 0.68 rather than an even split: at a low figure every box carries three unrelated
        // scraps and the whole frame becomes uniformly busy, which is the opposite of the
        // reference — that collage has large calm fields with loud facets cut into them.
        float hm = ax_h2(float2((float)idx * 7.7 + (float)face * 3.1, hs));
        mat  = (hm < 0.68) ? (int)r.mat
                           : (int)fmod(r.mat + floor(hm * 7.0) + 1.0, (float)AX_MATS);
        cidx = (int)fmod(r.col + floor(ax_h2(float2((float)face * 5.3, hs)) * 4.0), (float)AX_COLS);
    }
    // The per-octave rotation. Integer slot in, integer indices out — the whole reason the loop
    // can carry variation at all. The material steps by ONE, not several: AX_M_* is ordered
    // printed / patterned / flat, so a step of one keeps a paper record papery across the
    // octaves, while a larger step throws the balance the `paper` control was set to.
    mat  = (int)fmod((float)mat + (float)slot, (float)AX_MATS);
    cidx = (int)fmod((float)cidx + (float)slot * 5.0, (float)AX_COLS);
}

// One octave. `q` is the plate point in cell = 1 units; `lod` is lattice units per pixel at
// this scale, which is what keeps the printed detail resolvable however deep the fall goes.
LayerHit drawLayer(float2 q, float lod, int slot, float2 A, float2 B, float2 C, float3 D)
{
    LayerHit outh;
    outh.col = AX_FIELD; outh.cov = 0.0;

    float bestDepth = -1e9;
    int   bestIdx = -1, bestFace = 0, bestSub = 0;
    float2 bestFl = float2(0.0, 0.0), bestExt = float2(1.0, 1.0);

    for (uint i = 0u; i < AX_RECORDS - 1u; i++)
    {
        AxRec r = Plate[i];
        if (r.active < 0.5 || r.role == ROLE_TRC) continue;

        float2 bc; float br;
        axBound(r.pos, r.ext, A, B, C, bc, br);
        if (dot(q - bc, q - bc) > br * br) continue;          // bounding-circle early out

        int face; float2 fl; float dep;
        int sub = 0;
        bool hit = axBoxHit(r.pos, r.ext, q, A, B, C, D, face, fl, dep);

        // STEP: a second, smaller box set on the first. Tested separately and resolved by the
        // same painter key, so the two read as one stepped mass rather than as two objects.
        if (r.role == ROLE_VOL && (int)r.kind == AX_VK_STEP)
        {
            float3 sb = r.pos + float3(round(r.ext.x * 0.26), round(r.ext.y * 0.26), r.ext.z);
            float3 se = max(round(r.ext * float3(0.52, 0.52, 0.62)), float3(1.0, 1.0, 1.0));
            int f2_; float2 l2; float d2;
            if (axBoxHit(sb, se, q, A, B, C, D, f2_, l2, d2) && d2 > dep)
            {
                hit = true; face = f2_; fl = l2; dep = d2; sub = 1;
                if (dep <= bestDepth) continue;
                bestExt = (f2_ == AX_FACE_TOP) ? se.xy : ((f2_ == AX_FACE_RIGHT) ? se.yz : se.xz);
                bestDepth = dep; bestIdx = (int)i; bestFace = face; bestFl = fl; bestSub = 1;
                continue;
            }
        }
        // Volumes ATTACH by sharing a face plane, so coplanar facets are the normal case here,
        // not an edge case — and two exactly-equal depths let float noise decide the winner
        // differently from frame to frame, which is the classic z-fight shimmer along every
        // shared edge. A tiny bias by record index makes the tie deterministic. Lattice
        // coordinates are integers, so real depth differences are of order 1 and this can never
        // reorder anything that genuinely differs.
        dep += (float)i * 2e-5;
        if (!hit || dep <= bestDepth) continue;

        float2 ee = (face == AX_FACE_TOP)   ? r.ext.xy
                  : (face == AX_FACE_RIGHT) ? r.ext.yz : r.ext.xz;
        float2 t01 = fl / max(ee, 1e-4);

        // WEDGE — half a real facet, never a floating triangle
        if (r.role == ROLE_WDG)
        {
            int cnr = (int)r.kind;
            float sv = (cnr == 0) ? (t01.x + t01.y) : (cnr == 1) ? (2.0 - t01.x - t01.y)
                     : (cnr == 2) ? (1.0 + t01.x - t01.y) : (1.0 - t01.x + t01.y);
            if (sv > 1.0) continue;
        }
        // FRAME — edges only. This is what stops the near octaves walling the frame off and
        // lets the fall see all the way down the funnel.
        if (r.role == ROLE_VOL && (int)r.kind == AX_VK_FRAME)
        {
            float m = min(min(t01.x, 1.0 - t01.x), min(t01.y, 1.0 - t01.y));
            if (m > 0.15) continue;
        }
        // OPEN — a recessed inner floor under the top rim
        if (r.role == ROLE_VOL && (int)r.kind == AX_VK_OPEN && face == AX_FACE_TOP)
        {
            float m = min(min(t01.x, 1.0 - t01.x), min(t01.y, 1.0 - t01.y));
            if (m > 0.13)
            {
                float3 ib = r.pos + float3(r.ext.x * 0.13, r.ext.y * 0.13, r.ext.z * 0.86);
                float3 ie = float3(r.ext.x * 0.74, r.ext.y * 0.74, 0.0);
                int f3; float2 l3; float d3;
                if (axBoxHit(ib, ie, q, A, B, C, D, f3, l3, d3))
                {
                    face = f3; fl = l3; dep = d3; sub = 2;
                    ee = ie.xy;
                }
            }
        }

        bestDepth = dep; bestIdx = (int)i; bestFace = face; bestFl = fl;
        bestExt = ee; bestSub = sub;
    }

    if (bestIdx >= 0)
    {
        AxRec r = Plate[(uint)bestIdx];
        float2 t01 = bestFl / max(bestExt, 1e-4);
        int mat, cidx;
        facetPlate(r, (uint)bestIdx, bestFace, slot, t01, mat, cidx);

        float3 own = axPal(cidx);
        float3 c = axPlate(mat, bestFl, t01, r.seed + (float)slot * 13.0, own, lod, accent);

        // Face value. The reference is FLAT — a box reads as a box because its three faces carry
        // different scraps, not because they are lit. So this is a small value separation on top
        // of the material difference, not a shading model.
        float fv = (bestFace == AX_FACE_TOP) ? 1.0 : ((bestFace == AX_FACE_RIGHT) ? 0.88 : 0.76);
        c *= lerp(1.0, fv, saturate(shade));
        if (bestSub == 2) c *= 0.62;                       // the recess inside an open box

        c = axRuns(c, t01, r.seed + r.phase * 17.0, drip);

        // how many pixels the facet spans — the number every anti-aliasing decision below needs
        float facetPx = min(bestExt.x, bestExt.y) / max(lod, 1e-9);

        // Facet ink. Drawn in PIXELS, so the line weight is the same at every octave — which is
        // how ink on a printed sheet behaves, and it stays periodic because a constant is. On a
        // facet only a few pixels across the ink band would swallow the whole facet and flip
        // on and off as it grows, so it is faded out before it can.
        if (ink_mode != 3)
        {
            float m = min(min(t01.x, 1.0 - t01.x), min(t01.y, 1.0 - t01.y));
            float dpx = m * min(bestExt.x, bestExt.y) / max(lod, 1e-9);
            float w = (ink_mode == 1) ? ink_px * 2.4 : ((ink_mode == 2) ? ink_px * 1.6 : ink_px);
            float e = 1.0 - smoothstep(w, w + 1.0, dpx);
            float3 ic = (ink_mode == 2) ? float3(0.96, 0.95, 0.93) : float3(0.04, 0.04, 0.05);
            c = lerp(c, ic, e * 0.9 * smoothstep(3.0, 9.0, facetPx));
        }

        outh.col = c;
        // SUB-PIXEL FADE. Deep in the funnel a layer is made of facets around a pixel across,
        // and drawn at full opacity they scintillate as the fall resizes them — the deep centre
        // boils. Fading a facet out as it approaches a pixel hands those pixels to the octave
        // behind instead. It depends only on the record's own extent and the octave scale, both
        // constant per octave, so the loop stays bit-exact.
        outh.cov = smoothstep(1.1, 3.4, facetPx);
    }

    // --- traces, over the solids of this octave. Constant pixel weight, like a drawn line.
    for (uint t = 0u; t < AX_TRCS; t++)
    {
        AxRec r = Plate[AX_TRC_0 + t];
        if (r.active < 0.5) continue;
        float3 p0 = r.pos, p1 = r.pos + r.ext;
        // WEIGHT IN LATTICE UNITS, NOT PIXELS. A constant pixel weight makes every octave's
        // traces the same wire thickness, so the near octaves — where a span is many screen
        // widths long — lay a spiderweb over the whole composition. Scaling with the octave
        // turns the near ones into the reference's broad ribbons and lets the deep ones fall
        // below a pixel and disappear, which is what self-similarity requires anyway.
        float w = trace_w * 0.5;
        float d = 1e9;
        int k = (int)r.kind;
        if (k == AX_TK_ELBOW)
        {
            // an axis-following route: the reference's long lines turn corners rather than
            // cutting straight across, which is what makes them read as routing
            float3 m1 = float3(p1.x, p0.y, p0.z);
            float3 m2 = float3(p1.x, p1.y, p0.z);
            d = min(d, axSegD(q, axProj(p0, A, B, C), axProj(m1, A, B, C)));
            d = min(d, axSegD(q, axProj(m1, A, B, C), axProj(m2, A, B, C)));
            d = min(d, axSegD(q, axProj(m2, A, B, C), axProj(p1, A, B, C)));
        }
        else
        {
            float2 s0 = axProj(p0, A, B, C), s1 = axProj(p1, A, B, C);
            d = axSegD(q, s0, s1);
            if (k == AX_TK_DASH)
            {
                float2 dir = normalize(s1 - s0 + 1e-6);
                float u = dot(q - s0, dir);
                if (frac(u / max(trace_w * 7.0, 1e-5)) > 0.55) d = 1e9;
            }
            else if (k == AX_TK_TICK)
            {
                float2 dir = normalize(s1 - s0 + 1e-6);
                float u = dot(q - s0, dir);
                float len = length(s1 - s0);
                if (frac(u / max(len / 9.0, 1e-5)) < 0.10 && u > 0.0 && u < len)
                    d = min(d, abs(dot(q - s0, float2(-dir.y, dir.x))) * 0.22);
            }
        }
        // Analytic thin-line coverage. A line narrower than a pixel drawn at full opacity is the
        // other half of the flicker: it snaps on and off as it crosses pixel centres. Instead
        // the drawn width is floored at about two thirds of a pixel and the OPACITY is scaled
        // down by how much thinner than that the true line is, which is what a correctly
        // filtered thin line does.
        float aaw = max(lod, 1e-9);
        float hw = max(w, aaw * 0.35);
        float hit = (1.0 - smoothstep(hw - aaw * 0.5, hw + aaw * 0.5, d))
                  * saturate(w / (aaw * 0.35));
        if (hit > 0.001)
        {
            outh.col = lerp(outh.col, AX_INK[(int)fmod(r.col + (float)slot, (float)AX_TRACE_INKS)], hit);
            outh.cov = max(outh.cov, hit);
        }
    }
    return outh;
}

float3 shadeAt(float2 P, float pxScreen)
{
    AxRec hdr = Plate[AX_HEADER];
    float cell   = max(hdr.ext.z, 1e-5);
    float travel = hdr.phase;
    float cRmin  = max(hdr.rmin, 1e-3);
    float cRmax  = max(hdr.rmax, cRmin * 1.01);
    float2 focusL = float2(hdr.pad0, hdr.pad1);

    // projection, octave ratio and loop period all come off the header. AX_Plan owns them.
    float2 A, B, C; float3 D;
    axBasis((int)hdr.kind, A, B, C, D);
    float2 f2 = axProj(float3(focusL, 0.0), A, B, C);
    float ratio = max(hdr.mat, 1.05);
    int   per   = max((int)hdr.col, 1);

    int   L  = clamp((int)levels, 3, 18);
    float ft = frac(travel);
    int   it = (int)floor(travel);
    float d  = length(P);

    float3 col = AX_FIELD;
    for (int j = 0; j < L; j++)
    {
        float s = pow(ratio, ft + (float)j - (float)(L - 1 - AX_OUTER));
        float rIn  = cRmin * cell * s;
        float rOut = cRmax * cell * s;
        if (d < rIn * 0.985 || d > rOut * 1.015) continue;      // whole-octave annulus reject

        // Birth index, not screen slot. See the header comment — this is the difference between
        // a seamless fall and the entire frame changing paper once per octave.
        int slot = axSlotMod(it - j, per);

        // Mirroring odd slots is the one per-octave geometry change that costs the loop nothing:
        // it preserves every radius exactly and maps the lattice onto itself, so the ladder, the
        // aperture and the fit all stay true while the composition visibly differs octave to
        // octave.
        float2 Pm = ((slot & 1) != 0) ? float2(-P.x, P.y) : P;
        float2 q = f2 + Pm / (cell * s);
        float lod = pxScreen / (cell * s);

        LayerHit h = drawLayer(q, lod, slot, A, B, C, D);
        if (h.cov <= 0.001) continue;

        // Fade and haze are functions of the layer's SCALE alone, never of travel, so they
        // repeat exactly with the loop. The deep end dissolves into the field instead of
        // stippling itself to death at sub-pixel size.
        float sizePx = rOut / max(pxScreen, 1e-9);
        float a  = smoothstep(1.5, 26.0, sizePx);
        float hz = saturate(1.0 - smoothstep(0.02, 0.55, rOut)) * saturate(haze);
        float3 lc = lerp(h.col, AX_FIELD, hz);
        col = lerp(col, lc, h.cov * a);
    }
    return col;
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    uint W, H;
    OutputUAV.GetDimensions(W, H);
    if (pixel.x >= W || pixel.y >= H) return;

    float aspect = (float)W / max((float)H, 1.0);
    float zoom = max(frame_zoom, 1e-3);
    // one pixel in P units, after the frame zoom. Everything downstream measures detail in
    // pixels through this, which is what makes the printed stock scale-adaptive.
    float pxScreen = (2.0 / (float)H) / zoom * max(lod_scale, 0.1);

    int n = clamp((int)aa_samples, 1, 3);
    float3 acc = float3(0.0, 0.0, 0.0);
    for (int sy = 0; sy < n; sy++)
    {
        for (int sx = 0; sx < n; sx++)
        {
            float2 o = (float2(sx, sy) + 0.5) / (float)n;
            float2 uv = ((float2)pixel + o) / float2(W, H);
            float2 P = (uv - 0.5) * float2(aspect * 2.0, -2.0);
            P = (P - float2(frame_x, frame_y)) / zoom;
            acc += shadeAt(P, pxScreen);
        }
    }
    float3 col = acc / (float)(n * n);
    col *= max(exposure, 0.0);
    OutputUAV[pixel] = float4(col, 1.0);
}
