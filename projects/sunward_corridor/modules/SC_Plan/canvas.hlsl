// SC_Plan / canvas.hlsl — the editor surface.
//
// A draughtsman's plan and elevation of ONE LOOP of corridor, not a copy of the program image.
// Reading it should answer, without opening the renderer: where do the walls go, how wide is
// the aperture at each station, which stations are hand-edited or switched off, where is every
// organic mass sitting on the perimeter, where is the camera right now, and does the flight
// path actually stay inside the tunnel.
//
// Every handle is drawn through the same helpers plan.hlsl picks with, so what you can see is
// exactly what you can grab.
#include "../_shared/corridor.hlsli"
#include "../_shared/plan_theme.hlsli"

StructuredBuffer<ScRec> Plan : register(t0);
RWTexture2D<float4> OutputUAV : register(u0);

// INSTRUMENT PALETTE — see plan_theme.hlsli. Mostly monochrome; hue only where it informs.
#define INK        PT_FIELD
#define INK_GRID   PT_GRID
#define INK_AXIS   PT_RULE
#define CHALK      PT_INK
#define HOT        PT_ACCENT   // RESERVED: selection
#define AMBER      PT_MID      // edit state — value, not hue
#define COOL       PT_DIM      // limits and tallies

ScProfile profileAtZ(float zw)
{
    int i0, i1, i2, i3; float t;
    sc_bayFrame(zw, i0, i1, i2, i3, t);
    return sc_profileFrom(Plan[SC_BAY_0 + (uint)i0], Plan[SC_BAY_0 + (uint)i1],
                          Plan[SC_BAY_0 + (uint)i2], Plan[SC_BAY_0 + (uint)i3], t);
}

// Mass kind by VALUE, not hue: five members is past the point where an identity set reads, and
// the legend carries the mapping. MK_LENS keeps a tint because it is the one kind that behaves
// differently rather than merely looking different.
float3 massColour(int k)
{
    if (k == MK_LENS) return PT_ID_A;
    float t = (k >= MK_LENS) ? 1.0 : ((float)k / 3.0);
    return ptRamp(t);
}

