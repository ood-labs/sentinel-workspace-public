// Phage_Lighting / rig_inst - one thread per Fixture Rig record: what it is to the show (_shared/phage_rig.hlsli).
//   type, mode   through the FixtureRender tables (Fixtures data input 5, FixtureRender data input 6)
//   role         a type that pans and tilts is a mover; a line of 8 or more cells within PH_RIG_RUN_M of a pixel run's
//                piece is a batten on that run; anything else plays like a strobe
//   slot / run   the plot's identity (FixtureID, UnitNumber, CustomId) for PHAGE's own fixtures; rig_assign gives
//                every other fixture a free slot of its role
//   frame        the record's GDTF axes and origin, read in the rest frame of the mount it hangs from (its own slot's,
//                its run's piece under its middle, or for a guest the nearest mount at rest within PH_RIG_ANCHOR_M) and
//                set in that mount's live frame (Kinetics' Mounts and Bar Pieces), so the truss carries it; a fixture
//                with nothing to hang from stays where the rig puts it.
#define GDTF_RENDER _Data6
#include "../_shared/fe_tables.hlsli"
#include "lighting.hlsli"
#include "../_shared/phage_rig.hlsli"
float4 phD(uint i){return _Data3[i].value;}
#include "../_shared/phage_anatomy.hlsli"

RWStructuredBuffer<PhRigFix> Fix:register(u0);

struct Basis{float3 e1;float3 e2;float3 e3;float3 o;};
Basis mountBasis(float3 p,float3 up,float3 fwd){Basis b;b.e3=normalize(fwd);b.e2=normalize(up-b.e3*dot(up,b.e3));b.e1=cross(b.e2,b.e3);b.o=p;return b;}
Basis pieceBasis(float3 a,float3 c,float3 n){Basis b;b.e1=normalize(c-a);b.e3=normalize(n-b.e1*dot(n,b.e1));b.e2=cross(b.e3,b.e1);b.o=a;return b;}
float3 toLocal(Basis b,float3 v){return float3(dot(v,b.e1),dot(v,b.e2),dot(v,b.e3));}
float3 toWorld(Basis b,float3 v){return b.e1*v.x+b.e2*v.y+b.e3*v.z;}
void carry(inout PhRigFix f,Basis rest,Basis live){
 f.x.xyz=toWorld(live,toLocal(rest,f.x.xyz));f.y.xyz=toWorld(live,toLocal(rest,f.y.xyz));f.z.xyz=toWorld(live,toLocal(rest,f.z.xyz));
 f.o.xyz=live.o+toWorld(live,toLocal(rest,f.o.xyz-rest.o));f.flags|=PH_FIX_CARRIED;}
bool liveMount(uint s){return s<_Data0_Count&&_Data0[s].active>.5;}
Basis liveBasis(uint s){return mountBasis(_Data0[s].position,_Data0[s].up,_Data0[s].fwd);}
float3 nearestOnSegment(float3 p,float3 a,float3 c){float3 ac=c-a;return a+ac*saturate(dot(p-a,ac)/max(dot(ac,ac),1e-8));}

// A line of 8 or more cells (a pixel batten's layout).
bool lineType(uint t){
 bool found=false;uint me=feMaxEmitters();
 for(uint e=0;e<me;e++){uint4 em=FE_EMITTER_AT(t*me+e);found=found||(em.x!=0u&&(em.z&255u)==FE_LAYOUT_LINE&&em.w>=8u);}
 return found;}

