struct Architecture{float4 center,extent,surface,rotation;};
RWStructuredBuffer<Architecture>A:register(u0);
void box(inout uint i,float3 c,float3 e,float mat,float3 color){Architecture a;a.center=float4(c,mat);a.extent=float4(e,enabled?1:0);a.surface=float4(color,ambient);a.rotation=0;A[i++]=a;}
[numthreads(1,1,1)]void main(uint3 tid:SV_DispatchThreadID){for(uint j=0;j<256;j++)A[j]=(Architecture)0;uint i=0;float y=floor_level;
box(i,float3(0,y-.15,0),float3(width*.5,.15,length*.5),0,float3(.23,.235,.24));
if(walls){box(i,float3(-width*.5,y+height*.5,0),float3(.2,height*.5,length*.5),1,float3(.18,.19,.20));box(i,float3(width*.5,y+height*.5,0),float3(.2,height*.5,length*.5),1,float3(.18,.19,.20));
box(i,float3(0,y+height*.5,-length*.5),float3(width*.5,height*.5,.2),1,float3(.16,.17,.18));box(i,float3(0,y+height*.5,length*.5),float3(width*.5,height*.5,.2),1,float3(.16,.17,.18));}
if(roof)box(i,float3(0,y+height+.12,0),float3(width*.5,.12,length*.5),3,float3(.10,.11,.12));
for(uint bay=0;bay<9;bay++){float z=lerp(-length*.5+1,length*.5-1,bay/8.0);
for(uint side=0;side<2;side++){float x=(side==0?-1:1)*(width*.5-1);box(i,float3(x,y+height*.5,z),float3(.32,height*.5,.32),1,float3(.23,.24,.25));
box(i,float3(x,y+.15,z),float3(.55,.15,.55),1,float3(.18,.19,.20));}
box(i,float3(0,y+height-.7,z),float3(width*.5,.38,.32),1,float3(.23,.225,.21));
box(i,float3(0,y+height-1.45,z+.65),float3(width*.5,.045,.06),2,float3(.065,.07,.075));
box(i,float3(0,y+height-.75,z+.65),float3(width*.5,.045,.06),2,float3(.065,.07,.075));
for(uint tr=0;tr<8;tr++){float step=width/8,xa=-width*.5+tr*step,dy=tr%2==0?.7:-.7;box(i,float3(xa+step*.5,y+height-1.1,z+.65),float3(sqrt(step*step+dy*dy)*.5,.025,.035),2,float3(.065,.07,.075));A[i-1].rotation.x=atan2(dy,step);}}
for(uint k=0;k<13;k++){float x=lerp(-width*.5+.5,width*.5-.5,k/12.0);box(i,float3(x,y+height-.1,0),float3(.06,.10,length*.5),2,float3(.10,.11,.12));}
}
