// One thread per global mode: the mode's draw plan, rebuilt only when the FixtureTypes generation or RP_PLAN_FORMAT
// changes; the plan_mark pass records both after this pass, stamping the format this pass actually wrote, since a
// hot reload can install the passes in any order. The mode's geometry tree is the one its fixture-level channels
// sit in (else its first cell's, else the type's first top-level geometry). Geometry records are in document order, so a
// subtree is a contiguous run: the tree's nodes become entries in order, then each GeometryReference appends its
// template's nodes, the template root posed by the reference. An entry records the DMX Pan or Tilt channel that
// turns its geometry: a fixture-level channel for the tree's nodes, the reference's cell's channel in a template.
#include "probe.hlsli"

RWStructuredBuffer<PlanRecord> Plan : register(u0);

uint topLevel(uint g)
{
    [loop] for (uint k = 0u; k < 16u; k++)
    {
        uint p = gdtfGeometry(g, 0u).y;
        if (p == GDTF_NONE) return g;
        g = p;
    }
    return g;
}

bool isBelow(uint g, uint root)
{
    [loop] for (uint k = 0u; k < 16u; k++)
    {
        g = gdtfGeometry(g, 0u).y;
        if (g == GDTF_NONE) return false;
        if (g == root) return true;
    }
    return false;
}

uint subtreeEnd(uint root, uint geoEnd)
{
    uint g = root + 1u;
    [loop] while (g < geoEnd && isBelow(g, root)) g++;
    return g;
}

uint cellOfMode(uint4 m1, uint node)
{
    [loop] for (uint c = 0u; c < m1.w; c++)
        if (gdtfCell(m1.z + c).x == node) return c;
    return GDTF_NONE;
}

// The DMX Pan or Tilt channel of `cell` (none for fixture level) whose geometry is `node`: (channel, 0 Pan / 1 Tilt).
uint2 axisChannel(uint4 m0, uint node, uint cell)
{
    [loop] for (uint c = m0.x; c < m0.x + m0.y; c++)
    {
        uint4 r0 = gdtfChannel(c, 0u), r2 = gdtfChannel(c, 2u);
        if ((r0.w & GDTF_CHANNEL_VIRTUAL) != 0u || r2.x != node || r2.y != cell) continue;
        uint base = r2.w & 0xFFFFu;
        if (base == GDTF_ATTR_PAN) return uint2(c, 0u);
        if (base == GDTF_ATTR_TILT) return uint2(c, 1u);
    }
    return uint2(GDTF_NONE, 0u);
}

[numthreads(64, 1, 1)]
void main(uint3 id : SV_DispatchThreadID)
{
    uint m = id.x;
    if (Plan[0].r0.x == _Data1_Generation && Plan[0].r0.x != 0u && Plan[0].r0.z == RP_PLAN_FORMAT) return;
    if (m == 0u) Plan[0].r0.w = RP_PLAN_FORMAT;   // the format this build of the pass wrote; plan_mark stamps it
    uint modes = gdtfTablesValid() ? min(gdtfSectionCount(GDTF_SECTION_MODES), RP_MODES) : 0u;
    if (m >= modes) return;
    uint4 m0 = gdtfMode(m, 0u), m1 = gdtfMode(m, 1u), m2 = gdtfMode(m, 2u);
    uint4 t0 = gdtfType(m2.w, 0u);
    uint geoFirst = t0.z, geoEnd = t0.z + t0.w;

    uint root = GDTF_NONE;
    [loop] for (uint c = m0.x; c < m0.x + m0.y && root == GDTF_NONE; c++)
    {
        uint4 r2 = gdtfChannel(c, 2u);
        if (r2.y == GDTF_NONE && r2.x != GDTF_NONE) root = topLevel(r2.x);
    }
    if (root == GDTF_NONE && m1.w > 0u) root = topLevel(gdtfCell(m1.z).x);
    [loop] for (uint g = geoFirst; g < geoEnd && root == GDTF_NONE; g++)
        if (gdtfGeometry(g, 0u).y == GDTF_NONE) root = g;

    uint base = rpPlanHeader(m) + 1u;
    uint n = 0u;
    bool dropped = false;
    uint end = root == GDTF_NONE ? root : subtreeEnd(root, geoEnd);
    uint direct = root == GDTF_NONE ? 0u : min(end - root, RP_ENTRIES);
    dropped = root != GDTF_NONE && end - root > RP_ENTRIES;
    [loop] for (uint k = 0u; k < direct; k++)
    {
        uint g = root + k;
        uint parent = gdtfGeometry(g, 0u).y;
        PlanRecord e;
        uint2 ax = axisChannel(m0, g, GDTF_NONE);
        e.r0 = uint4(g, k == 0u ? GDTF_NONE : parent - root, cellOfMode(m1, g), 0u);
        e.r1 = uint4(ax, 0u, 0u);
        Plan[base + k] = e;
    }
    n = direct;
    [loop] for (uint r = 0u; r < direct; r++)
    {
        uint4 g0 = gdtfGeometry(root + r, 0u);
        if (g0.x != GDTF_GEO_REFERENCE || g0.z == GDTF_NONE) continue;
        uint tmpl = g0.z, tEnd = subtreeEnd(tmpl, geoEnd), cell = cellOfMode(m1, root + r), first = n;
        [loop] for (uint g = tmpl; g < tEnd; g++)
        {
            if (n >= RP_ENTRIES) { dropped = true; break; }
            uint parent = gdtfGeometry(g, 0u).y;
            PlanRecord e;
            uint2 ax = axisChannel(m0, g, cell);
            e.r0 = uint4(g, g == tmpl ? r : first + (parent - tmpl), cell, g == tmpl ? RP_SKIP_OWN : 0u);
            e.r1 = uint4(ax, 0u, 0u);
            Plan[base + n] = e;
            n++;
        }
    }
    PlanRecord h;
    h.r0 = uint4(n, root, dropped ? 1u : 0u, 0u);
    h.r1 = uint4(geoFirst, geoEnd, 0u, 0u);
    Plan[rpPlanHeader(m)] = h;
}
