// BLINK_Previs / fixture_loop.hlsli: sphere-trace one laser's RAW 10 housings along a camera ray
// (laser_lab LS_Air fixture.hlsl main loop). Define FIX, FIX_COUNT and FIX_FN before including.
float4 FIX_FN(float3 eye,float3 rd,float4 result){
 if(FIX_COUNT<2)return result;
 uint count=min((uint)FIX[0].aperture.w,min(FIX_COUNT-1,4));
 [loop]for(uint j=1;j<=count;j++){
  float3 offset=eye-FIX[j].aperture.xyz;
  float3 ro=float3(dot(offset,FIX[j].right.xyz),dot(offset,FIX[j].up.xyz),dot(offset,FIX[j].forward.xyz));
  float3 ray=float3(dot(rd,FIX[j].right.xyz),dot(rd,FIX[j].up.xyz),dot(rd,FIX[j].forward.xyz));
  float2 bound=boundsHit(ro,ray);if(bound.y<max(bound.x,0)||bound.x>result.w)continue;
  float t=max(bound.x,0),eps=max(.00006,t*.00008);
  [loop]for(uint stepId=0;stepId<72&&t<=bound.y&&t<result.w;stepId++){
   float3 p=ro+ray*t;float2 hit=rawSDF(p,FIX[j].up.w);
   if(hit.x<eps){
    float2 e=float2(eps,0);
    float3 n=normalize(float3(rawSDF(p+e.xyy,FIX[j].up.w).x-rawSDF(p-e.xyy,FIX[j].up.w).x,rawSDF(p+e.yxy,FIX[j].up.w).x-rawSDF(p-e.yxy,FIX[j].up.w).x,rawSDF(p+e.yyx,FIX[j].up.w).x-rawSDF(p-e.yyx,FIX[j].up.w).x));
    float3 worldN=n.x*FIX[j].right.xyz+n.y*FIX[j].up.xyz+n.z*FIX[j].forward.xyz;
    result=float4(finishMaterial(p,n,worldN,-rd,(uint)hit.y,FIX[j].aperture.w),t);break;
   }
   t+=max(hit.x*.9,eps*.5);
  }
 }
 return result;
}
