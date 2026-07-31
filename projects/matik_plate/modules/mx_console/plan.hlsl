// mx_console / plan.hlsl — authors the whole plate plan into one durable record buffer.
//
// Single-threaded on purpose: the layout is a sequential guillotine subdivision and the
// viewport event queue must be reduced in order. 128 records is trivial work; the cost of
// this pass is noise next to any render pass.
//
// Regeneration is signature-driven. A parameter (or the R-key salt) changing the signature
// rebuilds the plan from scratch; anything else preserves the buffer, so hand edits made by
// dragging survive across cooks, saves, and undo.
#include "../_shared/plate.hlsli"

RWStructuredBuffer<PlateRec> Plate : register(u0);

// The plan buffer is persistent, so it only rebuilds when the signature changes. Parameters
// feed that signature — shader edits do not. BUMP THIS whenever the layout algorithm below
// changes, or a recompile will keep serving the previously generated plan.
#define PLAN_VERSION 2.0

// Archetype anchor slots, transcribed from where the reference puts its organisms:
// one hero mass just off centre, dendritic clusters into three corners, then optional
// satellites. Seed jitter moves them; dragging overrides them.
static const float2 ANCHOR_POS[8] = {
    float2(0.455, 0.430), float2(0.135, 0.165), float2(0.125, 0.830), float2(0.860, 0.815),
    float2(0.880, 0.320), float2(0.320, 0.930), float2(0.905, 0.095), float2(0.585, 0.690)
};
// x = reserve radius (how much plate it clears), y = growth scale
static const float2 ANCHOR_SIZE[8] = {
    float2(0.230, 1.00), float2(0.150, 0.66), float2(0.160, 0.70), float2(0.165, 0.72),
    float2(0.105, 0.48), float2(0.095, 0.42), float2(0.085, 0.38), float2(0.100, 0.44)
};
static const float ANCHOR_KIND[8] = { 0, 1, 1, 1, 2, 1, 2, 0 };

// kind pools, chosen by cell aspect so a wide strip never gets a radial dial
static const int KW_WIDE[6]  = { K_RAIL, K_DASH, K_GLYPH, K_CHEVRON, K_BARS, K_KEYS };
static const int KW_TALL[4]  = { K_BARS, K_KEYS, K_DOTS, K_DASH };
static const int KW_SMALL[5] = { K_TARGET, K_DIAL, K_GLYPH, K_DATA, K_CHECKER };
static const int KW_BLOCK[9] = { K_GRID, K_CHECKER, K_DOTS, K_HALFTONE, K_DATA, K_CONE, K_SPIRAL, K_WAVE, K_KEYS };

float pickKind(float2 hs, float sd)
{
    float ar = hs.x / max(hs.y, 1e-5);
    float h = mxRnd(sd, 7.0);
    if (ar > 2.8)  return (float)KW_WIDE[(uint)(h * 6.0) % 6u];
    if (ar < 0.36) return (float)KW_TALL[(uint)(h * 4.0) % 4u];
    if (hs.x * hs.y < 0.0016) return (float)KW_SMALL[(uint)(h * 5.0) % 5u];
    return (float)KW_BLOCK[(uint)(h * 9.0) % 9u];
}

void buildAnchors(float s)
{
    uint want = (uint)clamp((float)anchor_count, 1.0, 8.0);
    for (uint i = 0u; i < 8u; i++)
    {
        PlateRec r = (PlateRec)0;
        float2 j = (mxHash22(float2(s * 13.1 + (float)i * 4.7, 7.7)) - 0.5) * 0.075;
        r.pos  = clamp(ANCHOR_POS[i] + j, 0.06, 0.94);
        r.size = float2(ANCHOR_SIZE[i].x * organism_scale * reserve,
                        ANCHOR_SIZE[i].y * organism_scale);
        r.role = ROLE_ANCHOR;
        r.kind = ANCHOR_KIND[i];
        r.seed = s * 3.3 + (float)i * 17.0 + 1.0;
        r.tone = 0.55 + 0.45 * mxRnd(r.seed, 3.0);
        r.grp  = (float)i;
        r.phase = mxRnd(r.seed, 5.0);
        r.flags = 0.0;
        r.active = (i < want) ? 1.0 : 0.0;
        Plate[PLATE_ANCHOR_0 + i] = r;
    }
}

