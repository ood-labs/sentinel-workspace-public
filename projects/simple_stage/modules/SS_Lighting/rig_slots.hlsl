// SS_Lighting / rig_slots - what each PHAGE slot plays (Rig Slots): the Rig Fixtures record, its type, mode and flags,
// and the slot's pan and tilt limits in PHAGE degrees, read from the type's GDTF: the physical span of the channel
// that drives its pan and tilt in its mode (PHAGE pan is the GDTF's negated, PHAGE tilt the GDTF's plus 90,
// ss_fixture.hlsli). A head of another type (not native) is aimed through its own GDTF by dmx_state
// (_shared/ss_aim.hlsli), which keeps it inside its ranges, so Lighting leaves its aim unclamped. A slot with no
// fixture keeps PHAGE's own head range.
#define GDTF_RENDER _Data5
#include "../_shared/fe_tables.hlsli"
#include "../_shared/fe_rig.hlsli"
#include "lighting.hlsli"
#include "../_shared/ss_rig.hlsli"
#include "../_shared/ss_aim.hlsli"

StructuredBuffer<SsRigFix> Fix:register(t0);
StructuredBuffer<uint> Map:register(t1);
RWStructuredBuffer<SsRigSlot> Out:register(u0);


[numthreads(64,1,1)]void main(uint3 id:SV_DispatchThreadID){
 uint s=id.x;if(s>=SS_SLOTS)return;
 SsRigSlot o;o.info=float4(-1,0,0,0);o.limits=float4(-270,270,SS_TILT_MIN,SS_TILT_MAX);
 uint k=s<SS_BAR0?Map[s]:0u;
 if(k>0u&&frTablesValid()){SsRigFix f=Fix[k-1u];
  o.info=float4(k-1u,f.type,f.mode,f.flags);
  if((f.flags&SS_FIX_NATIVE)!=0u){uint2 pt=FE_PANTILT_AT(f.type);float2 r;
   if(pt.x!=FE_SLOT_NONE&&ssAxisRange(f.mode,pt.x,r)){o.limits.x=-r.y;o.limits.y=-r.x;}
   if(pt.y!=FE_SLOT_NONE&&ssAxisRange(f.mode,pt.y,r)){o.limits.z=r.x+90;o.limits.w=r.y+90;}}
  else o.limits=float4(-720,720,-720,720);
 }
 Out[s]=o;
}
