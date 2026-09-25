#include "../_shared/rm_types.hlsli"
StructuredBuffer<RmOptical> Sources:register(t1);
RWTexture2D<float4> OutputUAV:register(u0);
bool coneInterval(float3 rel,float3 rd,float3 axis,float aperture,float slope,float reach,float limit,out float a,out float b){
 float z=dot(rel,axis),dz=dot(rd,axis);a=0;b=limit;
 if(abs(dz)<1e-7){if(z<0||z>reach)return false;}
 else{float t0=-z/dz,t1=(reach-z)/dz;a=max(a,min(t0,t1));b=min(b,max(t0,t1));}
 if(b<=a)return false;
 float r=aperture+slope*z,k=slope*dz;
 float A=1-dz*dz-k*k,B=2*(dot(rel,rd)-z*dz-r*k),C=dot(rel,rel)-z*z-r*r;
 if(abs(A)<1e-7){
  if(abs(B)<1e-7)return C<=0;
  float root=-C/B;if(B>0)b=min(b,root);else a=max(a,root);
 }else{
  float D=B*B-4*A*C;if(D<0)return A<0;
  float t0=(-B-sqrt(max(D,0)))/(2*A),t1=(-B+sqrt(max(D,0)))/(2*A);
  float lo=min(t0,t1),hi=max(t0,t1);
  if(A>0){a=max(a,lo);b=min(b,hi);}
  else if(a<lo)b=min(b,lo);else a=max(a,hi);
 }
 return b>a;
}
float broadIntegral(RmOptical o,float3 ro,float3 rd,float limit){
 float3 rel=ro-o.position;float b=dot(rel,rd),c=dot(rel,rel)-o.reach*o.reach,disc=b*b-c;
 if(disc<=0)return 0;
 float a=max(0,-b-sqrt(disc)),end=min(limit,-b+sqrt(disc));if(end<=a)return 0;
 float closest=clamp(-b,a,end),energy=0;
 [loop]for(int s=0;s<volume_samples*2;s++){
  bool before=s<volume_samples;int j=s%volume_samples;
  float u=(j+.5)/volume_samples,span=before?closest-a:end-closest,t=closest+(before?-1:1)*span*u*u,dt=2*span*u/volume_samples;
  float3 d=ro+rd*t-o.position;float ax=dot(d,o.normal),dist=length(d),slope=length(d-o.normal*ax)/max(.025,ax);
  float angular=exp(-.69314718*pow(slope/o.beam_tangent,2))*(1-smoothstep(o.field_tangent,o.field_tangent*1.3,slope));
  float edge=1-smoothstep(o.reach*.75,o.reach,dist);
  energy+=(ax>0?1:0)*angular*edge*edge*.15/(.06+dist*dist)*exp(-haze*t)*dt;
 }return energy;
}
float narrowIntegral(RmOptical o,float3 ro,float3 rd,float limit){
 float a,b;float3 rel=ro-o.position;
 if(!coneInterval(rel,rd,o.normal,.067,o.field_tangent,o.reach,limit,a,b))return 0;
 float energy=0;
 [loop]for(int s=0;s<volume_samples;s++){
  float t=lerp(a,b,(s+.5)/volume_samples);float3 d=rel+rd*t;
  float ax=dot(d,o.normal),radius=length(d-o.normal*ax);
  float core=.050+ax*o.beam_tangent,field=.067+ax*o.field_tangent;
  float angular=exp(-.69314718*pow(radius/core,2))*(1-smoothstep(field*.8,field,radius));
  float edge=1-smoothstep(o.reach*.75,o.reach,ax);
  energy+=angular*edge*edge*.055/(.10+ax*ax)*exp(-haze*t)*(b-a)/volume_samples;
 }return energy;
}
[numthreads(8,8,1)]void main(uint3 tid:SV_DispatchThreadID){
 uint w,h;OutputUAV.GetDimensions(w,h);if(tid.x>=w||tid.y>=h)return;
 float2 uv=(tid.xy+.5)/float2(w,h),ndc=float2(uv.x*2-1,1-uv.y*2);
 float4 nearW=mul(_InvViewProjMatrix,float4(ndc,0,1)),farW=mul(_InvViewProjMatrix,float4(ndc,1,1));
 nearW/=nearW.w;farW/=farW.w;float3 ro=_CameraPos,rd=normalize(farW.xyz-nearW.xyz);
 float depth=_Tex2.SampleLevel(PointSampler,uv,0).a;float limit=depth>0?depth:_CameraFar;float3 result=0;
 if(haze>0&&beam_gain>0){
  [loop]for(uint parent=0;parent<min(_Data0_Count,288u);parent++){
   if(_Data0[parent].active<.5)continue;
   RmOptical narrow=Sources[parent*2],broad=Sources[parent*2+1];
   if(narrow.active>.5&&narrow.intensity>0&&any(narrow.colour>0))result+=narrow.colour*narrow.intensity*narrowIntegral(narrow,ro,rd,limit);
   if(broad.active>.5&&broad.intensity>0&&any(broad.colour>0))result+=broad.colour*broad.intensity*broadIntegral(broad,ro,rd,limit);

  }
 }
 OutputUAV[tid.xy]=float4(result*haze*beam_gain,limit);
}
