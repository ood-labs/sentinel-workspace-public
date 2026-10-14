// Haze in-scatter at half resolution: mover beams (sampled cone intervals); ring glows, strobe flashes
// and pixel-bar glow in closed form (1/d^2 line integrals, cone terms at closest approach). Each 8 x 8
// group first stages, in groupshared memory, only the lights whose volume can reach its view cone
// (the sum does not care about order), so a pixel neither reads nor tests the rest.
//
// With SS_Haze's field linked (haze_field.hlsli) the haze is the simulated one: every beam sample takes the
// density where it lies (with the flow-carried wisps), dimmed by the haze between it and the lens (beamt.hlsl) and
// between it and the eye (a 16-step march of the view ray); a glow takes the density where the ray passes closest.
// The samples then jitter along each interval every frame for the TAA to average. Alpha carries the march's mean
// density for hdr_scene's surface attenuation. Unlinked, every term reduces exactly to the even haze.
#include "taa.hlsli"
#include "../_shared/ss_fixture.hlsli"
StructuredBuffer<SsOptical> Sources:register(t0);
#include "../_shared/ss_venue.hlsli"
struct RoomEmitter{float4 a,b,radiance;};StructuredBuffer<float4> Venue:register(t2);
RWTexture2D<float4> OutputUAV:register(u0);
#define HF_TEX _Tex3
#include "haze_field.hlsli"
StructuredBuffer<float> BT:register(t4);
// the view ray through the haze: cumulative density x length at HV_STEPS + 1 points out to gTauL
#define HV_STEPS 16
static float gTau[HV_STEPS+1];static float gTauL;
void viewMarch(float3 ro,float3 rd,float limit,float jit){gTauL=max(min(limit,80.0),1e-3);float seg=gTauL/HV_STEPS,acc=0;gTau[0]=0;
 [loop]for(uint i=0;i<HV_STEPS;i++){acc+=hzDen(ro+rd*((i+jit)*seg))*seg;gTau[i+1]=acc;}}
// transmittance from the eye to t along the ray
float viewT(float t){if(!gHzOn)return exp(-haze*t);float f=saturate(t/gTauL)*HV_STEPS;uint i=min((uint)f,HV_STEPS-1);
 return exp(-haze*(lerp(gTau[i],gTau[i+1],f-i)+max(t-gTauL,0)*lerp(1.0,gHzBase,haze_sim)));}
// transmittance from a beam's lens to ax metres down it (beamt.hlsl's table row)
float beamTrans(uint row,float ax,float reach){float f=saturate(ax/max(reach,1e-3))*64;uint i=min((uint)f,63u);
 float t0=i==0?0:BT[row*64+i-1],t1=BT[row*64+i];return exp(-lerp(t0,t1,f-i));}
