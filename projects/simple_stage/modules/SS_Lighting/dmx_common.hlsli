// SS_Lighting / DMX common - the instance record every pass shares, and how a Fixture Rig fixture maps back to PHAGE.
//
// The identity contract is tools/ss_stage.py's: FixtureID = slot + 1 for movers and strobes (the slot ranges are
// tools/ss_layout.py's); FixtureID = 10000 + run * 100 + unit for pixel battens, whose UnitNumber is the unit and whose
// CustomId is where the unit starts along its run in millimetres (a fixture added later is numbered inside that range, so
// the UnitNumber tells them apart). A fixture outside that contract (a guest, one dropped onto the rig later) plays a
// free slot of its role (ss_rig.hlsli).
#ifndef SS_DMX_COMMON_HLSLI
#define SS_DMX_COMMON_HLSLI

#define DMX_RECORDS 73u          // header, 8 metadata records, 64 universes (the rig uses 2)
#define DMX_UNIVERSES 64u
#define INST_MAX 1024u           // FE_N_MAX: the encoder's fixture capacity

#include "../_shared/ss_rig.hlsli"   // ROLE_*, SS_FIX_*: the show's fixture table (SS_Lighting Rig Fixtures)

// Slot ranges and the Optics layout come from the stage's layout (ss_layout.hlsli, through ss_rig.hlsli): never a literal.
#define SS_MOVER_SLOTS ((uint)SS_MOVERS)
#define SS_STROBE_SLOT0 ((uint)SS_STROBE0)
#define SS_STROBE_SLOTS ((uint)SS_STROBES)
#define BAR_PIECES ((uint)SS_BAR_SEGS)

// One per Fixtures record (32 bytes). active: the type is renderable, its mode has an engine mode, break 1 is patched
// inside the 64 universes this node sends, and the fixture table gives it a slot or run (inst.hlsl).
#define DMX_NATIVE(d) ((d).custom != 0u)   // a mover or strobe of the plot's own type
struct DmxInst
{
    uint type; uint mode; uint fid; uint role;      // rig type, engine mode, FixtureID, ROLE_*
    uint u0; uint a0; uint index; uint custom;      // break 1 (universe 0-based, address 1-512), PHAGE slot or run, CustomId
};

bool dmxActive(DmxInst d) { return d.a0 > 0u; }

#endif
