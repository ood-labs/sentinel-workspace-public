// Atmosphere and surface sources: per mover a narrow beam + its ring glow (averaged),
// per strobe a wide tube flash + a coloured plate wash. padding.x: 0 beam, 1 ring, 2 strobe.
#include "../_shared/phage_fixture.hlsli"
StructuredBuffer<PhOptical> Optics:register(t0);
RWStructuredBuffer<PhOptical> Sources:register(u0);
#define MOVERS 128
#define STROBES 48
[numthreads(64,1,1)]void main(uint3 tid:SV_DispatchThreadID){
 uint i=tid.x;if(i>=MOVERS*2+STROBES*2)return;PhOptical o=(PhOptical)0;
 if(i<MOVERS*2){uint parent=i/2;
  if(parent*PH_OPT_PER+24<_Data1_Count){o=Optics[parent*25];
   if(i%2==1){float3 energy=0,position=0;float active=0;
    for(uint k=0;k<24;k++){PhOptical p=Optics[parent*25+1+k];energy+=p.colour*p.intensity;position+=p.position;active=max(active,p.active);}
    o=Optics[parent*25+1];o.position=position/24;o.colour=energy/24;o.intensity=.04;o.active=active;o.padding.x=1;o.reach=min(o.reach,8);}}}
 else{uint k=i-MOVERS*2,s=k/2;if(PH_OPT_STROBE0+s<_Data1_Count){PhStrobe st=phStrobeOf(Optics[PH_OPT_STROBE0+s]);if(st.active>.5){
   o.position=st.position+st.fwd*.08;o.normal=st.fwd;o.active=1;o.reach=34;o.padding=float3(2,st.length,0);
   if(k%2==0){o.colour=st.tube_colour;o.intensity=st.tube*strobe_gain;o.beam_tangent=tan(radians(38));o.field_tangent=tan(radians(64));}
   else{o.colour=st.plate_colour;o.intensity=st.plate*strobe_gain*.35;o.beam_tangent=tan(radians(48));o.field_tangent=tan(radians(72));}}}}
 Sources[i]=o;}