bool coneInterval(float3 rel,float3 rd,float3 axis,float aperture,float slope,float reach,float limit,out float a,out float b){
 float z=dot(rel,axis),dz=dot(rd,axis);a=0;b=limit;
 if(abs(dz)<1e-7){if(z<0||z>reach)return false;}
 else{float t0=-z/dz,t1=(reach-z)/dz;a=max(a,min(t0,t1));b=min(b,max(t0,t1));}
 if(b<=a)return false;
 float r=aperture+slope*z,k=slope*dz;
 float A=1-dz*dz-k*k,B=2*(dot(rel,rd)-z*dz-r*k),C=dot(rel,rel)-z*z-r*r;
 if(abs(A)<1e-7){if(abs(B)<1e-7)return C<=0;float root=-C/B;if(B>0)b=min(b,root);else a=max(a,root);}
 else{float D=B*B-4*A*C;if(D<0)return A<0;float t0=(-B-sqrt(max(D,0)))/(2*A),t1=(-B+sqrt(max(D,0)))/(2*A);
  float lo=min(t0,t1),hi=max(t0,t1);if(A>0){a=max(a,lo);b=min(b,hi);}else if(a<lo)b=min(b,lo);else a=max(a,hi);}
 return b>a;
}
// Wide cones (ring glows, strobes) in closed form: the cone's angular and range terms at the ray's
// closest approach multiply the exact line integral of 1/d^2 along the visible segment.
float broadGlow(float4 pr,float4 nf,float beamT,float3 ro,float3 rd,float limit){
 float3 rel=ro-pr.xyz;float tc=-dot(rel,rd),t0=clamp(tc,0,limit);float3 d=rel+rd*t0;
 float perp=max(length(rel+rd*tc),.245),ax=dot(d,nf.xyz),slope=length(d-nf.xyz*ax)/max(.025,ax);
 float angular=ax>0?exp(-.69314718*(slope/beamT)*(slope/beamT))*(1-smoothstep(nf.w,nf.w*1.3,slope)):0;
 float edge=1-smoothstep(pr.w*.75,pr.w,length(d));
 return angular*edge*edge*.15*(atan((limit-tc)/perp)-atan(-tc/perp))/perp*viewT(t0)*hzDen(ro+rd*t0);
}
float narrowIntegral(float4 pr,float4 nf,float beamT,float3 ro,float3 rd,float limit,uint row,float jit){
 float a,b;float3 rel=ro-pr.xyz;
 if(!coneInterval(rel,rd,nf.xyz,.09,nf.w,pr.w,limit,a,b))return 0;
 float energy=0;
 [loop]for(int s=0;s<volume_samples;s++){float t=lerp(a,b,(s+jit)/volume_samples);float3 d=rel+rd*t;
  float ax=dot(d,nf.xyz),radius=length(d-nf.xyz*ax);float core=.07+ax*beamT,field=.09+ax*nf.w;
  float angular=exp(-.69314718*pow(radius/core,2))*(1-smoothstep(field*.8,field,radius));float edge=1-smoothstep(pr.w*.75,pr.w,ax);
  // beam_falloff 1 = inverse-square density (shafts fade as 1/distance); lower keeps them reading across the room.
  float medium=gHzOn?hzDenWisps(pr.xyz+d)*beamTrans(row,ax,pr.w):1;
  energy+=angular*edge*edge*.055*pow(.10+ax*ax,-beam_falloff)*viewT(t)*medium*(b-a)/volume_samples;}
 return energy;
}
// Bar glow from a point on an emitter: integral of 1/dist^2 along the ray, times extinction, faded to
// nothing by glow_range metres so a group can drop emitters its view cone cannot see. A wide range
// brings back the hall-filling wash of every bar's tail, at the cost of culling less.
float pointGlow(float3 p,float3 ro,float3 rd,float limit){float t0=dot(p-ro,rd);float3 c=ro+rd*t0;float d=max(length(p-c),.15);
 float w=saturate(1-d*d/(glow_range*glow_range));return (atan((limit-t0)/d)-atan((-t0)/d))/d*viewT(max(0,t0))*hzDen(ro+rd*clamp(t0,0,limit))*w*w;}
// Sphere against the group's view cone (apex at the camera).
bool sphereInCone(float3 c,float r,float3 ro,float3 dc,float tanA,float secA){
 float3 v=c-ro;if(dot(v,v)<=r*r)return true;float along=dot(v,dc);
 return along>-r&&length(v-dc*along)<along*tanA+r*secA;}
