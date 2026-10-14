// Phage_Lighting / DMX common - the instance record every pass shares, and how a Fixture Rig fixture maps back to PHAGE.
//
// The identity contract is tools/phage_mvr.py's: FixtureID = PHAGE slot + 1 for movers (slots 0-127) and strobes
// (128-175); FixtureID = 10000 + run * 100 + unit for pixel battens, whose UnitNumber is the unit and whose CustomId is
// where the unit starts along its run in millimetres (a fixture added later is numbered inside that range, so the
// UnitNumber tells them apart). A fixture outside that contract (a guest, one dropped onto the rig later) plays as the PHAGE
// mover nearest it: that mover's level and colour, everything else at its GDTF defaults.
#ifndef PHAGE_DMX_COMMON_HLSLI
#define PHAGE_DMX_COMMON_HLSLI

#define DMX_RECORDS 73u          // header, 8 metadata records, 64 universes (the rig uses 57)
#define DMX_UNIVERSES 64u
#define INST_MAX 1024u           // FE_N_MAX: the encoder's fixture capacity

#include "../_shared/phage_rig.hlsli"   // ROLE_*, PH_FIX_*: the show's fixture table (Phage_Lighting Rig Fixtures)

#define PH_MOVER_SLOTS 128u
#define PH_STROBE_SLOT0 128u
#define PH_STROBE_SLOTS 48u
#define PH_OPT_PER 25u
#define PH_OPT_STROBE0 3200u
#define BAR_PIECES 12u

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
