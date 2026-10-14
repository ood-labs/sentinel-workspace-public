// SS_Lighting / dmx_inst - one thread per Fixture Rig record, from the fixture table (rig_out.hlsl): its type and
// engine mode, its first break, and what it plays: the mover or strobe slot (PHAGE's own, or the free slot a guest took)
// or the pixel run. A record with no slot or run, or no patch inside the 64 universes, is not encoded. `custom` is the
// start along the run (mm) for a batten, and for a mover or strobe 1 when its type is the plot's own (native), else 0.
#define GDTF_RENDER _Data5
#include "../_shared/fe_tables.hlsli"
#include "dmx_common.hlsli"

StructuredBuffer<SsRigFix> RigFix : register(t0);
RWStructuredBuffer<DmxInst> Inst : register(u0);

[numthreads(64, 1, 1)]
void main(uint3 id : SV_DispatchThreadID)
{
    uint i = id.x;
    if (i >= INST_MAX) return;
    DmxInst d = (DmxInst)0;
    SsRigFix f = RigFix[i];
    bool plays = (f.role == ROLE_BATTEN && f.run < 64u) || ((f.role == ROLE_MOVER || f.role == ROLE_STROBE) && f.slot < SS_STROBE_SLOT0 + SS_STROBE_SLOTS);
    if (frTablesValid() && ssFixActive(f) && ssFixPatched(f) && plays)
    {
        d.type = f.type;
        d.mode = f.mode;
        d.role = f.role;
        d.u0 = f.u0;
        d.a0 = f.a0;
        d.fid = f.fid;
        d.index = f.role == ROLE_BATTEN ? f.run : f.slot;
        d.custom = f.role == ROLE_BATTEN ? f.custom : ((f.flags & SS_FIX_NATIVE) != 0u ? 1u : 0u);
    }
    Inst[i] = d;
}
