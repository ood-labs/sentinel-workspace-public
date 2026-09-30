// BLINK_Previs / bloom_up.hlsl: Klangrig 2 Klang_Renderer bloom_up.hlsl (StageRig), unchanged. Tent upsample
// of the coarser level blended over the finer one.
RWTexture2D<float4>OutputUAV:register(u0);
[numthreads(8,8,1)]void main(uint3 id:SV_DispatchThreadID){uint w,h,sw,sh;OutputUAV.GetDimensions(w,h);if(id.x>=w||id.y>=h)return;_Tex0.GetDimensions(sw,sh);float2 uv=(id.xy+.5)/float2(w,h),px=1./float2(sw,sh);float3 c=0;
 for(int y=-1;y<=1;y++)for(int x=-1;x<=1;x++){float weight=(x==0?2:1)*(y==0?2:1)/16.;c+=_Tex0.SampleLevel(LinearSampler,clamp(uv+float2(x,y)*px,px*.5,1-px*.5),0).rgb*weight;}
 float3 fine=_Tex1.SampleLevel(LinearSampler,uv,0).rgb;OutputUAV[id.xy]=float4(lerp(fine,c,.65),1);}
