// SS_Lighting / rig_mounts - the mounts every Lighting pass (the pixel bars too) plays, from the rig: a mover or strobe slot
// is active only while a Fixture Rig record plays it, and sits where that record is now (its carried GDTF frame in
// PHAGE's mount convention: a mover's up is -Z and fwd +Y, a strobe's up +X and fwd -Z, its face 0.135 m in front of
// the plot's housing origin). A PHAGE fixture keeps its slot's family, leg and chase ranks, its rest moving with it if
// the rig moved it; a guest takes the family of its role's guests and the leg of the mount it hangs from. A pixel run is
// active while the rig has a batten on it; the axes are Kinetics' own.
#include "lighting.hlsli"
#include "../_shared/ss_rig.hlsli"

StructuredBuffer<SsRigFix> Fix:register(t0);
StructuredBuffer<uint> Map:register(t1);
RWStructuredBuffer<SsMount> Out:register(u0);

#define GUEST_MOVERS 2
#define GUEST_STROBES 12

[numthreads(64,1,1)]void main(uint3 id:SV_DispatchThreadID){
 uint s=id.x;if(s>=SS_SLOTS)return;
 SsMount m=(SsMount)0;
 SsMount kin=(SsMount)0;
 if(s<_Data0_Count){kin.position=_Data0[s].position;kin.fixture_id=_Data0[s].fixture_id;kin.up=_Data0[s].up;kin.kind=_Data0[s].kind;
  kin.fwd=_Data0[s].fwd;kin.active=_Data0[s].active;kin.extra=_Data0[s].extra;kin.rest=_Data0[s].rest;}
 if(s<SS_BAR0){
  uint k=Map[s];
  if(k>0u){SsRigFix f=Fix[k-1u];bool mover=s<SS_STROBE0;
   bool plotted=(f.flags&SS_FIX_PLOTTED)!=0u;
   m.kind=mover?0:1;m.fixture_id=s;m.active=1;
   m.up=mover?-f.z.xyz:f.x.xyz;m.fwd=mover?f.y.xyz:-f.z.xyz;
   float face=(!mover&&plotted)?.135:0;
   m.position=f.o.xyz+m.fwd*face;
   float3 restPos=f.rest.xyz+(mover?0:-normalize(f.z.xyz)*face);
   if(plotted&&kin.active>.5){m.extra=kin.extra;m.rest=kin.rest;if(length(f.rest.xyz-kin.rest.xyz)>.02+face)m.rest.xyz=restPos;}
   else{uint a=f.anchor;float leg=-1,part=0;
    if(a!=SS_RIG_NONE&&a<_Data0_Count){leg=_Data0[a].extra.z;part=_Data0[a].extra.w;}
    m.extra=float4(mover?GUEST_MOVERS:GUEST_STROBES,s,leg,part);m.rest=float4(restPos,f.rest.w);}
  }
 }else if(s<SS_AXIS0){
  m=kin;uint b=s-SS_BAR0;uint n=0;
  for(uint k=0;k<SS_RIG_MAX;k++){SsRigFix f=Fix[k];n+=(ssFixActive(f)&&f.role==ROLE_BATTEN&&f.run==b)?1u:0u;}
  m.active=(kin.active>.5&&n>0u)?1:0;
 }else m=kin;
 Out[s]=m;
}
