// Phage_Renderer / vis_common - what every pass shares: the rig instance (../_shared/phage_rig.hlsli), the live frame each
// fixture is drawn in, and reading a fixture's decoded state by attribute kind, emitter and cell through the
// FixtureRender tables (so any mode of any type reads the same way).
#ifndef PHAGE_VIS_COMMON_HLSLI
#define PHAGE_VIS_COMMON_HLSLI
#include "../_shared/phage_rig.hlsli"

// A fixture's GDTF axes and origin in the stage, where the truss has carried it now; o.w is 1 when it is drawn.
struct VisFrame { float4 x; float4 y; float4 z; float4 o; };

#define VIS_ANY_EMITTER 255u

// Guests: the rig's fixtures PHAGE's own models do not draw (a type other than the plot's own, or one with no slot or
// run to play), drawn from their GDTFs by the renderer's generic passes (guests.hlsl lists them, gframe.hlsl poses and
// lights them). Which slot each fixture plays is the show's fixture table's (Phage_Lighting Rig Fixtures).
#define VIS_GUESTS 64u
#define VIS_GFRAME_STRIDE 134u     // fe_render.hlsli's FE_FRAME_STRIDE: 6 pose rows, then 128 cells of radiance
#define VIS_GSOURCE0 3248u         // guest sources follow Lighting's Optics layout (PH_OPT_COUNT records)

// Emission cells of emitter e of type t.
uint visEmitterCells(uint t, uint e)
{
    uint4 em = FE_EMITTER_AT(t * feMaxEmitters() + e);
    return em.x == 0u ? 0u : max((em.z >> 8) & 255u, 1u) * max((em.z >> 16) & 255u, 1u);
}

// The first emitter of type t whose cell count is single (want 1) or many (want 2), or 255.
uint visEmitter(uint t, uint want)
{
    uint found = VIS_ANY_EMITTER;
    for (uint e = 0u; e < feMaxEmitters(); e++)
    {
        uint n = visEmitterCells(t, e);
        bool hit = found == VIS_ANY_EMITTER && n > 0u && (want == 1u ? n == 1u : n > 1u);
        found = hit ? e : found;
    }
    return found;
}

// The first emitter of type t with colour system `colour` (FE_COLOUR_*), or 255.
uint visEmitterColour(uint t, uint colour)
{
    uint found = VIS_ANY_EMITTER;
    for (uint e = 0u; e < feMaxEmitters(); e++)
    {
        uint4 em = FE_EMITTER_AT(t * feMaxEmitters() + e);
        bool hit = found == VIS_ANY_EMITTER && em.x != 0u && em.y == colour;
        found = hit ? e : found;
    }
    return found;
}

// The attribute row (slot base, cells, kind, emitter) of `kind` bound to `emitter` (255: any), first match.
bool visAttr(uint t, uint kind, uint emitter, out uint4 row)
{
    row = uint4(0u, 0u, 0u, 0u);
    bool found = false;
    uint4 ti = FE_TYPE_INFO_AT(t);
    for (uint a = 0u; a < FE_TYPE_ATTRN_AT(t); a++)
    {
        uint4 x = FE_ATTR_AT(ti.w + a);
        bool hit = !found && x.z == kind && (emitter == VIS_ANY_EMITTER || x.w == emitter);
        row = hit ? x : row;
        found = found || hit;
    }
    return found;
}

#endif
