// PR_Plan / canvas.hlsl — the schematic. This is the diagnostic surface for the whole
// system, not decoration: it is the only place you can see what the authority actually
// decided before the marcher spends anything on it.
//
// It draws the plan through pr_unplace(), the exact inverse of the projection the renderer
// marches with, so schematic and render agree by construction. Three panes:
//   * front elevation — every record's real projected footprint, coloured by role,
//     brightness by depth;
//   * top-down XZ inset — proves depth ordering, which the elevation cannot show;
//   * role tallies — one tick per ACTIVE record. This is how a dropped emit becomes
//     visible instead of silent.

#include "../_shared/relic.hlsli"

StructuredBuffer<CastRec> Cast : register(t0);
RWTexture2D<float4> OutputUAV : register(u0);

// q-space: world normalised by frame height, so x and y carry the same units and a stroke
// is the same weight in both axes.
float2 toQ(float3 world)
{
    float2 im = pr_unplace(world);
    return float2(im.x * PR_AR, im.y);
}
float qHalf(float w, float z) { return w / max(pr_frame_h(z), 1e-4); }

float dSeg(float2 p, float2 a, float2 b)
{
    float2 pa = p - a, ba = b - a;
    float h = saturate(dot(pa, ba) / max(dot(ba, ba), 1e-9));
    return length(pa - ba * h);
}
float dRect(float2 p, float2 c, float2 h)
{
    float2 d = abs(p - c) - h;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

float3 roleColor(float role)
{
    if (role == ROLE_TORUS)  return float3(1.00, 0.60, 0.24);
    if (role == ROLE_GLYPH)  return float3(0.34, 0.84, 1.00);
    if (role == ROLE_PLATE)  return float3(0.42, 0.48, 0.62);
    if (role == ROLE_GEM)    return float3(0.94, 0.95, 1.00);
    if (role == ROLE_SPHERE) return float3(0.68, 0.80, 0.96);
    if (role == ROLE_RING)   return float3(1.00, 0.98, 0.82);
    if (role == ROLE_FILM)   return float3(1.00, 0.38, 0.88);
    if (role == ROLE_POST)   return float3(0.42, 0.92, 0.52);
    return float3(0.55, 0.55, 0.55);
}

// Nearer records read brighter, so the elevation carries depth without the inset.
float depthKey(float z) { return 0.42 + 0.58 * saturate((z + 2.0) / 3.6); }

void over(inout float3 col, float3 c, float a) { col = lerp(col, c, saturate(a)); }

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;

    float2 uv = ((float2)pixel + 0.5) / _Resolution.xy;
    float2 q  = float2(uv.x * PR_AR, uv.y);
    float  aa = 1.4 / _Resolution.y;
    float  lw = 0.0016;

    CastRec stage = Cast[SLOT_STAGE];

    // Editor state. Selection is read from the ONE place it is stored — the editor header —
    // rather than mirrored onto each record, so the schematic can never disagree with the
    // editor about what is selected.
    CastRec ed  = Cast[SLOT_EDIT];
    int     sel = (int)ed.pos.y - 1;          // -1 = nothing selected

    // ---- field -------------------------------------------------------------
    float3 col = float3(0.055, 0.058, 0.068) * (1.0 - 0.35 * uv.y);

    // 1/8 graticule, so displacements are readable as quantities
    float2 g8 = abs(frac(float2(uv.x, uv.y) * 8.0) - 0.5) / 8.0;
    float  gl = min(g8.x * PR_AR, g8.y);
    over(col, float3(0.10, 0.11, 0.13), (1.0 - smoothstep(0.0, 0.0012, gl)) * 0.55);

    // ground line — where world y = 0 actually lands at the hero's depth
    float horizonQ = toQ(float3(0.0, 0.0, 0.0)).y;
    over(col, float3(0.30, 0.33, 0.40), (1.0 - smoothstep(lw, lw + aa, abs(q.y - horizonQ))) * 0.85);

    // frame border
    float border = min(min(q.x, PR_AR - q.x), min(q.y, 1.0 - q.y));
    over(col, float3(0.22, 0.24, 0.30), 1.0 - smoothstep(0.004, 0.006, border));

    // ---- elevation: boxes, spheres, chips, membrane -------------------------
    [loop] for (uint i = 0u; i < (uint)CAST_COUNT; i++)
    {
        CastRec r = Cast[i];
        if (r.role == ROLE_NONE || r.role == ROLE_EDIT) continue;
        if (r.role == ROLE_STAGE || r.role == ROLE_TORUS || r.role == ROLE_RING) continue;

        // Switched-off records are drawn as ghosts rather than dropped. They are still
        // selectable, so hiding them entirely would strand the user with no way to find
        // what they just turned off.
        bool   on     = r.active > 0.5;
        bool   edited = pr_hasFlag(r, F_EDITED);
        float2 c      = toQ(r.pos);
        float3 rc     = roleColor(r.role) * depthKey(r.pos.z) * (on ? 1.0 : 0.30);
        float2 hbox   = float2(0.01, 0.01);   // q-space bounds, for the selection bracket

        if (r.role == ROLE_GLYPH || r.role == ROLE_PLATE || r.role == ROLE_POST)
        {
            float2 h = float2(qHalf(r.dims.x, r.pos.z), qHalf(r.dims.y, r.pos.z));
            hbox = h;
            float  d = dRect(q, c, h);
            over(col, rc * 0.35, (1.0 - smoothstep(-aa, aa, d)) * (on ? 0.45 : 0.10));
            over(col, rc, 1.0 - smoothstep(lw, lw + aa, abs(d)));
        }
        else if (r.role == ROLE_SPHERE)
        {
            hbox = qHalf(r.radius, r.pos.z).xx;
            float d = length(q - c) - qHalf(r.radius, r.pos.z);
            over(col, rc * 0.30, (1.0 - smoothstep(-aa, aa, d)) * (on ? 0.40 : 0.10));
            over(col, rc, 1.0 - smoothstep(lw, lw + aa, abs(d)));
            // chrome vs marble: a centre dot marks the mirror finish
            if (r.mat == MAT_CHROME)
                over(col, rc, 1.0 - smoothstep(0.0, aa * 2.0, length(q - c) - 0.004));
        }
        else if (r.role == ROLE_GEM)
        {
            float  s = qHalf(r.radius, r.pos.z);
            hbox = s.xx;
            float2 p = q - c;
            float  d;
            if (r.p0 < 0.5)      d = (abs(p.x) + abs(p.y)) * 0.7071 - s * 0.75;   // diamond
            else if (r.p0 < 1.5) d = max(abs(p.x), abs(p.y)) - s * 0.62;          // square
            else                 d = length(p) - s * 0.66;                        // round
            over(col, saturate(r.tint) * depthKey(r.pos.z) * 0.9, (1.0 - smoothstep(-aa, aa, d)) * 0.95);
        }
        else if (r.role == ROLE_FILM)
        {
            // The membrane record carries a real orientation, so the schematic has to draw
            // an ORIENTED footprint. Project its two edge vectors and solve q into that
            // frame; an axis-aligned box here would quietly misreport the drape's tilt.
            float2 ex = toQ(r.pos + pr_qrot(r.rot, float3(r.dims.x, 0, 0))) - c;
            float2 ey = toQ(r.pos + pr_qrot(r.rot, float3(0, r.dims.y, 0))) - c;
            float  det = ex.x * ey.y - ex.y * ey.x;
            if (abs(det) > 1e-9)
            {
                float2 rel = q - c;
                float  a2  = ( rel.x * ey.y - rel.y * ey.x) / det;
                float  b2  = (-rel.x * ex.y + rel.y * ex.x) / det;
                float  sc  = min(length(ex), length(ey));
                float  d   = (max(abs(a2), abs(b2)) - 1.0) * sc;

                hbox = float2(qHalf(r.dims.x, r.pos.z), qHalf(r.dims.y, r.pos.z));
                over(col, rc, 1.0 - smoothstep(lw, lw + aa, abs(d)));
                // fold ribs along the drape's own axis — this is where film_folds reads
                float rib = abs(frac(b2 * max(r.p1, 1.0) * 0.5 + 0.5) - 0.5);
                over(col, rc * 0.8, (1.0 - smoothstep(-aa, aa, d)) *
                                    (1.0 - smoothstep(0.05, 0.12, rib)) * 0.20);
                // billow depth as a dashed inner offset
                float db = abs(d + qHalf(r.dims.z, r.pos.z) * 0.5);
                float dash = step(0.5, frac((a2 + b2) * 9.0));
                over(col, rc * 0.75, (1.0 - smoothstep(lw * 0.7, lw * 0.7 + aa, db)) * dash * 0.7);
            }
        }

        // ---- editor overlays -------------------------------------------------
        // A hand-edited record gets a small solid tick at its top-right, so at a glance you
        // can see which of the composition is procedural and which you placed yourself.
        if (edited)
            over(col, float3(1.00, 0.82, 0.30),
                 1.0 - smoothstep(0.0, aa, dRect(q, c + hbox + 0.010, float2(0.0035, 0.0035))));

        if ((int)i == sel)
        {
            float db2 = abs(dRect(q, c, hbox + 0.014));
            over(col, float3(1.0, 1.0, 1.0), (1.0 - smoothstep(lw, lw + aa, db2)) * 0.95);
        }
    }

    // ---- the hero and the light ring, drawn as real projected centrelines ----
    // A tilted torus has no rectangle to fall back on: sampling the centreline is the only
    // way the schematic can honestly show the tip of the ring.
    [unroll] for (uint pass2 = 0u; pass2 < 2u; pass2++)
    {
        // ternary on a struct is not legal HLSL
        CastRec r;
        if (pass2 == 0u) r = Cast[SLOT_TORUS]; else r = Cast[SLOT_RING];
        if (r.active < 0.5) continue;

        float3 rc    = roleColor(r.role) * depthKey(r.pos.z);
        float  tube  = qHalf(r.dims.x, r.pos.z);
        float  best  = 1e9;

        [loop] for (uint k = 0u; k < 48u; k++)
        {
            float a0 = PR_TAU * (float)k / 48.0;
            float a1 = PR_TAU * (float)(k + 1u) / 48.0;
            float3 w0 = r.pos + pr_qrot(r.rot, float3(cos(a0), 0.0, sin(a0)) * r.radius);
            float3 w1 = r.pos + pr_qrot(r.rot, float3(cos(a1), 0.0, sin(a1)) * r.radius);
            best = min(best, dSeg(q, toQ(w0), toQ(w1)));
        }

        // tube envelope, then the centreline itself
        over(col, rc * 0.30, (1.0 - smoothstep(tube, tube + aa * 2.0, best)) * 0.55);
        over(col, rc, 1.0 - smoothstep(lw, lw + aa, abs(best - tube)) );
        over(col, rc * 1.2, (1.0 - smoothstep(lw * 0.7, lw * 0.7 + aa, best)) * 0.8);

        if ((int)((pass2 == 0u) ? SLOT_TORUS : SLOT_RING) == sel)
        {
            float rq = qHalf(r.radius + r.dims.x, r.pos.z) + 0.014;
            over(col, float3(1.0, 1.0, 1.0),
                 (1.0 - smoothstep(lw, lw + aa, abs(dRect(q, toQ(r.pos), rq.xx)))) * 0.95);
        }

        // hole-axis tick — the only readout of the tip
        if (pass2 == 0u)
        {
            float3 axis = pr_qrot(r.rot, float3(0, 1, 0));
            float2 a2   = toQ(r.pos);
            float2 b2   = toQ(r.pos + axis * r.radius * 0.85);
            over(col, float3(1.0, 0.85, 0.45), (1.0 - smoothstep(lw, lw + aa, dSeg(q, a2, b2))) * 0.9);
        }
    }

    // ---- top-down XZ depth strip -------------------------------------------
    // A full-width strip below the ground line rather than a corner box: its x axis is the
    // SAME axis as the elevation above it, so each record's depth reads directly under the
    // object it belongs to — and nothing in the composition gets covered up.
    float2 stripH = float2((PR_AR - 0.024) * 0.5, 0.0430);
    float2 ic     = float2(PR_AR * 0.5, 0.9440);
    float  dIn    = dRect(q, ic, stripH);
    if (dIn < 0.0)
    {
        over(col, float3(0.028, 0.031, 0.038), 0.94);

        float2 t = (q - (ic - stripH)) / (stripH * 2.0);

        // z = 0 plane, and the optical axis at x = 0
        over(col, float3(0.20, 0.22, 0.28),
             (1.0 - smoothstep(0.0, 0.0018, abs(t.y - (0.0 + 2.2) / 4.0) * stripH.y * 2.0)) * 0.9);
        over(col, float3(0.18, 0.20, 0.26),
             (1.0 - smoothstep(0.0, 0.0018, abs(t.x - 0.5) * stripH.x * 2.0)) * 0.6);

        [loop] for (uint j = 0u; j < (uint)CAST_COUNT; j++)
        {
            CastRec r = Cast[j];
            if (r.active < 0.5 || r.role == ROLE_STAGE || r.role == ROLE_EDIT) continue;

            // -x, so the strip's horizontal axis matches the elevation above it (see the
            // handedness note on pr_place).
            float2 pq = (ic - stripH) + float2((-r.pos.x + 2.6) / 5.2,
                                               (r.pos.z + 2.2) / 4.0) * stripH * 2.0;
            float  rr = clamp(max(r.radius, r.dims.x) * 0.030, 0.0022, 0.014);
            over(col, roleColor(r.role), 1.0 - smoothstep(rr, rr + aa, length(q - pq)));
        }

        // the camera sits at z = +12, far past the plotted range: mark the near edge
        float camY = (ic - stripH).y + 1.0 * stripH.y * 2.0;
        over(col, float3(0.95, 0.75, 0.30),
             (1.0 - smoothstep(0.0016, 0.0030, abs(q.y - camY + 0.004))) * 0.8);
    }
    over(col, float3(0.26, 0.29, 0.36), 1.0 - smoothstep(lw, lw + aa, abs(dIn)));

    // ---- role tallies -------------------------------------------------------
    // One tick per ACTIVE record, grouped by role. A gem loop that silently drops emits
    // shows up here as a short row.
    float2 tallyO = float2(PR_AR - 0.028, 0.045);
    [loop] for (uint rr2 = 1u; rr2 <= 9u; rr2++)
    {
        float role = (float)rr2;
        uint  n = 0u;
        [loop] for (uint m = 0u; m < (uint)CAST_COUNT; m++)
            if (Cast[m].active > 0.5 && Cast[m].role == role) n++;

        float rowY = tallyO.y + (float)(rr2 - 1u) * 0.019;
        float3 rc  = roleColor(role);

        // role swatch
        over(col, rc, 1.0 - smoothstep(0.0, aa, dRect(q, float2(tallyO.x, rowY), float2(0.0055, 0.0055))));

        [loop] for (uint t2 = 0u; t2 < n && t2 < 44u; t2++)
        {
            float2 tp = float2(tallyO.x - 0.017 - (float)(t2 % 22u) * 0.0072,
                               rowY + ((t2 < 22u) ? -0.0032 : 0.0032));
            over(col, rc * 0.95, 1.0 - smoothstep(0.0, aa, dRect(q, tp, float2(0.0022, 0.0022))));
        }
    }

    // exploration axes, read back off the stage record so the readout cannot drift from
    // what was actually published: two short bars, one notch per selected index
    [unroll] for (uint ax = 0u; ax < 2u; ax++)
    {
        float v = (ax == 0u) ? stage.p0 : stage.p1;
        [loop] for (uint s2 = 0u; s2 < 3u; s2++)
        {
            float2 bp = float2(0.020 + (float)s2 * 0.014, 0.026 + (float)ax * 0.016);
            float  on = (abs(v - (float)s2) < 0.5) ? 1.0 : 0.18;
            over(col, float3(0.85, 0.88, 0.95) * on,
                 1.0 - smoothstep(0.0, aa, dRect(q, bp, float2(0.005, 0.0035))));
        }
    }

    OutputUAV[pixel] = float4(col, 1.0);
}
