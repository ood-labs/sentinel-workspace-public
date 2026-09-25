#include "../_shared/rm_types.hlsli"
RWStructuredBuffer<RmOptical> Sources:register(u0);
[numthreads(1,1,1)]void main(uint3 tid:SV_DispatchThreadID){
 uint i=tid.x,parent=i/2;if(i>=576)return;RmOptical o=(RmOptical)0;
 if(parent*25>=_Data1_Count){Sources[i]=o;return;}
 o=_Data1[parent*25];
 if(i%2==1){float3 energy=0,position=0;float active=0;
  for(uint k=0;k<24;k++){RmOptical p=_Data1[parent*25+1+k];energy+=p.colour*p.intensity;position+=p.position;active=max(active,p.active);}
  o=_Data1[parent*25+1];o.position=position/24;o.colour=energy/24;o.intensity=.04;o.active=active;
 }
 Sources[i]=o;
}
