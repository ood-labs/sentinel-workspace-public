// Multiscale HDR bloom: 13-tap weighted downsample, no hard threshold.
// Technique reference: https://learnopengl.com/Guest-Articles/2022/Phys.-Based-Bloom
RWTexture2D<float4>OutputUAV:register(u0);
float3 sampleAt(float2 uv,float2 d,float2 texel){return _Tex0.SampleLevel(LinearSampler,clamp(uv+d*texel,texel*.5,1-texel*.5),0).rgb;}
[numthreads(8,8,1)]void main(uint3 id:SV_DispatchThreadID){uint w,h,sw,sh;OutputUAV.GetDimensions(w,h);if(id.x>=w||id.y>=h)return;_Tex0.GetDimensions(sw,sh);float2 uv=(id.xy+.5)/float2(w,h),px=1./float2(sw,sh);float3 c=sampleAt(uv,0,px)*.125;
 for(int y=-1;y<=1;y++)for(int x=-1;x<=1;x++){if(x==0&&y==0)continue;float weight=(x==0||y==0)?.0625:.03125;c+=sampleAt(uv,float2(x,y)*2,px)*weight;}
 for(int y=-1;y<=1;y+=2)for(int x=-1;x<=1;x+=2)c+=sampleAt(uv,float2(x,y),px)*.125;
 OutputUAV[id.xy]=float4(c,1);}