[numthreads(64,1,1)]void main(uint3 id:SV_DispatchThreadID){
 uint k=id.x;if(k>=PH_RIG_MAX)return;
 PhRigFix f=(PhRigFix)0;f.slot=PH_RIG_NONE;f.run=PH_RIG_NONE;f.anchor=PH_RIG_NONE;
 if(k<_Data5_Count&&_Data5[k].origin.w>.5&&frTablesValid()){
  uint t=_Data5[k].ids[0];uint m=t<frTypeCount()?frEngineMode(t,_Data5[k].ids[1]):0xFFFFFFFFu;
  if(m!=0xFFFFFFFFu&&frTypeStatus(t)==FR_STATUS_RENDERABLE){
   f.type=t;f.mode=m;f.flags=PH_FIX_ACTIVE;
   uint u=_Data5[k].dmx01[0],a=_Data5[k].dmx01[1];
   if(u>=1u&&u<=PH_RIG_UNIVERSES&&a>=1u&&a<=512u){f.u0=u-1u;f.a0=a;f.flags|=PH_FIX_PATCHED;}
   f.fid=_Data5[k].ids[2];f.unit=_Data5[k].ids[3];f.custom=_Data5[k].meta[3];
   f.x=float4(_Data5[k].axis_x.xyz,0);f.y=float4(_Data5[k].axis_y.xyz,0);f.z=float4(_Data5[k].axis_z.xyz,0);
   f.o=float4(_Data5[k].origin.xyz,1);f.rest=float4(f.o.xyz,phHash1((float)k*1.618+.37));
   bool design=_Data3_Count>=16u;PhDesign D=phLoad();
   // The plot's identity (_shared/phage_rig.hlsli phRigIdentity) names PHAGE's own fixtures.
   PhRigInst id0=(PhRigInst)0;phRigIdentity(f.fid,f.unit,id0);
   bool pans=FE_PANTILT_AT(t).x!=FE_SLOT_NONE;
   if(id0.role!=ROLE_NONE){
    f.flags|=PH_FIX_PLOTTED;f.role=id0.role;
    if(id0.role==ROLE_BATTEN)f.run=id0.index;else{f.slot=id0.index;f.anchor=id0.index;}
   }else{
    f.flags|=PH_FIX_GUEST;f.role=pans?ROLE_MOVER:ROLE_STROBE;
    // A line of cells near a pixel run's piece (at rest) joins that run, where it sits along it.
    if(!pans&&design&&lineType(t)){
     float best=PH_RIG_RUN_M;
     for(uint b=0;b<PH_BARS;b++){float before=0;
      for(uint j=0;j<phBarSegCount(b);j++){float3 pa,pc,pn;phBarPiece(D,phRest(),b,j,pa,pc,pn);
       float3 q=nearestOnSegment(f.o.xyz,pa,pc);float d=length(q-f.o.xyz);
       if(d<best){best=d;f.run=b;f.custom=(uint)max(0.0,round((before+length(q-pa)-.5)*1000.0));}
       before+=length(pc-pa);}}
     if(f.run!=PH_RIG_NONE)f.role=ROLE_BATTEN;
    }
    // A guest mover or strobe hangs from the nearest mount at rest.
    if(f.role!=ROLE_BATTEN){float best=PH_RIG_ANCHOR_M;
     for(uint s=0;s<PH_SLOTS;s++){if(liveMount(s)){float d=length(_Data0[s].rest.xyz-f.o.xyz);if(d<best){best=d;f.anchor=s;}}}}
   }
   // Ride the truss.
   if(design&&f.role==ROLE_BATTEN&&f.run!=PH_RIG_NONE){
    float mid=(float)f.custom/1000.0+.5,before=0;uint piece=PH_RIG_NONE;float3 ra=0,rc=0,rn=0;
    for(uint j=0;j<phBarSegCount(f.run);j++){float3 a2,c2,n2;phBarPiece(D,phRest(),f.run,j,a2,c2,n2);float len=length(c2-a2);
     bool hit=piece==PH_RIG_NONE&&mid<before+len;piece=hit?j:piece;ra=hit?a2:ra;rc=hit?c2:rc;rn=hit?n2:rn;before+=len;}
    uint q=f.run*PH_RIG_BAR_PIECES+piece;
    if(piece!=PH_RIG_NONE&&q<_Data4_Count&&_Data4[q].w.z>.5)carry(f,pieceBasis(ra,rc,rn),pieceBasis(_Data4[q].a.xyz,_Data4[q].b.xyz,_Data4[q].n.xyz));
   }else if(design&&f.anchor!=PH_RIG_NONE&&liveMount(f.anchor)){
    PhMount r=phMountAt(D,phRest(),f.anchor);carry(f,mountBasis(r.position,r.up,r.fwd),liveBasis(f.anchor));
   }
  }
 }
 Fix[k]=f;
}