// soft coverage of a disc, in aspect-corrected uv
float disc(float2 uv, float2 c, float r, float2 asp, float px)
{
    return 1.0 - smoothstep(r - px, r + px, length((uv - c) * asp));
}
float ring(float2 uv, float2 c, float r, float w, float2 asp, float px)
{
    float d = abs(length((uv - c) * asp) - r);
    return 1.0 - smoothstep(w - px, w + px, d);
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    uint W, H;
    OutputUAV.GetDimensions(W, H);
    if (pixel.x >= W || pixel.y >= H) return;

    float2 uv = ((float2)pixel + 0.5) / float2(W, H);
    float2 asp = float2((float)W / max((float)H, 1.0), 1.0);
    float px = 1.0 / (float)H;

    ScRec hdr = Plan[SC_HEADER];
    float sel = hdr.pos.y;
    float travel = hdr.phase;
    uint liveB = (uint)fmod(hdr.flags, 100.0);
    uint liveM = (uint)(hdr.flags / 100.0);

    float3 col = INK;

    // --- station grid, drawn under everything --------------------------------------------
    for (uint g = 0u; g < SC_BAYS; g++)
    {
        float gx = sc_zToX((float)g * SC_BAY_Z);
        float lw = (Plan[SC_BAY_0 + g].active > 0.5) ? 0.0009 : 0.0006;
        float hit = 1.0 - smoothstep(lw, lw + px, abs(uv.x - gx));
        if (uv.y > 0.055 && uv.y < 0.945) col = lerp(col, INK_GRID, hit * 0.9);
    }

    int strip = sc_stripAt(uv);
    bool inDiag = (uv.x > SC_DIAG_X0 - 0.012 && uv.x < SC_DIAG_X1 + 0.012);

    // --- the two orthographic strips ------------------------------------------------------
    if (inDiag && (strip == 1 || strip == 2))
    {
        float cy = (strip == 1) ? SC_PLAN_CY : SC_ELEV_CY;
        float z = sc_xToZ(uv.x);
        ScProfile pf = profileAtZ(sc_wrapZ(z));

        float c = (strip == 1) ? pf.c.x : pf.c.y;
        float h = (strip == 1) ? pf.h.x : pf.h.y;
        float wLo = sc_wToY(c - h, cy);      // larger uv.y (down)
        float wHi = sc_wToY(c + h, cy);

        // interior fill, tinted by the palette actually in force at this z
        float inside = step(min(wHi, wLo), uv.y) * step(uv.y, max(wHi, wLo));
        float3 tint = PT_MID;
        col = lerp(col, lerp(INK, tint, 0.16), inside);

        // the checker cadence, so the tile scale is legible from the plan
        float cellz = frac(z / max(pf.chk, 0.05) * 0.5);
        col = lerp(col, lerp(INK, tint, 0.24), inside * step(cellz, 0.5) * 0.5);

        // walls
        float wallW = 0.0016;
        float wall = max(1.0 - smoothstep(wallW, wallW + px, abs(uv.y - wLo)),
                         1.0 - smoothstep(wallW, wallW + px, abs(uv.y - wHi)));
        col = lerp(col, lerp(CHALK, tint, 0.45), wall);

        // centreline of the corridor
        float ctr = 1.0 - smoothstep(0.0006, 0.0006 + px, abs(uv.y - sc_wToY(c, cy)));
        col = lerp(col, INK_AXIS, ctr * 0.85);

        // THE FLIGHT AXIS — world 0, where the camera actually sits. If this line ever leaves
        // the filled band the viewer is flying through a wall, and that has to be visible here
        // rather than discovered in the renderer.
        float axY = sc_wToY(0.0, cy);
        float ax = 1.0 - smoothstep(0.0008, 0.0008 + px, abs(uv.y - axY));
        float dash = step(0.35, frac(uv.x * 190.0));
        bool outside = (0.0 < c - h) || (0.0 > c + h);
        col = lerp(col, outside ? PT_ALARM : COOL, ax * dash * 0.95);
    }

    // --- masses, projected into both strips -----------------------------------------------
    for (uint m = 0u; m < SC_MASSES; m++)
    {
        ScRec r = Plan[SC_MASS_0 + m];
        ScProfile pf = profileAtZ(r.pos.x);
        float2 sec = sc_massSection(r, pf.h);
        float3 mc = massColour((int)r.kind);
        bool on = r.active > 0.5;
        bool isSel = (sel > 0.5) && ((uint)(sel - 1.0) == SC_MASS_0 + m);
        bool edited = (((uint)r.flags) & F_EDITED) != 0u;

        for (uint s = 0u; s < 2u; s++)
        {
            float cy = (s == 0u) ? SC_PLAN_CY : SC_ELEV_CY;
            float w = (s == 0u) ? (pf.c.x + sec.x) : (pf.c.y + sec.y);
            float2 hp = float2(sc_zToX(r.pos.x), sc_wToY(w, cy));
            float rad = max(r.size.x / SC_WORLD_H * SC_STRIP_H, 0.010);

            // elongation along the corridor is a real, editable magnitude — show it
            float2 e = float2(rad * r.size.y * 0.55 / asp.x, rad);
            float2 q = (uv - hp) / max(e, 1e-4);
            float ql = length(q);
            float cov = 1.0 - smoothstep(1.0 - px / rad, 1.0 + px / rad, ql);
            // translucent body + a hard rim: a mass has to show its true footprint against the
            // aperture without hiding the wall it is attached to.
            col = lerp(col, mc, cov * (on ? 0.34 : 0.08));
            float rim = (1.0 - smoothstep(1.0 - px / rad, 1.0 + px / rad, ql))
                      * smoothstep(1.0 - 3.5 * px / rad, 1.0 - px / rad, ql);
            col = lerp(col, mc, rim * (on ? 0.95 : 0.40));
            if (edited) col = lerp(col, AMBER, ring(uv, hp, rad * 1.35, 0.0012, asp, px) * 0.8);
            if (isSel)  col = lerp(col, HOT,   ring(uv, hp, rad * 1.70, 0.0022, asp, px));
        }
    }

    // --- bay handles ----------------------------------------------------------------------
    for (uint b = 0u; b < SC_BAYS; b++)
    {
        ScRec r = Plan[SC_BAY_0 + b];
        bool on = r.active > 0.5;
        bool isSel = (sel > 0.5) && ((uint)(sel - 1.0) == SC_BAY_0 + b);
        bool edited = (((uint)r.flags) & F_EDITED) != 0u;
        float3 hc = ptRamp((float)r.kind / (float)(SC_PALSETS - 1));

        for (uint s = 0u; s < 2u; s++)
        {
            float cy = (s == 0u) ? SC_PLAN_CY : SC_ELEV_CY;
            float w = (s == 0u) ? r.pos.x : r.pos.y;
            float2 hp = float2(sc_zToX((float)b * SC_BAY_Z), sc_wToY(w, cy));
            col = lerp(col, on ? hc : INK_AXIS, disc(uv, hp, 0.0105, asp, px));
            col = lerp(col, CHALK, ring(uv, hp, 0.0105, 0.0013, asp, px) * (on ? 0.85 : 0.35));
            if (edited) col = lerp(col, AMBER, ring(uv, hp, 0.0165, 0.0012, asp, px) * 0.85);
            if (isSel)  col = lerp(col, HOT,   ring(uv, hp, 0.0225, 0.0022, asp, px));
        }
    }

    // --- travel playhead ------------------------------------------------------------------
    if (inDiag && uv.y > 0.055 && uv.y < 0.945)
    {
        float tx = sc_zToX(travel);
        // the stretch of corridor about to arrive, brightest right at the eye. Drawn UNDER the
        // playhead so the line itself stays the sharpest thing in the diagram.
        float dz = sc_wrapZ(sc_xToZ(uv.x) - sc_xToZ(tx));
        col = lerp(col, col + PT_MID * 0.055, saturate(1.0 - dz / 7.0));
        float ph = 1.0 - smoothstep(0.0011, 0.0011 + px, abs(uv.x - tx));
        col = lerp(col, PT_ACCENT, ph * 0.95);   // playhead: a live reading, so it earns the accent
    }

    // --- sun inset: the real sky plate, not a schematic of one ----------------------------
    {
        float2 ic = float2((SC_INSET_X0 + SC_INSET_X1) * 0.5, (SC_INSET_Y0 + SC_INSET_Y1) * 0.5);
        float2 ih = float2((SC_INSET_X1 - SC_INSET_X0) * 0.5, (SC_INSET_Y1 - SC_INSET_Y0) * 0.5);
        float2 d = abs(uv - ic) - ih;
        float inBox = 1.0 - step(0.0, max(d.x, d.y));
        if (inBox > 0.5)
        {
            float2 s = float2((uv.x - ic.x) / ih.x, -(uv.y - ic.y) / ih.y);
            col = ptInset(sc_skyPlate(s, Plan[SC_SKY], px / ih.y));
        }
        float border = 1.0 - smoothstep(0.0016, 0.0016 + px, abs(max(d.x, d.y)));
        bool skySel = (sel > 0.5) && ((uint)(sel - 1.0) == SC_SKY);
        col = lerp(col, skySel ? HOT : CHALK, border * (skySel ? 1.0 : 0.55));
    }

    // --- tallies: live bays (top row) and live masses (bottom row) ------------------------
    for (uint t = 0u; t < SC_BAYS; t++)
    {
        float2 p = float2(0.060 + (float)t * 0.016, 0.028);
        float on = (t < liveB) ? 1.0 : 0.0;
        col = lerp(col, lerp(INK_AXIS, PT_MID, on), disc(uv, p, 0.0052, asp, px));
    }
    for (uint t2 = 0u; t2 < SC_MASSES; t2++)
    {
        float2 p = float2(0.060 + (float)t2 * 0.016, 0.972);
        float on = (t2 < liveM) ? 1.0 : 0.0;
        col = lerp(col, lerp(INK_AXIS, PT_INK, on), disc(uv, p, 0.0052, asp, px));
    }

    OutputUAV[pixel] = float4(col, 1.0);
}
