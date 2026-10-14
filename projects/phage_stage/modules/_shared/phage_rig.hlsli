// PHAGE's rig identity: how a Fixture Rig fixture maps back to PHAGE (Phage_Lighting's rig_inst reads it), and the show's
// fixture table every node reads. The plot's contract is tools/phage_mvr.py's:
//   movers and strobes   FixtureID = PHAGE slot + 1 (slots 0-127 movers, 128-175 strobes)
//   pixel battens        FixtureID = 10000 + run * 100 + unit, UnitNumber = unit (from 1), CustomId = where the unit
//                        starts on its run (mm)
// Any other fixture is a guest, the rig's own: it stays where the Fixture Rig puts it. The rig numbers a fixture added
// later after the highest FixtureID, inside the battens' range, so a batten must carry its unit as UnitNumber too.
#ifndef PHAGE_RIG_HLSLI
#define PHAGE_RIG_HLSLI

#define PH_RIG_MAX 1024u          // fixtures either side handles (the fixture engine's FE_N_MAX)
#define PH_RIG_UNIVERSES 64u      // DMX universes either side reads or writes

#define ROLE_NONE 0u
#define ROLE_MOVER 1u
#define ROLE_STROBE 2u
#define ROLE_BATTEN 3u

#define PH_RIG_MOVER_SLOTS 128u
#define PH_RIG_STROBE_SLOT0 128u
#define PH_RIG_STROBE_SLOTS 48u
#define PH_RIG_BAR_PIECES 12u

// One per Fixtures record (32 bytes). Active (a0 > 0): the type is renderable, its mode has an engine mode, and break
// 1 is patched inside the universes this project handles.
struct PhRigInst
{
    uint type; uint mode; uint fid; uint role;      // rig type, engine mode, FixtureID, ROLE_*
    uint u0; uint a0; uint index; uint custom;      // break 1 (universe 0-based, address 1-512), PHAGE slot or run, CustomId
};

bool phRigActive(PhRigInst d) { return d.a0 > 0u; }

// ---- The show's fixture table: Phage_Lighting builds it from the Fixture Rig every frame (rig_*.hlsl) and publishes
// it as Rig Fixtures (one record per Fixtures record) and Rig Slots (the record each PHAGE slot plays). Lighting's
// own passes (motors, optics, pixels, DMX) and Phage_Renderer read it, so a fixture added to, moved in or deleted from
// the rig is added, moved or deleted
// everywhere. A fixture the plot names (PH_FIX_PLOTTED) plays its own slot or run; any other (a guest) takes a free
// slot of its role: a type that pans and tilts plays a mover slot, a line of many cells near a pixel run joins that
// run, anything else plays a strobe slot. Each hangs from a truss mount (its own, or the nearest at rest within
// PH_RIG_ANCHOR_M) and rides it.
#define PH_FIX_ACTIVE 1u       // a renderable type with an engine mode for its GDTF mode
#define PH_FIX_PATCHED 2u      // break 1 inside the universes this project handles
#define PH_FIX_PLOTTED 4u      // the plot names it (FixtureID / UnitNumber, tools/phage_mvr.py)
#define PH_FIX_GUEST 8u        // added to the rig: plays a free slot or joins a run
#define PH_FIX_CARRIED 16u     // rides a truss mount or bar piece
#define PH_FIX_UNPLACED 32u    // a guest with no free slot of its role: drawn, not played
#define PH_FIX_NATIVE 64u      // its type is the one the plot uses for its role (Halo Beam, Linear Strobe, Pixel
                               // Batten): PHAGE's own conventions and models apply; any other type takes the generic
                               // GDTF paths (aim solved through its pan and tilt, drawn from its GDTF)
#define PH_RIG_NONE 0xFFFFu
#define PH_RIG_ANCHOR_M 2.5
#define PH_RIG_RUN_M 0.6       // a batten within this of a pixel run's piece joins the run

struct PhRigFix
{
    uint type; uint mode; uint role; uint slot;       // rig type, engine mode, ROLE_*, the PHAGE slot it plays (PH_RIG_NONE)
    uint run; uint custom; uint anchor; uint flags;   // pixel run (PH_RIG_NONE), start along the run (mm), mount slot, PH_FIX_*
    uint u0; uint a0; uint fid; uint unit;            // break 1 (universe 0-based, address 1-512 or 0), FixtureID, UnitNumber
    float4 x; float4 y; float4 z; float4 o;           // GDTF axes and origin where the truss carries it now (o.w 1: drawn)
    float4 rest;                                      // GDTF origin at rest (the rig's placement), w: shuffle hash
};
bool phFixActive(PhRigFix f) { return (f.flags & PH_FIX_ACTIVE) != 0u; }
bool phFixPatched(PhRigFix f) { return (f.flags & PH_FIX_PATCHED) != 0u; }

// What a PHAGE slot plays (Rig Slots): the Rig Fixtures record (or -1), its type, and the slot's pan and tilt limits in
// PHAGE degrees, from the type's GDTF ranges.
struct PhRigSlot { float4 info; float4 limits; };     // info: record, type, mode, flags

// The PHAGE fixture a FixtureID and UnitNumber name: its role and its slot (movers, strobes) or run (battens).
bool phRigIsBatten(uint fid, uint unit) { return fid >= 10000u && fid < 16400u && unit >= 1u && unit == fid % 100u; }

void phRigIdentity(uint fid, uint unit, inout PhRigInst d)
{
    d.role = ROLE_NONE;
    d.index = 0u;
    if (fid >= 1u && fid <= PH_RIG_MOVER_SLOTS) { d.role = ROLE_MOVER; d.index = fid - 1u; }
    else if (fid > PH_RIG_STROBE_SLOT0 && fid <= PH_RIG_STROBE_SLOT0 + PH_RIG_STROBE_SLOTS) { d.role = ROLE_STROBE; d.index = fid - 1u; }
    else if (phRigIsBatten(fid, unit)) { d.role = ROLE_BATTEN; d.index = (fid - 10000u) / 100u; }
}

#endif
