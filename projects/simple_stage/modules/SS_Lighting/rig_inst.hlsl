// SS_Lighting / rig_inst - one thread per Fixture Rig record: what it is to the show (_shared/ss_rig.hlsli).
//   type, mode   through the FixtureRender tables (Fixtures data input 4, FixtureRender data input 5)
//   role         a type that pans and tilts is a mover; a line of 8 or more cells within SS_RIG_RUN_M of a pixel run's
//                piece (Bar Pieces, data input 3) is a batten on that run; anything else plays like a strobe
//   slot / run   the plot's identity (FixtureID, UnitNumber, CustomId) for the stage's own fixtures; rig_assign gives
//                every other fixture a free slot of its role
//   frame        the record's GDTF axes and origin, exactly where the rig puts it: the trusses never move, so
//                nothing carries a fixture. A guest mover or strobe notes the nearest mount within SS_RIG_ANCHOR_M,
//                whose group it joins in the chase orders (rig_mounts).
#define GDTF_RENDER _Data5
#include "../_shared/fe_tables.hlsli"
#include "lighting.hlsli"
#include "../_shared/ss_rig.hlsli"

RWStructuredBuffer<SsRigFix> Fix:register(u0);

bool liveMount(uint s){return s<_Data0_Count&&_Data0[s].active>.5;}
float3 nearestOnSegment(float3 p,float3 a,float3 c){float3 ac=c-a;return a+ac*saturate(dot(p-a,ac)/max(dot(ac,ac),1e-8));}

// A line of 8 or more cells (a pixel batten's layout).
bool lineType(uint t){
 bool found=false;uint me=feMaxEmitters();
 for(uint e=0;e<me;e++){uint4 em=FE_EMITTER_AT(t*me+e);found=found||(em.x!=0u&&(em.z&255u)==FE_LAYOUT_LINE&&em.w>=8u);}
 return found;}

[numthreads(64,1,1)]void main(uint3 id:SV_DispatchThreadID){
 uint k=id.x;if(k>=SS_RIG_MAX)return;
 SsRigFix f=(SsRigFix)0;f.slot=SS_RIG_NONE;f.run=SS_RIG_NONE;f.anchor=SS_RIG_NONE;
 if(k<_Data4_Count&&_Data4[k].origin.w>.5&&frTablesValid()){
  uint t=_Data4[k].ids[0];uint m=t<frTypeCount()?frEngineMode(t,_Data4[k].ids[1]):0xFFFFFFFFu;
  if(m!=0xFFFFFFFFu&&frTypeStatus(t)==FR_STATUS_RENDERABLE){
   f.type=t;f.mode=m;f.flags=SS_FIX_ACTIVE;
   uint u=_Data4[k].dmx01[0],a=_Data4[k].dmx01[1];
   if(u>=1u&&u<=SS_RIG_UNIVERSES&&a>=1u&&a<=512u){f.u0=u-1u;f.a0=a;f.flags|=SS_FIX_PATCHED;}
   f.fid=_Data4[k].ids[2];f.unit=_Data4[k].ids[3];f.custom=_Data4[k].meta[3];
   f.x=float4(_Data4[k].axis_x.xyz,0);f.y=float4(_Data4[k].axis_y.xyz,0);f.z=float4(_Data4[k].axis_z.xyz,0);
   f.o=float4(_Data4[k].origin.xyz,1);f.rest=float4(f.o.xyz,ssHash1((float)k*1.618+.37));
   // The plot's identity (_shared/ss_rig.hlsli ssRigIdentity) names the stage's own fixtures.
   SsRigInst id0=(SsRigInst)0;ssRigIdentity(f.fid,f.unit,id0);
   bool pans=FE_PANTILT_AT(t).x!=FE_SLOT_NONE;
   if(id0.role!=ROLE_NONE){
    f.flags|=SS_FIX_PLOTTED;f.role=id0.role;
    if(id0.role==ROLE_BATTEN)f.run=id0.index;else{f.slot=id0.index;f.anchor=id0.index;}
   }else{
    f.flags|=SS_FIX_GUEST;f.role=pans?ROLE_MOVER:ROLE_STROBE;
    // A line of cells near a pixel run's piece joins that run, where it sits along it.
    if(!pans&&lineType(t)){
     float best=SS_RIG_RUN_M;uint pieces=min(_Data3_Count,(uint)(SS_BARS*SS_BAR_SEGS));
     for(uint q=0;q<pieces;q++){if(_Data3[q].w.z<.5)continue;
      float3 pa=_Data3[q].a.xyz,pc=_Data3[q].b.xyz,c=nearestOnSegment(f.o.xyz,pa,pc);float d=length(c-f.o.xyz);
      if(d<best){uint b=q/SS_BAR_SEGS,j=q%SS_BAR_SEGS;float before=0;
       for(uint i=0;i<j;i++)before+=_Data3[b*SS_BAR_SEGS+i].w.x;
       best=d;f.run=b;f.custom=(uint)max(0.0,round((before+length(c-pa)-.5)*1000.0));}}
     if(f.run!=SS_RIG_NONE)f.role=ROLE_BATTEN;
    }
    // A guest mover or strobe notes the nearest mount: it joins that mount's group.
    if(f.role!=ROLE_BATTEN){float best=SS_RIG_ANCHOR_M;
     for(uint s=0;s<SS_SLOTS;s++){if(liveMount(s)){float d=length(_Data0[s].rest.xyz-f.o.xyz);if(d<best){best=d;f.anchor=s;}}}}
   }
  }
 }
 Fix[k]=f;
}
