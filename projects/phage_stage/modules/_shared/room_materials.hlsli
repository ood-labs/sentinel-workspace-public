// Room settings and pixel-bar emitters, read from the Venue's packed float4 buffer (phage_venue.hlsli).
#ifndef VENUE_SLOT
#define VENUE_SLOT t2
#endif
#include "../_shared/phage_venue.hlsli"
struct RoomSettings{float4 fill,material,tint,bounds,finish;};
#define ROOM_EMITTERS PV_EMITTERS
struct RoomEmitter{float4 a,b,radiance;};
StructuredBuffer<float4> Venue:register(VENUE_SLOT);
RoomSettings roomSettings(){RoomSettings r;r.fill=Venue[PV_ROOM];r.material=Venue[PV_ROOM+1];r.tint=Venue[PV_ROOM+2];r.bounds=Venue[PV_ROOM+3];r.finish=Venue[PV_ROOM+4];return r;}
RoomEmitter roomEmitter(uint k){RoomEmitter e;uint b=PV_EMIT+3*k;e.a=Venue[b];e.b=Venue[b+1];e.radiance=Venue[b+2];return e;}
float roomHash(float2 p){return frac(sin(dot(p,float2(127.1,311.7)))*43758.5453);}
float roomNoise(float2 p){float2 b=floor(p),f=frac(p);f=f*f*(3-2*f);return lerp(lerp(roomHash(b),roomHash(b+float2(1,0)),f.x),lerp(roomHash(b+float2(0,1)),roomHash(b+1),f.x),f.y);}
float3 roomFresnel(float cosine,float3 f0){return f0+(1-f0)*pow(1-saturate(cosine),5);}
float3 roomBRDF(float3 n,float3 v,float3 l,float3 albedo,float rough,float metal){
 float nl=saturate(dot(n,l)),nv=max(.001,saturate(dot(n,v)));if(nl<=0)return 0;
 float3 h=normalize(v+l);float nh=saturate(dot(n,h)),vh=saturate(dot(v,h));
 float variance=.5*(dot(ddx(n),ddx(n))+dot(ddy(n),ddy(n)));
 float a=max(.006,saturate(rough*rough+min(.18,variance))),a2=a*a,d=nh*nh*(a2-1)+1;
 float D=a2/(3.14159265*d*d),k=(rough+1)*(rough+1)/8;
 float G=nv/(nv*(1-k)+k)*nl/(nl*(1-k)+k);
 float3 F=roomFresnel(vh,lerp(.04.xxx,albedo,metal));
 return ((1-F)*(1-metal)*albedo/3.14159265+F*D*G/max(.004,4*nl*nv))*nl;
}
// Finite LED strips: a representative point follows the reflection direction
// on metals, while diffuse bounce uses the closest point on the actual segment.
float3 roomLEDLight(float3 p,float3 n,float3 v,float3 albedo,float rough,float metal){
 float3 result=0;float gain=Venue[PV_ROOM+2].w;if(gain<=0)return 0;
 float3 ray=reflect(-v,n);
 [loop]for(uint k=0;k<ROOM_EMITTERS;k++){
  RoomEmitter e=roomEmitter(k);if(!any(e.radiance.rgb>0))continue;
  float3 ab=e.b.xyz-e.a.xyz,rel=p-e.a.xyz;float len2=max(dot(ab,ab),.001);
  float t=dot(rel,ab)/len2;
  if(metal>.5){float b=dot(ray,ab);t=(dot(rel,ab)-dot(rel,ray)*b)/max(.001,len2-b*b);}
  float3 d=e.a.xyz+ab*saturate(t)-p;float dist2=max(dot(d,d),.02);float3 l=d*rsqrt(dist2);
  float area=sqrt(len2)*max(.08,e.a.w);
  float solid=area/(dist2+area);
  float r=max(rough,.10*sqrt(solid));
  result+=roomBRDF(n,v,l,albedo,r,metal)*e.radiance.rgb*solid*gain*3;
 }
 return result;
}
float3 roomLEDDiffuse(float3 p,float3 n){
 float3 sum=0;float gain=Venue[PV_ROOM+2].w;if(gain<=0)return 0;
 [loop]for(uint k=0;k<ROOM_EMITTERS;k++){
  RoomEmitter e=roomEmitter(k);if(!any(e.radiance.rgb>0))continue;
  float3 ab=e.b.xyz-e.a.xyz;float len2=max(dot(ab,ab),.001);
  float3 d=e.a.xyz+ab*saturate(dot(p-e.a.xyz,ab)/len2)-p;
  float dist2=max(dot(d,d),.02),area=sqrt(len2)*max(.08,e.a.w);
  sum+=e.radiance.rgb*saturate(dot(n,d*rsqrt(dist2)))*area/(dist2+area)*gain;
 }
 return sum;
}
