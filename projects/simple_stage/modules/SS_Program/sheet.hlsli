// SS_Program / sheet - the programmer sheet's geometry as a pure function of the live extent,
// shared by the drawing (preview.hlsl), its type (layout.hlsl) and the hover hit test, so what you
// see and what you point at cannot disagree at any panel size.
#ifndef SS_SHEET_HLSLI
#define SS_SHEET_HLSLI
#include "../_shared/ss_layout.hlsli"
#define SHEET_ROWS 17u
#define SHEET_COLS ((uint)SS_ROWS)
#define SHEET_GROUPS 7
#define SHEET_NONE 0xffffffffu
// One column per program row, grouped by layer in fixture-type order: the Halo Beams' MOVE, BEAM and HALO, the
// Linear Strobes' TUBE and PLATES, the Pixel Battens' PIXELS and CHASE. A group's columns are consecutive program
// rows from SHEET_ROW0 (tools/ss_layout.py: base rows 0..SLOTS-1, BEAM slot + BEAM0, the second layer slot + LAYER2).
#define SHEET_M SS_MOVERS
#define SHEET_S SS_STROBES
#define SHEET_B SS_BARS
static const uint SHEET_FIRST[7] = { 0u, SHEET_M, 2*SHEET_M, 3*SHEET_M, 3*SHEET_M+SHEET_S, 3*SHEET_M+2*SHEET_S, 3*SHEET_M+2*SHEET_S+SHEET_B };
static const uint SHEET_END[7] = { SHEET_M, 2*SHEET_M, 3*SHEET_M, 3*SHEET_M+SHEET_S, 3*SHEET_M+2*SHEET_S, 3*SHEET_M+2*SHEET_S+SHEET_B, 3*SHEET_M+2*SHEET_S+2*SHEET_B };
static const uint SHEET_ROW0[7] = { SS_MOVER0, SS_BEAM0, SS_LAYER2+SS_MOVER0, SS_STROBE0, SS_LAYER2+SS_STROBE0, SS_BAR0, SS_LAYER2+SS_BAR0 };
// The fixture type of each group: 0 Halo Beam, 1 Linear Strobe, 2 Pixel Batten.
static const uint SHEET_TYPE[7] = { 0u, 0u, 0u, 1u, 1u, 2u, 2u };
// Which of the 17 attributes each layer reads (attribute_catalog kinds; docs/PROGRAMMING.md): bit a set = read.
// Cells a layer ignores are drawn as empty wells, so each layer's shape shows at a glance.
static const uint SHEET_READS[7] = { 0x1FE43u, 0x1F994u, 0x1F9A8u, 0x1F884u, 0x1F998u, 0x1F9B4u, 0x1F884u };

struct Sheet
{
    float  s;        // type scale
    float4 pane;     // the sheet's plate
    float4 grid;     // where the cells live (x0, top, right, bottom)
    float4 strip;    // the inspector strip under the plate
    float  pitch;    // one column
    float  cell;     // a cell's drawn width
    float  gap;      // between layers; three between fixture types
    float  rowH;
};

Sheet sheetOf(float2 R)
{
    Sheet g;
    g.s = max(ilCtx(R).s, 0.85);
    float s = g.s;
    g.strip = float4(8.0, R.y - 8.0 - 30.0 * s, R.x - 8.0, R.y - 8.0);
    g.pane = float4(8.0, 38.0 * s, R.x - 8.0, g.strip.y - 8.0);
    g.gap = 4.0 * s;
    float x0 = g.pane.x + 118.0 * s, x1 = g.pane.z - 10.0 * s;
    g.pitch = max((x1 - x0 - (6.0 + 2.0 * 2.0) * g.gap) / SHEET_COLS, 0.5);
    g.cell = max(1.0, g.pitch * 0.82);
    g.grid = float4(x0, g.pane.y + 40.0 * s, x1, g.pane.w - 6.0 * s);
    g.rowH = (g.grid.w - g.grid.y) / SHEET_ROWS;
    return g;
}

// Each attribute's range (the grey ramp runs over it) and where it lives in a program row.
static const float2 SHEET_RANGE[17] = { float2(-270, 270), float2(-135, 135), float2(0, 1), float2(0, 1), float2(0, 2),
    float2(0, 2), float2(0, 5), float2(0, 5), float2(0, 5), float2(-180, 180), float2(-90, 90), float2(0, 0.95),
    float2(0, 1), float2(-1, 1), float2(0, 1), float2(0, 63), float2(0, 7) };
float sheetAttr(SsProgram r, uint a)
{
    float4 v = a < 4u ? r.aim : (a < 8u ? r.routing : (a < 12u ? r.movement : (a < 16u ? r.timing : r.extra)));
    uint k = a >= 16u ? 0u : a % 4u;
    return k == 0u ? v.x : (k == 1u ? v.y : (k == 2u ? v.z : v.w));
}

uint sheetGroup(uint c)
{
    uint grp = SHEET_GROUPS - 1u;
    [unroll] for (int f = SHEET_GROUPS - 2; f >= 0; f--) grp = c < SHEET_END[f] ? (uint)f : grp;
    return grp;
}
// The program row a column shows, and the fixture slot that row belongs to.
uint sheetRow(uint c) { uint grp = sheetGroup(c); return SHEET_ROW0[grp] + c - SHEET_FIRST[grp]; }
uint rowSlot(uint r) { return r < (uint)SS_SLOTS ? r : (r < (uint)SS_LAYER2 ? r - SS_BEAM0 : r - SS_LAYER2); }
float colX(Sheet g, uint c)
{
    uint grp = sheetGroup(c);
    return g.grid.x + c * g.pitch + (grp + 2u * SHEET_TYPE[grp]) * g.gap;
}

// The column that contains x, or SHEET_NONE between groups or outside the grid.
uint colAt(Sheet g, float x)
{
    [unroll] for (int f = SHEET_GROUPS - 1; f >= 0; f--)
    {
        float fx = colX(g, SHEET_FIRST[f]);
        if (x >= fx)
        {
            uint c = SHEET_FIRST[f] + (uint)floor((x - fx) / g.pitch);
            return c < SHEET_END[f] ? c : SHEET_NONE;
        }
    }
    return SHEET_NONE;
}
#endif
