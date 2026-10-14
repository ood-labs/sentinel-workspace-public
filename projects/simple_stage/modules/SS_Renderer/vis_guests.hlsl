// SS_Renderer / vis_guests - the fixtures the renderer draws from their GDTFs: every active rig fixture PHAGE's models do not
// draw (inst.hlsl's role NONE: a type other than the plot's own, or one with no slot or run to play). List[0] is the
// count, then up to VIS_GUESTS rig records in rig order, so a guest keeps its place while others come and go after it.
#define GDTF_RENDER _Data6
#include "../_shared/fe_tables.hlsli"
#include "vis_common.hlsli"

StructuredBuffer<SsRigInst> Inst : register(t0);
RWStructuredBuffer<uint> List : register(u0);

[numthreads(1, 1, 1)]
void main()
{
    uint n = 0u;
    for (uint j = 0u; j < SS_RIG_MAX; j++)
    {
        SsRigInst d = Inst[j];
        bool generic = ssRigActive(d) && d.role == ROLE_NONE && n < VIS_GUESTS;
        if (generic) List[1u + n] = j;
        n += generic ? 1u : 0u;
    }
    List[0] = n;
}
