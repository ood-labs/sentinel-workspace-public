// BLINK_Previs / streak_seed.hlsl: the StageRig renderer's streak_seed.hlsl (StageRig), unchanged. Keeps
// only hot cores (peak 0.8..2.5 ramp) so streaks come from the lasers and apertures, not the wall.
RWTexture2D<float4>OutputUAV:register(u0);
[numthreads(8,8,1)]void main(uint3 id:SV_DispatchThreadID){uint w,h,sw,sh;OutputUAV.GetDimensions(w,h);if(id.x>=w||id.y>=h)return;_Tex0.GetDimensions(sw,sh);float2 uv=(id.xy+.5)/float2(w,h);float3 c=0;float weight=0;
 for(int i=-16;i<=16;i++){float k=exp(-i*i/70.);float2 q=uv+float2(i/(float)sw,0);float3 v=_Tex0.SampleLevel(LinearSampler,clamp(q,.5/float2(sw,sh),1-.5/float2(sw,sh)),0).rgb;float peak=max(v.r,max(v.g,v.b));v*=smoothstep(.8,2.5,peak); c+=v*k;weight+=k;}OutputUAV[id.xy]=float4(c/max(weight,.001),1);}