void buildCells(float s)
{
    float4 rc[72];
    uint nr = 1u;
    float m = margin;
    rc[0] = float4(m, m, 1.0 - 2.0 * m, 1.0 - 2.0 * m);

    uint target = (uint)clamp((float)cell_count, 6.0, 64.0);
    int preset = (int)layout_preset;

    if (preset == 2)
    {
        // Ring Array — concentric bands of cells around the plate centre. A different
        // structural idea rather than a re-tuned guillotine, so the preset actually matters.
        nr = 0u;
        uint ring = 0u;
        while (nr < target && ring < 7u)
        {
            float rad = 0.085 + 0.068 * (float)ring;
            uint cnt = 6u + ring * 4u;
            for (uint k = 0u; k < cnt && nr < target && nr < 72u; k++)
            {
                float a = 6.2831853 * ((float)k / (float)cnt) + mxRnd(s + (float)ring, (float)k) * 0.30;
                float2 c = float2(0.5, 0.5) + float2(cos(a), sin(a) * 0.98) * rad;
                // cells grow with radius so the outer bands read as panels, not confetti
                float sc = 0.55 + 0.75 * (float)ring / 6.0;
                float w = lerp(0.055, 0.150, mxRnd(s * 2.0 + (float)ring, (float)k + 40.0)) * sc;
                float h = lerp(0.040, 0.110, mxRnd(s * 2.0 + (float)ring, (float)k + 80.0)) * sc;
                rc[nr++] = float4(c.x - w * 0.5, c.y - h * 0.5, w, h);
            }
            ring++;
        }
    }
    else
    {
        uint guard = 0u;
        while (nr < target && nr < 72u && guard < 240u)
        {
            guard++;
            uint bi = 0u; float ba = -1.0;
            for (uint i = 0u; i < nr; i++) { float a = rc[i].z * rc[i].w; if (a > ba) { ba = a; bi = i; } }
            float4 R = rc[bi];
            float h1 = mxHash21(float2(s * 5.3 + (float)guard * 1.7, 2.1));
            float h2 = mxHash21(float2(s * 7.9 + (float)guard * 3.1, 9.4));

            bool vert;
            // Dense Strata lays horizontal bands first, then subdivides inside them, which
            // is what makes it read as strata rather than a stack of full-width bars.
            if (preset == 1)      vert = (guard < 5u) ? true : (h1 < 0.34);   // Column Rack
            else if (preset == 3) vert = (guard < 7u) ? false : (h1 < 0.80);  // Dense Strata
            else                  vert = (R.z > R.w) ? (h1 < 0.86) : (h1 > 0.86);

            float ratio = lerp(0.32, 0.68, h2);
            if (h1 > 0.80) ratio = lerp(0.13, 0.29, h2);   // occasional thin strip

            if (vert) { rc[bi] = float4(R.x, R.y, R.z * ratio, R.w);
                        rc[nr] = float4(R.x + R.z * ratio, R.y, R.z * (1.0 - ratio), R.w); }
            else      { rc[bi] = float4(R.x, R.y, R.z, R.w * ratio);
                        rc[nr] = float4(R.x, R.y + R.w * ratio, R.z, R.w * (1.0 - ratio)); }
            nr++;
        }
    }

    for (uint i = 0u; i < PLATE_CELLS; i++)
    {
        PlateRec r = (PlateRec)0;
        r.role = ROLE_CELL;
        if (i >= nr) { r.active = 0.0; Plate[i] = r; continue; }

        float4 R = rc[i];
        float2 c  = float2(R.x + R.z * 0.5, R.y + R.w * 0.5);
        float2 hs = float2(R.z * 0.5 - gap, R.w * 0.5 - gap);
        float sd  = s * 2.7 + (float)i * 13.37 + 3.0;

        r.pos = c;
        r.size = max(hs, 0.0);
        r.seed = sd;
        r.tone = mxRnd(sd, 1.0);
        r.grp = floor(c.y * 6.0);
        r.phase = mxRnd(sd, 2.0);
        r.kind = pickKind(max(hs, 1e-4), sd);
        r.flags = 0.0;

        bool ok = (hs.x > 0.006 && hs.y > 0.006);
        for (uint a = 0u; a < 8u; a++)
        {
            PlateRec an = Plate[PLATE_ANCHOR_0 + a];
            if (an.active < 0.5) continue;
            // Rect-vs-disc, not centre-vs-disc: a big panel whose centre sits outside the
            // reserve still covers the organism. Clearing the core carves real negative
            // space; panels in the outer ring survive and knock out the wireframe, which is
            // exactly the layering the reference has.
            float2 dq = max(abs(an.pos - c) - r.size, 0.0);
            if (length(dq) < an.size.x * 0.58) ok = false;
        }
        if (mxRnd(sd, 4.0) < thinning) ok = false;
        r.active = ok ? 1.0 : 0.0;
        Plate[i] = r;
    }
}

