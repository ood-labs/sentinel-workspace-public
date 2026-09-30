// Current-frame, depth-tested screen-space reflections. No temporal history.
#include "../_shared/phage_venue.hlsli"
struct RoomSettings{float4 fill,material,tint,bounds,finish;};
StructuredBuffer<float4> Venue:register(t1);
RWTexture2D<float4> OutputUAV:register(u0);
bool project(float3 p,out float2 uv){float4 q=mul(_ViewProjMatrix,float4(p,1));uv=float2(q.x,-q.y)/max(q.w,.00001)*.5+.5;return q.w>0&&all(uv>.001)&&all(uv<.999);}
[numthreads(8,8,1)]void main(uint3 id:SV_DispatchThreadID){
 uint w,h;OutputUAV.GetDimensions(w,h);if(id.x>=w||id.y>=h)return;
 OutputUAV[id.xy]=0;RoomSettings room;room.fill=Venue[PV_ROOM];room.material=Venue[PV_ROOM+1];room.tint=Venue[PV_ROOM+2];room.bounds=Venue[PV_ROOM+3];room.finish=Venue[PV_ROOM+4];if(room.material.w<=0)return;
 float2 uv=(id.xy+.5)/float2(w,h),ndc=float2(uv.x*2-1,1-uv.y*2);
 float4 farW=mul(_InvViewProjMatrix,float4(ndc,1,1));float3 rd=normalize(farW.xyz/farW.w-_CameraPos);
 float4 base=_Tex0.SampleLevel(PointSampler,uv,0);if(base.a<=0)return;
 float3 p=_CameraPos+rd*base.a;if(abs(p.y-room.bounds.w)>.025||abs(p.x)>room.bounds.x*.5||abs(p.z)>room.bounds.y*.5)return;
 float3 dir=reflect(rd,float3(0,1,0));float t=.12,previous=t;float2 hitUV=0;bool found=false;float hitDepth=0;
 [loop]for(uint k=0;k<36;k++){
  float3 q=p+float3(0,.035,0)+dir*t;float2 suv;if(!project(q,suv))break;
  float d=_Tex0.SampleLevel(PointSampler,suv,0).a,rayDepth=length(q-_CameraPos);
  if(d>0&&rayDepth>d&&rayDepth-d<max(.35,t*.12)){
   float lo=previous,hi=t;
   [unroll]for(uint j=0;j<5;j++){float mid=(lo+hi)*.5;float3 m=p+float3(0,.035,0)+dir*mid;float2 mu;project(m,mu);float md=_Tex0.SampleLevel(PointSampler,mu,0).a;if(md>0&&length(m-_CameraPos)>md)hi=mid;else lo=mid;}
   float3 qh=p+float3(0,.035,0)+dir*hi;project(qh,hitUV);hitDepth=_Tex0.SampleLevel(PointSampler,hitUV,0).a;
   found=abs(length(qh-_CameraPos)-hitDepth)<.4;break;
  }
  previous=t;t+=.12+t*.18;
 }
 if(!found)return;
 float rough=room.material.z;float2 pixel=1/float2(w,h);float radius=1+rough*rough*16;
 float3 color=0;float weight=0;
 [unroll]for(uint k=0;k<5;k++){
  float2 offset=k==0?float2(0,0):k==1?float2(1,0):k==2?float2(-1,0):k==3?float2(0,1):float2(0,-1);
  float4 tap=_Tex0.SampleLevel(LinearSampler,hitUV+offset*pixel*radius,0);float a=exp(-abs(tap.a-hitDepth)*.4);color+=tap.rgb*a;weight+=a;
 }
 float edge=saturate(min(min(hitUV.x,1-hitUV.x),min(hitUV.y,1-hitUV.y))*20);
 float fresnel=.04+.96*pow(1-saturate(-rd.y),5);
 OutputUAV[id.xy]=float4(color/max(weight,.001)*fresnel*room.material.w*(1-rough*.65)*edge,1);
}
