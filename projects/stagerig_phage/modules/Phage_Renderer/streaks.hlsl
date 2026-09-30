RWTexture2D<float4>OutputUAV:register(u0);
[numthreads(8,8,1)]void main(uint3 id:SV_DispatchThreadID){uint w,h,sw,sh;OutputUAV.GetDimensions(w,h);if(id.x>=w||id.y>=h)return;_Tex0.GetDimensions(sw,sh);float2 uv=(id.xy+.5)/float2(w,h);float3 c=0;float weight=0;
 for(int i=-16;i<=16;i++){float k=exp(-i*i/70.);float2 q=uv+float2(i*streak_length/16.,0);float3 v=_Tex0.SampleLevel(LinearSampler,clamp(q,.5/float2(sw,sh),1-.5/float2(sw,sh)),0).rgb; c+=v*k;weight+=k;}OutputUAV[id.xy]=float4(c/max(weight,.001),1);}
