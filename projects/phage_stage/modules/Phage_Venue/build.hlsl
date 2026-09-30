// The arena: polished floor, dark walls, roof trusses, side columns and seating tiers on three sides.
// center.w = material: 0 floor, 1 concrete, 2 steel, 3 roof, 4 seating.
struct Architecture{float4 center,extent,surface,rotation;};
RWStructuredBuffer<Architecture>A:register(u0);
void box(inout uint i,float3 c,float3 e,float mat,float3 color){if(i>=256)return;Architecture a;a.center=float4(c,mat);a.extent=float4(e,enabled?1:0);a.surface=float4(color,ambient);a.rotation=0;A[i++]=a;}
[numthreads(1,1,1)]void main(uint3 tid:SV_DispatchThreadID){
 for(uint j=0;j<256;j++)A[j]=(Architecture)0;uint i=0;float y=floor_level;float hw=hall_width*.5,hl=hall_length*.5;
 box(i,float3(0,y-.15,0),float3(hw,.15,hl),0,float3(.2,.205,.21));
 if(walls){box(i,float3(-hw,y+hall_height*.5,0),float3(.3,hall_height*.5,hl),1,float3(.10,.105,.11));box(i,float3(hw,y+hall_height*.5,0),float3(.3,hall_height*.5,hl),1,float3(.10,.105,.11));
  box(i,float3(0,y+hall_height*.5,-hl),float3(hw,hall_height*.5,.3),1,float3(.09,.095,.10));box(i,float3(0,y+hall_height*.5,hl),float3(hw,hall_height*.5,.3),1,float3(.09,.095,.10));}
 if(roof)box(i,float3(0,y+hall_height+.15,0),float3(hw,.15,hl),3,float3(.06,.065,.07));
 uint bays=(uint)clamp(floor(hall_length/10),4,11);
 for(uint b=0;b<bays;b++){float z=lerp(-hl+4,hl-4,b/(float)(bays-1));
  for(uint s=0;s<2;s++){float x=(s==0?-1:1)*(hw-1.2);box(i,float3(x,y+hall_height*.5,z),float3(.4,hall_height*.5,.4),2,float3(.16,.165,.17));}
  box(i,float3(0,y+hall_height-.5,z),float3(hw,.09,.14),2,float3(.07,.075,.08));
  box(i,float3(0,y+hall_height-2.6,z),float3(hw,.09,.14),2,float3(.07,.075,.08));
  for(uint tr=0;tr<10;tr++){float st=hall_width/10,xa=-hw+tr*st,dy=tr%2==0?2.1:-2.1;box(i,float3(xa+st*.5,y+hall_height-1.55,z),float3(sqrt(st*st+dy*dy)*.5,.05,.06),2,float3(.07,.075,.08));A[i-1].rotation.x=atan2(dy,st);}}
 if(tiers){for(uint k=0;k<7;k++){float rise=.75*(k+1),run=1.1;
  for(uint s=0;s<2;s++){float x=(s==0?-1:1)*(hw-2.5-run*(6.5-k));box(i,float3(x,y+rise*.5,6),float3(run*.5,rise*.5,hl-14),4,float3(.06,.062,.07));}
  box(i,float3(0,y+rise*.5,-hl+2.5+run*(6.5-k)),float3(hw-14,rise*.5,run*.5),4,float3(.06,.062,.07));
  box(i,float3(0,y+rise*.5,hl-2.5-run*(6.5-k)),float3(hw-14,rise*.5,run*.5),4,float3(.06,.062,.07));}}
}
