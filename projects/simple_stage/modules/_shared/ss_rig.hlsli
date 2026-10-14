// The stage's rig identity: how a Fixture Rig fixture maps back to a program slot (SS_Lighting's rig_inst reads it), and
// the show's fixture table every node reads. The plot's contract is tools/ss_stage.py's:
//   movers and strobes   FixtureID = slot + 1 (slots 0-31 movers, 32-47 strobes)
//   pixel battens        FixtureID = 10000 + run * 100 + unit, UnitNumber = unit (from 1), CustomId = where the unit
//                        starts on its run (mm)
// Any other fixture is a guest, the rig's own: it stays where the Fixture Rig puts it. The rig numbers a fixture added
// later after the highest FixtureID, inside the battens' range, so a batten must carry its unit as UnitNumber too.
#ifndef SS_RIG_HLSLI
#define SS_RIG_HLSLI

#define SS_RIG_MAX 1024u          // fixtures either side handles (the fixture engine's FE_N_MAX)
#define SS_RIG_UNIVERSES 64u      // DMX universes either side reads or writes

#define ROLE_NONE 0u
#define ROLE_MOVER 1u
#define ROLE_STROBE 2u
#define ROLE_BATTEN 3u

#include "../_shared/ss_layout.hlsli"
#define SS_RIG_MOVER_SLOTS ((uint)SS_MOVERS)
#define SS_RIG_STROBE_SLOT0 ((uint)SS_STROBE0)
#define SS_RIG_STROBE_SLOTS ((uint)SS_STROBES)
#define SS_RIG_BAR_PIECES ((uint)SS_BAR_SEGS)

// One per Fixtures record (32 bytes). Active (a0 > 0): the type is renderable, its mode has an engine mode, and break
// 1 is patched inside the universes this project handles.
struct SsRigInst
{
    uint type; uint mode; uint fid; uint role;      // rig type, engine mode, FixtureID, ROLE_*
    uint u0; uint a0; uint index; uint custom;      // break 1 (universe 0-based, address 1-512), PHAGE slot or run, CustomId
};

bool ssRigActive(SsRigInst d) { return d.a0 > 0u; }

// ---- The show's fixture table: SS_Lighting builds it from the Fixture Rig every frame (rig_*.hlsl) and publishes
// it as Rig Fixtures (one record per Fixtures record) and Rig Slots (the record each PHAGE slot plays). Lighting's
// own passes (motors, optics, pixels, DMX) and SS_Renderer read it, so a fixture added to, moved in or deleted from
// the rig is added, moved or deleted
// everywhere. A fixture the plot names (SS_FIX_PLOTTED) plays its own slot or run; any other (a guest) takes a free
// slot of its role: a type that pans and tilts plays a mover slot, a line of many cells near a pixel run joins that
// run, anything else plays a strobe slot. Each hangs from a truss mount (its own, or the nearest at rest within
// SS_RIG_ANCHOR_M) and rides it.
#define SS_FIX_ACTIVE 1u       // a renderable type with an engine mode for its GDTF mode
#define SS_FIX_PATCHED 2u      // break 1 inside the universes this project handles
#define SS_FIX_PLOTTED 4u      // the plot names it (FixtureID / UnitNumber, tools/ss_mvr.py)
#define SS_FIX_GUEST 8u        // added to the rig: plays a free slot or joins a run
#define SS_FIX_CARRIED 16u     // rides a truss mount or bar piece
#define SS_FIX_UNPLACED 32u    // a guest with no free slot of its role: drawn, not played
#define SS_FIX_NATIVE 64u      // its type is the one the plot uses for its role (Halo Beam, Linear Strobe, Pixel
                               // Batten): PHAGE's own conventions and models apply; any other type takes the generic
                               // GDTF paths (aim solved through its pan and tilt, drawn from its GDTF)
#define SS_RIG_NONE 0xFFFFu
#define SS_RIG_ANCHOR_M 2.5
#define SS_RIG_RUN_M 0.6       // a batten within this of a pixel run's piece joins the run

struct SsRigFix
{
    uint type; uint mode; uint role; uint slot;       // rig type, engine mode, ROLE_*, the PHAGE slot it plays (SS_RIG_NONE)
    uint run; uint custom; uint anchor; uint flags;   // pixel run (SS_RIG_NONE), start along the run (mm), mount slot, SS_FIX_*
    uint u0; uint a0; uint fid; uint unit;            // break 1 (universe 0-based, address 1-512 or 0), FixtureID, UnitNumber
    float4 x; float4 y; float4 z; float4 o;           // GDTF axes and origin where the truss carries it now (o.w 1: drawn)
    float4 rest;                                      // GDTF origin at rest (the rig's placement), w: shuffle hash
};
bool ssFixActive(SsRigFix f) { return (f.flags & SS_FIX_ACTIVE) != 0u; }
bool ssFixPatched(SsRigFix f) { return (f.flags & SS_FIX_PATCHED) != 0u; }

// What a PHAGE slot plays (Rig Slots): the Rig Fixtures record (or -1), its type, and the slot's pan and tilt limits in
// PHAGE degrees, from the type's GDTF ranges.
struct SsRigSlot { float4 info; float4 limits; };     // info: record, type, mode, flags

// The PHAGE fixture a FixtureID and UnitNumber name: its role and its slot (movers, strobes) or run (battens).
bool ssRigIsBatten(uint fid, uint unit) { return fid >= 10000u && fid < 10000u + 100u * (uint)SS_BARS && unit >= 1u && unit == fid % 100u; }
// The shuffle rank of a record (the mounts carry their own, tools/ss_stage.py).
float ssHash1(float x) { return frac(sin(x * 12.9898 + 4.1414) * 43758.5453); }

void ssRigIdentity(uint fid, uint unit, inout SsRigInst d)
{
    d.role = ROLE_NONE;
    d.index = 0u;
    if (fid >= 1u && fid <= SS_RIG_MOVER_SLOTS) { d.role = ROLE_MOVER; d.index = fid - 1u; }
    else if (fid > SS_RIG_STROBE_SLOT0 && fid <= SS_RIG_STROBE_SLOT0 + SS_RIG_STROBE_SLOTS) { d.role = ROLE_STROBE; d.index = fid - 1u; }
    else if (ssRigIsBatten(fid, unit)) { d.role = ROLE_BATTEN; d.index = (fid - 10000u) / 100u; }
}

#endif
