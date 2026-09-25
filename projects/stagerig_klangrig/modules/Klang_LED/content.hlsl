#include "../_shared/program.hlsli"
#include "scatter.hlsli"
StructuredBuffer<KlangProgram>Program:register(t3);
#include "../_shared/rig.hlsli"
StructuredBuffer<RigRecord>R:register(t0);StructuredBuffer<float4>S:register(t1);
#include "led_patterns.hlsli"

#include "../_shared/show.hlsli"
StructuredBuffer<float4>Show:register(t2);
RWTexture2D<float4>OutputUAV:register(u0);
[numthreads(8,8,1)]void main(uint3 id:SV_DispatchThreadID){uint w,h;OutputUAV.GetDimensions(w,h);if(id.x>=w||id.y>=h)return;float u=(id.x+.5)/w,v=(id.y+.5)/h*12;uint wing=min(11u,(uint)v);float t=frac(v);float ph=phase+_Time*rate*(animate?1:0);float val=1;
 if(pattern==1)val=(1-smoothstep(.035,.07,min(t,1-t)))+ .45*(1-smoothstep(.015,.04,abs(t-.5)));
 if(pattern==2)val=smoothstep(.82,.85,frac(u*4-ph+wing*.12));
 if(pattern==3)val=.5+.5*sin((ph-wing*.08)*6.2831853);
 if(pattern==4)val=(1-smoothstep(.035,.065,abs(u-frac(ph))))*(.25+.75*t);
 if(pattern==5){uint f=(uint)S[0].y-1;float total=0,lo=0,len=0;for(uint j=0;j<4;j++){RigRecord r=R[1+wing*4+j];float l=length(r.b.xyz-r.a.xyz);total+=l;if(j<f%4)lo+=l;if(j==f%4)len=l;}val=0;if(_Data0_Count>=49&&total>0&&wing==f/4)val=(u>lo/total+1.0/w&&u<(lo+len)/total-1.0/w)?1:0;}
 float3 color=pattern==5?float3(1,1,1):led_color;if(pattern==4)color=u<.04?float3(1,.2,0):u>.96?float3(0,.5,1):float3(.7,1,.1);
 if(pattern<4&&_Data1_Count>=3&&Show[0].y>.5&&Show[2].x<.5&&_Data0_Count>=49){float z=0;for(uint j=0;j<4;j++)z+=R[1+wing*4+j].a.z*.25;float rank=klangRank(z,R[0].a.z,R[0].b.z,Show[1].y);val=klangPulse(Show[0].x,rank,Show[0].z,Show[0].w);color=float3(1,.003,.0005)*Show[1].z;}
 if(pattern<4&&_Data2_Count>=289&&_Data1_Count>=9&&Show[2].x>.5){KlangProgram pr=Program[288];uint lane=(uint)pr.routing.w;float4 l=lane>0?Show[2+min(3u,lane)]:float4(0,1,0,1);float z=0;for(uint j=0;j<4;j++)z+=R[1+wing*4+j].a.z*.25;float rank=klangRank(z,R[0].a.z,R[0].b.z,pr.timing.z);uint pat=(uint)pr.timing.w;
 val=pat==0?1:pat==1?(1-smoothstep(.035,.07,min(t,1-t))):pat==2?l.y*klangPulse(l.x+pr.timing.y,rank,pr.timing.x,pr.movement.w):l.y*klangPulse(l.x+pr.timing.y,0,pr.timing.x,0);
 uint palette=min(2u,(uint)pr.routing.x);color=Show[6+palette].rgb;
 if(pat==4){val=lane>0?wingScatter(wing,l.x,l.y,pr.movement.w,pr.timing.x,pr.timing.y,pr.timing.z,strobe_rate,strobe_duty,strobe_cycle_beats):0;
 // The LED group's ring palette is its accent color; the base can stay black.
 color=Show[6+min(2u,(uint)pr.routing.y)].rgb;}
 if(pat>=5){float3 c=(R[0].a.xyz+R[0].b.xyz)*.5;color=ledPattern(min(15u,pat),wing,u,t,l,lane,pr,rank,color,Show[6+min(2u,(uint)pr.routing.y)].rgb,loopPoint(wing,u),c,_Time);val=1;}
 uint colorLane=(uint)pr.movement.x;if(colorLane>0){float4 c=Show[2+min(3u,colorLane)];color=lerp(color,Show[6+(palette+1)%3].rgb,(.5-.5*cos(c.x*6.2831853))*c.y);}
 color*=Show[1].z;val*=pr.aim.z*pr.meta.y;}
 if(pattern>=4&&_Data2_Count>=289&&_Data1_Count>=9&&Show[2].x>.5)val*=Program[288].aim.z*Program[288].meta.y;
 if(_Data2_Count>=289&&_Data1_Count>=10&&Show[9].x>.5){color=Show[1].z;val=Show[9].y*Program[288].meta.y;}
 if(isolate_wing>=0&&wing!=(uint)isolate_wing)val=0;
 OutputUAV[id.xy]=float4(color*val*level,1);}
