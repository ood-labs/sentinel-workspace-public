// Atmosphere and surface sources: per mover a narrow beam + its ring glow (averaged),
// per strobe a wide tube flash + a coloured plate wash, then one per guest (vis_optics after its SS_OPT_COUNT
// records). padding.x: 0 beam, 1 ring, 2 strobe, 3 narrow guest, 4 wide guest.
#include "../_shared/ss_fixture.hlsli"
StructuredBuffer<SsOptical> Optics:register(t0);
RWStructuredBuffer<SsOptical> Sources:register(u0);
#define MOVERS SS_MOVERS
#define STROBES SS_STROBES
#define GUESTS 64
#define GUEST0 SS_OPT_COUNT
[numthreads(64,1,1)]void main(uint3 tid:SV_DispatchThreadID){
 uint i=tid.x;if(i>=MOVERS*2+STROBES*2+GUESTS)return;SsOptical o=(SsOptical)0;
 if(i>=MOVERS*2+STROBES*2){uint g=GUEST0+i-MOVERS*2-STROBES*2;if(g<SS_OPT_COUNT+GUESTS)o=Optics[g];Sources[i]=o;return;}
 if(i<MOVERS*2){uint parent=i/2;
  if(parent*SS_OPT_PER+24<SS_OPT_COUNT){o=Optics[parent*SS_OPT_PER];
   if(i%2==1){float3 energy=0,position=0;float active=0;
    for(uint k=0;k<24;k++){SsOptical p=Optics[parent*SS_OPT_PER+1+k];energy+=p.colour*p.intensity;position+=p.position;active=max(active,p.active);}
    o=Optics[parent*SS_OPT_PER+1];o.position=position/24;o.colour=energy/24;o.intensity=.04;o.active=active;o.padding.x=1;o.reach=min(o.reach,8);}}}
 else{uint k=i-MOVERS*2,s=k/2;if(SS_OPT_STROBE0+s<SS_OPT_COUNT){SsStrobe st=ssStrobeOf(Optics[SS_OPT_STROBE0+s]);if(st.active>.5){
   o.position=st.position+st.fwd*.08;o.normal=st.fwd;o.active=1;o.reach=34;o.padding=float3(2,st.length,0);
   if(k%2==0){o.colour=st.tube_colour;o.intensity=st.tube*strobe_gain;o.beam_tangent=tan(radians(38));o.field_tangent=tan(radians(64));}
   else{o.colour=st.plate_colour;o.intensity=st.plate*strobe_gain*.35;o.beam_tangent=tan(radians(48));o.field_tangent=tan(radians(72));}}}}
 Sources[i]=o;}