// Candidates k: [0,VM) mover beams, [VM,2VM) their ring glows, then the strobe rows, the venue's pixel-run emitters
// and the guests (sources.hlsl's rows, in its order).
#define VM SS_MOVERS
#define VS2 (2*SS_STROBES)
#define VG 64
#define V_STROBE0 (2*VM)
#define V_EMIT0 (2*VM+VS2)
#define V_GUEST0 (V_EMIT0+PV_EMITTERS)
#define V_TOTAL (V_GUEST0+VG)
groupshared float4 gB0[VM+VG],gB1[VM+VG],gB2[VM+VG];   // beams (movers, narrow guests): position+reach, axis+field tangent, energy+beam tangent
groupshared uint gBr[VM+VG];                            // each beam's row in beamt's table
groupshared float4 gW0[VM+VS2+VG],gW1[VM+VS2+VG],gW2[VM+VS2+VG];   // ring glows, strobes and wide guests, same layout
groupshared float4 gE0[PV_EMITTERS],gE1[PV_EMITTERS],gE2[PV_EMITTERS];      // pixel-run emitters: a+length, b, energy
groupshared uint gNB,gNW,gNE;
[numthreads(8,8,1)]void main(uint3 tid:SV_DispatchThreadID,uint3 gid:SV_GroupID,uint gi:SV_GroupIndex){
 uint w,h;OutputUAV.GetDimensions(w,h);bool inside=tid.x<w&&tid.y<h;float3 ro=_CameraPos;
 // the group's view cone: axis through its centre, half-angle out to its farthest corner ray
 float3 cr[4],dc=0;
 [unroll]for(uint k=0;k<4;k++){float2 uvc=(gid.xy*8+float2(k&1?8:0,k&2?8:0))/float2(w,h);
  float4 f=mul(_InvViewProjMatrix,float4(uvc.x*2-1,1-uvc.y*2,1,1));cr[k]=normalize(f.xyz/f.w-ro);dc+=cr[k];}
 dc=normalize(dc);float cosA=min(min(dot(dc,cr[0]),dot(dc,cr[1])),min(dot(dc,cr[2]),dot(dc,cr[3])));cosA=max(cosA*.998,.05);
 float tanA=sqrt(1-cosA*cosA)/cosA,secA=1/cosA;
 if(gi==0){gNB=0;gNW=0;gNE=0;}
 GroupMemoryBarrierWithGroupSync();
 if(haze>0&&beam_gain>0){[loop]for(uint k=gi;k<V_TOTAL;k+=64){
  if(k<VM){SsOptical b=Sources[k*2];if(b.active<.5||b.intensity<=0||!any(b.colour>0))continue;
   bool hit=false;float seg=b.reach/8;
   [loop]for(uint s=0;s<8&&!hit;s++){float t=(s+.5)*seg;hit=sphereInCone(b.position+b.normal*t,.09+(t+seg*.5)*b.field_tangent+seg*.5,ro,dc,tanA,secA);}
   if(hit){uint j;InterlockedAdd(gNB,1,j);gB0[j]=float4(b.position,b.reach);gB1[j]=float4(b.normal,b.field_tangent);gB2[j]=float4(b.colour*b.intensity,b.beam_tangent);gBr[j]=k;}}
  else if(k<V_EMIT0){SsOptical b;float f=1;
   if(k<V_STROBE0){if(Sources[(k-VM)*2].active<.5)continue;b=Sources[(k-VM)*2+1];if(b.active<.5||b.intensity<=0||!any(b.colour>0))continue;f=ring_haze;}
   else{b=Sources[k];if(b.active<.5||b.intensity<.002||!any(b.colour>0))continue;f=strobe_haze;}
   if(sphereInCone(b.position,b.reach,ro,dc,tanA,secA)){uint j;InterlockedAdd(gNW,1,j);
    gW0[j]=float4(b.position,b.reach);gW1[j]=float4(b.normal,b.field_tangent);gW2[j]=float4(b.colour*b.intensity*f,b.beam_tangent);}}
  else if(k>=V_GUEST0){SsOptical b=Sources[V_EMIT0+k-V_GUEST0];bool on=b.active>.5&&b.intensity>.001&&any(b.colour>0);
   if(on&&b.padding.x<3.5){bool hit=false;float seg=b.reach/8;
    [loop]for(uint s=0;s<8&&!hit;s++){float t=(s+.5)*seg;hit=sphereInCone(b.position+b.normal*t,.09+(t+seg*.5)*b.field_tangent+seg*.5,ro,dc,tanA,secA);}
    if(hit){uint j;InterlockedAdd(gNB,1,j);gB0[j]=float4(b.position,b.reach);gB1[j]=float4(b.normal,b.field_tangent);gB2[j]=float4(b.colour*b.intensity,b.beam_tangent);gBr[j]=VM+k-V_GUEST0;}}
   else if(on&&sphereInCone(b.position,b.reach,ro,dc,tanA,secA)){uint j;InterlockedAdd(gNW,1,j);
    gW0[j]=float4(b.position,b.reach);gW1[j]=float4(b.normal,b.field_tangent);gW2[j]=float4(b.colour*b.intensity*strobe_haze,b.beam_tangent);}}
  else if(bar_glow>0){uint e=k-V_EMIT0;float4 a=Venue[PV_EMIT+3*e],bb=Venue[PV_EMIT+3*e+1],r=Venue[PV_EMIT+3*e+2];if(!any(r.rgb>.001))continue;
   float len=length(bb.xyz-a.xyz);
   if(sphereInCone((a.xyz+bb.xyz)*.5,len*.5+glow_range,ro,dc,tanA,secA)){uint j;InterlockedAdd(gNE,1,j);
    gE0[j]=float4(a.xyz,len);gE1[j]=float4(bb.xyz,0);gE2[j]=float4(r.rgb*len*.004*bar_glow/max(beam_gain,.001),0);}}}}
 GroupMemoryBarrierWithGroupSync();
 if(!inside)return;
 // With taa on, each frame samples its own sub-pixel position (taa.hlsli), so the resolve averages 8 positions per
 // half-resolution pixel and a beam's edge behind the crowd stops stepping.
 float2 uv=(tid.xy+.5+(taa>.5?taaJitter():float2(0,0)))/float2(w,h),ndc=float2(uv.x*2-1,1-uv.y*2);
 float4 nearW=mul(_InvViewProjMatrix,float4(ndc,0,1)),farW=mul(_InvViewProjMatrix,float4(ndc,1,1));
 nearW/=nearW.w;farW/=farW.w;float3 rd=normalize(farW.xyz-nearW.xyz);
 float depth=_Tex1.SampleLevel(PointSampler,uv,0).a;float limit=depth>0?depth:_CameraFar;float3 result=0;
 uint vn,vs;Venue.GetDimensions(vn,vs);hzBegin(hzVenueDomain(vn,vn>4u?Venue[3]:0,vn>4u?Venue[4]:0));
 // interleaved gradient noise, moved on each frame: where along each interval this pixel samples
 float fr=(float)(((uint)_Frame)%64u);float jit=gHzOn?frac(52.9829189*frac(dot((float2)tid.xy+fr*5.588238,float2(.06711056,.00583715)))):.5;
 if(gHzOn)viewMarch(ro,rd,limit,jit);
 [loop]for(uint b=0;b<gNB;b++)result+=gB2[b].rgb*narrowIntegral(gB0[b],gB1[b],gB2[b].w,ro,rd,limit,gBr[b],jit);
 [loop]for(uint q=0;q<gNW;q++)result+=gW2[q].rgb*broadGlow(gW0[q],gW1[q],gW2[q].w,ro,rd,limit);
 [loop]for(uint e=0;e<gNE;e++){float3 a=gE0[e].xyz,bb=gE1[e].xyz;
  result+=gE2[e].rgb*(pointGlow(lerp(a,bb,.2),ro,rd,limit)+pointGlow(lerp(a,bb,.5),ro,rd,limit)+pointGlow(lerp(a,bb,.8),ro,rd,limit));}
 OutputUAV[tid.xy]=float4(result*haze*beam_gain,gHzOn?gTau[HV_STEPS]/gTauL:1);
}
