// Surface light for the draw passes, culled through the world-space light grid (lightgrid.hlsli):
// the fixture beams and strobes listed for the pixel's cell, the pixel-bar emitters within LG_NEAR
// (exact, windowed), and the cell probes' L1 irradiance for all farther bar light. Sources are
// bound at LIGHT_SLOT, the grid at GRID_SLOT; room_materials.hlsli must be included first.
#ifndef LIGHT_SLOT
#define LIGHT_SLOT t1
#endif
#ifndef GRID_SLOT
#define GRID_SLOT t3
#endif
#include "../_shared/phage_fixture.hlsli"
#include "lightgrid.hlsli"
StructuredBuffer<PhOptical> SurfaceLights:register(LIGHT_SLOT);
StructuredBuffer<uint> Grid:register(GRID_SLOT);
// roomBRDF with the normal-variance term hoisted out of the light loops.
float3 lgBRDF(float3 n,float3 v,float3 l,float3 albedo,float rough,float metal,float variance,bool diffuseOnly){
 float nl=saturate(dot(n,l));if(nl<=0)return 0;
 if(diffuseOnly)return albedo*(1-metal)/3.14159265*nl;
 float nv=max(.001,saturate(dot(n,v)));float3 h=normalize(v+l);float nh=saturate(dot(n,h)),vh=saturate(dot(v,h));
 float a=max(.006,saturate(rough*rough+min(.18,variance))),a2=a*a,d=nh*nh*(a2-1)+1;
 float D=a2/(3.14159265*d*d),k=(rough+1)*(rough+1)/8;float G=nv/(nv*(1-k)+k)*nl/(nl*(1-k)+k);
 float3 F=roomFresnel(vh,lerp(.04.xxx,albedo,metal));
 return ((1-F)*(1-metal)*albedo/3.14159265+F*D*G/max(.004,4*nl*nv))*nl;}
float3 sourceLight(PhOptical b,float3 p,float3 n,float3 v,float3 albedo,float rough,float metal,float variance,bool diffuseOnly){
 float3 d=p-b.position;float ax=dot(d,b.normal);if(ax<=0||ax>=b.reach)return 0;
 float radial=length(d-b.normal*ax);float field=.03+ax*b.field_tangent;if(radial>=field)return 0;
 float core=.025+ax*b.beam_tangent;float angular=exp(-.69314718*pow(radial/max(core,.001),2))*(1-smoothstep(field*.8,field,radial));
 float fall=1-smoothstep(b.reach*.75,b.reach,ax);
 return lgBRDF(n,v,-normalize(d),albedo,rough,metal,variance,diffuseOnly)*b.colour*b.intensity*angular*fall*fall*25/(.4+ax*ax);}
// Finite LED strip: a representative point follows the reflection on metals; diffuse bounce uses
// the closest point on the segment. Weighted by the near window; the probes carry the rest.
float3 emitterLight(uint k,float3 p,float3 n,float3 v,float3 ray,float3 albedo,float rough,float metal,float variance,bool diffuseOnly){
 RoomEmitter e=roomEmitter(k);if(!any(e.radiance.rgb>0))return 0;
 float3 ab=e.b.xyz-e.a.xyz,rel=p-e.a.xyz;float len2=max(dot(ab,ab),.001);float t=dot(rel,ab)/len2;
 if(metal>.5&&!diffuseOnly){float b=dot(ray,ab);t=(dot(rel,ab)-dot(rel,ray)*b)/max(.001,len2-b*b);}
 float3 d=e.a.xyz+ab*saturate(t)-p;float dist2=max(dot(d,d),.02);float3 l=d*rsqrt(dist2);
 float area=sqrt(len2)*max(.08,e.a.w),solid=area/(dist2+area),r=max(rough,.10*sqrt(solid));
 float3 q=e.a.xyz+ab*saturate(dot(rel,ab)/len2);
 return lgBRDF(n,v,l,albedo,r,metal,variance,diffuseOnly)*e.radiance.rgb*solid*3*lgWindow(length(q-p));}
// Trilinear L1 probe irradiance: E(n) = .25 T + .5 D.n per channel.
float3 lgProbe(uint cell,float3 n){uint b=cell*LG_STRIDE;
 float4 r=float4(f16tof32(Grid[b+1]),f16tof32(Grid[b+1]>>16),f16tof32(Grid[b+2]),f16tof32(Grid[b+2]>>16));
 float4 g=float4(f16tof32(Grid[b+3]),f16tof32(Grid[b+3]>>16),f16tof32(Grid[b+4]),f16tof32(Grid[b+4]>>16));
 float4 c=float4(f16tof32(Grid[b+5]),f16tof32(Grid[b+5]>>16),f16tof32(Grid[b+6]),f16tof32(Grid[b+6]>>16));
 return max(0,.25*float3(r.x,g.x,c.x)+.5*float3(dot(r.yzw,n),dot(g.yzw,n),dot(c.yzw,n)));}
float3 lgFar(float3 p,float3 n,float4 bounds){
 float3 g=(p-lgMin(bounds))/lgCellSize(bounds)-.5;float3 f=frac(g);int3 i0=(int3)floor(g);float3 sum=0;
 [unroll]for(uint k=0;k<8;k++){int3 o=int3(k&1,(k>>1)&1,k>>2);uint3 c=(uint3)clamp(i0+o,0,int3(LG_X-1,LG_Y-1,LG_Z-1));
  float w=(o.x?f.x:1-f.x)*(o.y?f.y:1-f.y)*(o.z?f.z:1-f.z);sum+=lgProbe(lgIndex(c),n)*w;}
 return sum;}
float3 phageLightImpl(float3 p,float3 n,float3 v,float3 albedo,float rough,float metal,bool diffuseOnly){
 float variance=.5*(dot(ddx(n),ddx(n))+dot(ddy(n),ddy(n)));float4 bounds=Venue[PV_ROOM+3];
 uint base=lgCellOf(p,bounds)*LG_STRIDE,h=Grid[base],nl=h&255,ne=(h>>8)&255,flags=h>>16;float3 sum=0;
 if(flags&1){[loop]for(uint k=0;k<LG_CANDIDATES;k++){PhOptical b=SurfaceLights[lgSourceRow(k)];if(b.active<.5||b.intensity<.001||!any(b.colour>0))continue;
   sum+=sourceLight(b,p,n,v,albedo,rough,metal,variance,diffuseOnly);}}
 else{[loop]for(uint k=0;k<nl;k++)sum+=sourceLight(SurfaceLights[Grid[base+LG_LIST+k]],p,n,v,albedo,rough,metal,variance,diffuseOnly);}
 float3 c=sum*Venue[PV_ROOM].w;float gain=Venue[PV_ROOM+2].w;
 if(gain>0){float3 ray=reflect(-v,n),led=0;
  if(flags&2){[loop]for(uint e=0;e<ROOM_EMITTERS;e++)led+=emitterLight(e,p,n,v,ray,albedo,rough,metal,variance,diffuseOnly);}
  else{[loop]for(uint k=0;k<ne;k++)led+=emitterLight(Grid[base+LG_LIST+LG_LIGHTS+k],p,n,v,ray,albedo,rough,metal,variance,diffuseOnly);}
  c+=led*gain+albedo*(1-metal)/3.14159265*lgFar(p,n,bounds);}
 return c;}
float3 phageLight(float3 p,float3 n,float3 v,float3 albedo,float rough,float metal){return phageLightImpl(p,n,v,albedo,rough,metal,false);}
float3 phageLightDiffuse(float3 p,float3 n,float3 albedo){return phageLightImpl(p,n,0,albedo,1,0,true);}