// Nearest pickable record under a plate-space point. Smallest containing cell wins so a
// tag sitting on a big panel stays reachable; anchors win inside their core disc.
uint pickRecord(float2 p)
{
    uint best = 0u; float bestScore = 1e9;
    for (uint a = 0u; a < 8u; a++)
    {
        PlateRec an = Plate[PLATE_ANCHOR_0 + a];
        if (an.active < 0.5) continue;
        float d = length(p - an.pos);
        if (d < an.size.x * 0.34 && d < bestScore) { bestScore = d; best = PLATE_ANCHOR_0 + a + 1u; }
    }
    if (best != 0u) return best;
    for (uint i = 0u; i < PLATE_CELLS; i++)
    {
        PlateRec r = Plate[i];
        if (r.role > 0.5) continue;
        float2 q = abs(p - r.pos) - r.size - 0.004;
        if (max(q.x, q.y) < 0.0)
        {
            float area = r.size.x * r.size.y;
            if (area < bestScore) { bestScore = area; best = i + 1u; }
        }
    }
    return best;
}

[numthreads(1, 1, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    PlateRec hdr = Plate[PLATE_HEADER];
    float initFlag = hdr.tone;
    float salt     = hdr.seed;
    float sel      = hdr.pos.y;     // selected index + 1, 0 = nothing
    float dragOn   = hdr.size.x;
    float2 grab    = float2(hdr.size.y, hdr.kind);

    uint n = min((uint)_ViewportEventCount, 64u);

    // --- pass 1: keys. R changes the salt, so it must land before the signature test.
    for (uint e = 0u; e < n; e++)
    {
        ViewportEvent ev = _ViewportEvents[e];
        if (ev.type != 4u || ev.phase != 1u) continue;
        uint c = (uint)ev.code;
        if (c == 18u) salt += 1.0;                                  // R  regenerate
        else if (c == 3u) sel = 0.0;                                 // C  clear selection
        else if (sel > 0.5)
        {
            uint idx = (uint)(sel - 1.0);
            PlateRec r = Plate[idx];
            if (c == 11u)                                            // K  cycle kind
            {
                if (r.role < 0.5) r.kind = fmod(r.kind + 1.0, (float)K_KINDS);
                else              r.kind = fmod(r.kind + 1.0, 3.0);
                r.flags = (float)(((uint)r.flags) | F_EDITED);
            }
            else if (c == 24u)                                       // X  toggle active
            {
                r.active = (r.active > 0.5) ? 0.0 : 1.0;
                r.flags = (float)(((uint)r.flags) | F_EDITED);
            }
            else if (c == 14u)                                       // N  re-roll this record
            {
                r.seed += 7.77;
                r.tone = mxRnd(r.seed, 1.0);
                r.phase = mxRnd(r.seed, 2.0);
                r.flags = (float)(((uint)r.flags) | F_EDITED);
            }
            Plate[idx] = r;
        }
    }

    float sig = seed * 7.31 + (float)cell_count * 1.13 + (float)layout_preset * 3.77
              + margin * 53.1 + gap * 97.3 + reserve * 31.7 + (float)anchor_count * 5.51
              + organism_scale * 23.9 + thinning * 61.3 + salt * 101.3 + PLAN_VERSION * 911.7;

    if (initFlag < 0.5 || abs(sig - hdr.pos.x) > 1e-4)
    {
        float s = seed + salt * 3.19;
        buildAnchors(s);
        buildCells(s);
        sel = 0.0; dragOn = 0.0;
    }

    // --- pass 2: pointer. Selection and drag share pickRecord()/plate space with the canvas.
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
                if (hit != 0u) { dragOn = 1.0; grab = Plate[hit - 1u].pos - p; }
            }
            else if (ev.phase == 6u && dragOn > 0.5 && sel > 0.5)
            {
                uint idx = (uint)(sel - 1.0);
                PlateRec r = Plate[idx];
                r.pos = clamp(p + grab, 0.02, 0.98);
                r.flags = (float)(((uint)r.flags) | F_EDITED);
                Plate[idx] = r;
            }
            else { dragOn = 0.0; }
        }
    }

    // selection flag is derived, never stored twice
    for (uint i = 0u; i < PLATE_RECORDS - 1u; i++)
    {
        PlateRec r = Plate[i];
        uint f = (uint)r.flags;
        f = (sel > 0.5 && (uint)(sel - 1.0) == i) ? (f | F_SELECTED) : (f & ~F_SELECTED);
        r.flags = (float)f;
        Plate[i] = r;
    }

    uint liveCells = 0u, liveAnch = 0u;
    for (uint j = 0u; j < PLATE_CELLS; j++) if (Plate[j].active > 0.5) liveCells++;
    for (uint k = 0u; k < 8u; k++) if (Plate[PLATE_ANCHOR_0 + k].active > 0.5) liveAnch++;

    hdr.pos   = float2(sig, sel);
    hdr.size  = float2(dragOn, grab.x);
    hdr.role  = ROLE_HEADER;
    hdr.kind  = grab.y;
    hdr.seed  = salt;
    hdr.tone  = 1.0;
    hdr.grp   = (float)liveCells;
    hdr.phase = (float)liveAnch;
    hdr.flags = (float)n;
    hdr.active = 1.0;
    Plate[PLATE_HEADER] = hdr;
}
