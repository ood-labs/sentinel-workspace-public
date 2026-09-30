// Builds the world-space light grid (lightgrid.hlsli), one thread per cell. The live sources and
// emitters are staged in groupshared memory once per group; each cell then keeps the fixture cones
// that reach its bounding sphere, the emitters within LG_NEAR of it, and an L1 probe of the rest.
#include "../_shared/phage_fixture.hlsli"
#include "../_shared/phage_venue.hlsli"
#include "lightgrid.hlsli"
StructuredBuffer<PhOptical> Sources:register(t0);
StructuredBuffer<float4> Venue:register(t1);
RWStructuredBuffer<uint> Grid:register(u0);
groupshared float4 gL0[LG_CANDIDATES],gL1[LG_CANDIDATES];   // position + reach (-1 off), axis + field tangent
groupshared float4 gE0[PV_EMITTERS],gE1[PV_EMITTERS],gE2[PV_EMITTERS];   // a + area (-1 off), b, radiance x gain
float3 closestOnSegment(float3 p,float3 a,float3 b){float3 ab=b-a;return a+ab*saturate(dot(p-a,ab)/max(dot(ab,ab),1e-4));}
uint packHalf(float a,float b){return f32tof16(a)|(f32tof16(b)<<16);}
[numthreads(64,1,1)]void main(uint3 tid:SV_DispatchThreadID,uint gi:SV_GroupIndex){
 bool ok=_Data4_Count>=PV_COUNT;   // Venue is the Module's data input 4; the sources buffer is always 352 rows
 float gain=ok?Venue[PV_ROOM+2].w:0;
 [loop]for(uint k=gi;k<LG_CANDIDATES;k+=64){PhOptical b=(PhOptical)0;if(ok)b=Sources[lgSourceRow(k)];
  bool on=b.active>.5&&b.intensity>=.001&&any(b.colour>0);gL0[k]=float4(b.position,on?b.reach:-1);gL1[k]=float4(b.normal,b.field_tangent);}
 [loop]for(uint e=gi;e<PV_EMITTERS;e+=64){float4 a=0,b=0,r=0;if(ok){a=Venue[PV_EMIT+3*e];b=Venue[PV_EMIT+3*e+1];r=Venue[PV_EMIT+3*e+2];}
  float area=length(b.xyz-a.xyz)*max(.08,a.w);bool on=gain>0&&any(r.rgb>0);
  gE0[e]=float4(a.xyz,on?area:-1);gE1[e]=float4(b.xyz,0);gE2[e]=float4(r.rgb*gain*3,0);}
 GroupMemoryBarrierWithGroupSync();
 uint cell=tid.x;if(cell>=LG_CELLS)return;uint base=cell*LG_STRIDE;
 if(!ok){Grid[base]=0;[unroll]for(uint z=1;z<7;z++)Grid[base+z]=0;return;}
 float4 bounds=Venue[PV_ROOM+3];uint3 c3=uint3(cell%LG_X,(cell/LG_X)%LG_Y,cell/(LG_X*LG_Y));
 float3 cs=lgCellSize(bounds),cen=lgMin(bounds)+(c3+.5)*cs;float rc=length(cs)*.5;
 uint nl=0,ne=0,flags=0;
 [loop]for(uint k=0;k<LG_CANDIDATES;k++){float4 l0=gL0[k];if(l0.w<0)continue;float4 l1=gL1[k];
  float3 d=cen-l0.xyz;float ax=dot(d,l1.xyz);if(ax<-rc||ax>l0.w+rc)continue;
  float radial=length(d-l1.xyz*ax),field=.03+max(ax,0)*l1.w;
  if((radial-field)*rsqrt(1+l1.w*l1.w)>rc)continue;
  if(nl<LG_LIGHTS){Grid[base+LG_LIST+nl]=lgSourceRow(k);nl++;}else flags|=1;}
 float4 pr=0,pg=0,pb=0;
 [loop]for(uint e=0;e<PV_EMITTERS;e++){float4 e0=gE0[e];if(e0.w<0)continue;float3 q=closestOnSegment(cen,e0.xyz,gE1[e].xyz);
  float3 to=q-cen;float d=length(to);
  if(d<LG_NEAR+rc){if(ne<LG_EMITS){Grid[base+LG_LIST+LG_LIGHTS+ne]=e;ne++;}else flags|=2;}
  float3 I=gE2[e].rgb*e0.w/(d*d+e0.w)*(1-lgWindow(d));float3 dir=to/max(d,1e-3);
  pr+=I.r*float4(1,dir);pg+=I.g*float4(1,dir);pb+=I.b*float4(1,dir);}
 Grid[base]=nl|(ne<<8)|(flags<<16);
 Grid[base+1]=packHalf(pr.x,pr.y);Grid[base+2]=packHalf(pr.z,pr.w);
 Grid[base+3]=packHalf(pg.x,pg.y);Grid[base+4]=packHalf(pg.z,pg.w);
 Grid[base+5]=packHalf(pb.x,pb.y);Grid[base+6]=packHalf(pb.z,pb.w);}
