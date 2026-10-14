// SS_Renderer / vis_inst - one thread per Fixture Rig record, as the show's fixture table has it (SS_Lighting's Rig
// Fixtures, built from the rig every frame): its rig type and engine mode, its first break, and how it is drawn. A
// fixture of the plot's own type playing a slot or run (native) is drawn by PHAGE's models: role and index name the
// mover or strobe slot, or the pixel run with its start (custom, mm). Every other fixture is a guest (role NONE),
// drawn from its GDTF by the generic passes, whatever slot it plays.
#define GDTF_RENDER _Data6
#include "../_shared/fe_tables.hlsli"
#include "../_shared/ss_rig.hlsli"

RWStructuredBuffer<SsRigInst> Inst : register(u0);

[numthreads(64, 1, 1)]
void main(uint3 id : SV_DispatchThreadID)
{
    uint i = id.x;
    if (i >= SS_RIG_MAX) return;
    SsRigInst d = (SsRigInst)0;
    if (i < _Data1_Count && frTablesValid())
    {
        uint flags = _Data1[i].run[3];
        if ((flags & SS_FIX_ACTIVE) != 0u && (flags & SS_FIX_PATCHED) != 0u)
        {
            uint role = _Data1[i].ids[2], slot = _Data1[i].ids[3], run = _Data1[i].run[0];
            bool native = (flags & SS_FIX_NATIVE) != 0u;
            d.type = _Data1[i].ids[0];
            d.mode = _Data1[i].ids[1];
            d.fid = _Data1[i].patch[2];
            d.u0 = _Data1[i].patch[0];
            d.a0 = _Data1[i].patch[1];
            d.custom = _Data1[i].run[1];
            bool slotted = (role == ROLE_MOVER || role == ROLE_STROBE) && slot < SS_RIG_STROBE_SLOT0 + SS_RIG_STROBE_SLOTS;
            bool onRun = role == ROLE_BATTEN && run < 64u;
            d.role = native && (slotted || onRun) ? role : ROLE_NONE;
            d.index = role == ROLE_BATTEN ? run : slot;
        }
    }
    Inst[i] = d;
}
