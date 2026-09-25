#ifndef LIGHT_SLOT
#define LIGHT_SLOT t1
#endif
#include "../_shared/rm_types.hlsli"
StructuredBuffer<RmOptical> SurfaceLights:register(LIGHT_SLOT);
float3 fixtureSurface(float3 p,float3 n){float3 sum=0;
[loop]for(uint k=0;k<288;k++){RmOptical b=SurfaceLights[k*2];if(b.active<.5||b.intensity<.001)continue;float3 d=p-b.position;float ax=dot(d,b.normal);if(ax<=0||ax>=b.reach)continue;float radial=length(d-b.normal*ax),field=.03+ax*b.field_tangent;if(radial>=field)continue;float core=.025+ax*b.beam_tangent;float angular=exp(-.69314718*pow(radial/max(core,.001),2))*(1-smoothstep(field*.8,field,radial));float fall=1-smoothstep(b.reach*.75,b.reach,ax);sum+=b.colour*b.intensity*angular*fall*fall*saturate(dot(n,-normalize(d)))*8/(.4+ax*ax);}
return sum;}

float3 fixtureMaterial(float3 p,float3 n,float3 v,float3 albedo,float rough,float metal){float3 sum=0;
[loop]for(uint k=0;k<288;k++){RmOptical b=SurfaceLights[k*2];if(b.active<.5||b.intensity<.001||!any(b.colour>0))continue;float3 d=p-b.position;float ax=dot(d,b.normal);if(ax<=0||ax>=b.reach)continue;float radial=length(d-b.normal*ax),field=.03+ax*b.field_tangent;if(radial>=field)continue;float core=.025+ax*b.beam_tangent;float angular=exp(-.69314718*pow(radial/max(core,.001),2))*(1-smoothstep(field*.8,field,radial));float fall=1-smoothstep(b.reach*.75,b.reach,ax);sum+=roomBRDF(n,v,-normalize(d),albedo,rough,metal)*b.colour*b.intensity*angular*fall*fall*25/(.4+ax*ax);}
return sum*Room[0].fill.w;}
