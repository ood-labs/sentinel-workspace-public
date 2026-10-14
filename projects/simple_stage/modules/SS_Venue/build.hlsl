// The club: a black-box room with the stage at one end. Polished concrete floor, painted block walls, a black ceiling
// carried on steel beams, a crowd barrier, the PA stacked either side of the stage, a front-of-house riser and a bar
// across the back. The room runs from stage_depth behind the stage's centre to hall_length in front of that.
// center.w = material: 0 floor, 1 wall, 2 steel, 3 ceiling, 4 black fittings (PA, bar, riser).
#include "venue_view.hlsli"
struct Architecture{float4 center,extent,surface,rotation;};
RWStructuredBuffer<Architecture>A:register(u0);
void box(inout uint i,float3 c,float3 e,float mat,float3 color){if(i>=256)return;Architecture a;a.center=float4(c,mat);a.extent=float4(e,enabled?1:0);a.surface=float4(color,ambient);a.rotation=0;A[i++]=a;}
[numthreads(1,1,1)]void main(uint3 tid:SV_DispatchThreadID){
 for(uint j=0;j<256;j++)A[j]=(Architecture)0;uint i=0;float y=floor_level;float hw=hall_width*.5,hl=hall_length*.5,zc=roomZ();
 float zb=zc-hl,zf=zc+hl;   // the back wall behind the stage, the far wall behind the crowd
 box(i,float3(0,y-.15,zc),float3(hw,.15,hl),0,float3(.2,.205,.21));
 if(walls){box(i,float3(-hw,y+hall_height*.5,zc),float3(.3,hall_height*.5,hl),1,float3(.10,.105,.11));
  box(i,float3(hw,y+hall_height*.5,zc),float3(.3,hall_height*.5,hl),1,float3(.10,.105,.11));
  box(i,float3(0,y+hall_height*.5,zb),float3(hw,hall_height*.5,.3),1,float3(.05,.05,.055));
  box(i,float3(0,y+hall_height*.5,zf),float3(hw,hall_height*.5,.3),1,float3(.09,.095,.10));}
 if(roof){box(i,float3(0,y+hall_height+.15,zc),float3(hw,.15,hl),3,float3(.04,.042,.045));
  // steel beams across the ceiling, one every 4 m
  uint beams=(uint)clamp(floor(hall_length/4),2,12);
  for(uint b=0;b<beams;b++){float z=lerp(zb+2,zf-2,b/(float)(beams-1));box(i,float3(0,y+hall_height-.2,z),float3(hw,.2,.1),2,float3(.07,.075,.08));}}
 // the crowd barrier, in front of the deck
 box(i,float3(0,y+.55,CROWD_BARRIER),float3(hw-1.5,.55,.05),2,float3(.16,.165,.17));
 // the PA: a sub and two tops either side of the stage, outside the trusses
 for(uint s=0;s<2;s++){float x=(s==0?-1:1)*(SS_BOUNDS.x+1.35);
  box(i,float3(x,y+.6,1.6),float3(.65,.6,.5),4,float3(.03,.03,.032));
  box(i,float3(x,y+1.6,1.6),float3(.45,.4,.4),4,float3(.03,.03,.032));
  box(i,float3(x,y+2.3,1.6),float3(.45,.3,.4),4,float3(.03,.03,.032));}
 // front of house: a riser and its desk two thirds back, off the centre line
 float zh=lerp(CROWD_BARRIER,zf,.62);
 box(i,float3(2.6,y+.2,zh),float3(1.8,.2,1.4),4,float3(.035,.036,.04));
 box(i,float3(2.6,y+.85,zh-.4),float3(1.5,.45,.35),4,float3(.03,.03,.032));
 // the bar across the back
 box(i,float3(0,y+.55,zf-1.6),float3(min(6.0,hw-2),.55,.45),4,float3(.04,.038,.036));
}
