// Surfaces (+ floor reflections) attenuated through the haze, plus the half-resolution in-scatter.
RWTexture2D<float4>OutputUAV:register(u0);
[numthreads(8,8,1)]void main(uint3 id:SV_DispatchThreadID){uint w,h;OutputUAV.GetDimensions(w,h);if(id.x>=w||id.y>=h)return;float2 uv=(id.xy+.5)/float2(w,h);
 float4 s=_Tex0.SampleLevel(PointSampler,uv,0);float depth=s.a>0?s.a:_CameraFar;
 OutputUAV[id.xy]=float4((s.rgb+_Tex2.SampleLevel(PointSampler,uv,0).rgb)*exp(-haze*depth)+_Tex1.SampleLevel(LinearSampler,uv,0).rgb,1);}
