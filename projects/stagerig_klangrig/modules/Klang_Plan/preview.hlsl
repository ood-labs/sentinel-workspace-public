
#include "layout.hlsli"
#include "../_shared/ui/sui3_core.hlsli"
#include "../_shared/ui/sui3_text.hlsli"
StructuredBuffer<RigRecord>R:register(t0);StructuredBuffer<float4>E:register(t1);StructuredBuffer<MountRecord>M:register(t2);RWTexture2D<float4>OutputUAV:register(u0);
float3 groupColor(uint g){return g==0?float3(.94,.77,.42):g==1?float3(.3,.8,.85):g==2?float3(.7,.65,.95):float3(.95,.55,.4);}

static const uint L0[15]={75,76,65,78,71,82,73,71,32,47,32,80,76,65,78};
static const uint L1[14]={83,73,68,69,32,69,76,69,86,65,84,73,79,78};
static const uint L2[13]={69,78,68,32,69,76,69,86,65,84,73,79,78};
static const uint L3[54]={68,82,65,71,32,87,73,78,71,32,72,65,78,68,76,69,83,32,47,32,82,32,82,69,83,69,84,32,47,32,68,73,77,69,78,83,73,79,78,83,32,65,82,69,32,69,83,84,73,77,65,84,69,83};
float label(float2 p,float2 pos,uint n){float a=0;if(n==0)for(uint j=0;j<15;j++)a=max(a,sui3Glyph(p,pos+float2(j*SUI3_ADVANCE,0),1,L0[j]));if(n==1)for(uint j=0;j<14;j++)a=max(a,sui3Glyph(p,pos+float2(j*SUI3_ADVANCE,0),1,L1[j]));if(n==2)for(uint j=0;j<13;j++)a=max(a,sui3Glyph(p,pos+float2(j*SUI3_ADVANCE,0),1,L2[j]));if(n==3)for(uint j=0;j<54;j++)a=max(a,sui3Glyph(p,pos+float2(j*SUI3_ADVANCE,0),1,L3[j]));return a;}
[numthreads(8,8,1)]void main(uint3 id:SV_DispatchThreadID){uint W,H;OutputUAV.GetDimensions(W,H);if(id.x>=W||id.y>=H)return;float2 p=id.xy+.5;uint v=viewAt(p);float3 c=float3(.025,.035,.047);
 float2 grid=abs(frac((p-originAt(v))/scaleAt(v)+.5)-.5)*scaleAt(v);c+=.018*(1-smoothstep(.3,1,min(grid.x,grid.y)));
 for(uint i=0;i<SEGMENTS;i++){RigRecord r=R[i];float d=lineDist(p,project(r.a.xyz,v),project(r.b.xyz,v));c=lerp(c,groupColor((uint)r.meta.z),1-smoothstep(1,2.3,d));}
 for(uint f=0;f<FIXTURES;f++){MountRecord m=M[f];if(m.active>.5){float d=length(p-project(m.position,v));c=lerp(c,float3(.82,.85,.88),1-smoothstep(1.5,2.5,d));}}
 for(uint h=0;h<13;h++){float3 q=h==0?(R[0].a.xyz+R[0].b.xyz)*.5:R[2+(h-1)*4].a.xyz;float d=length(p-project(q,v));c=lerp(c,E[0].x==h+1?float3(1,.85,.4):float3(.3,.6,.65),1-smoothstep(5,6,d));}
 float div=min(abs(p.y-H*.5),p.y>H*.5?abs(p.x-W*.65):9999);c=lerp(c,float3(.22,.3,.34),1-smoothstep(.5,1.5,div));
 c=lerp(c,float3(.8,.86,.9),label(p,float2(20,18),0));c=lerp(c,float3(.8,.86,.9),label(p,float2(20,H*.5+16),1));c=lerp(c,float3(.8,.86,.9),label(p,float2(W*.65+16,H*.5+16),2));c=lerp(c,float3(.5,.65,.7),label(p,float2(20,H-20),3));OutputUAV[id.xy]=float4(c,1);}
