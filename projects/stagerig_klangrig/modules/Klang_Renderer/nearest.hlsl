
RWTexture2D<float4>OutputUAV:register(u0);
[numthreads(8,8,1)]void main(uint3 id:SV_DispatchThreadID){uint w,h;OutputUAV.GetDimensions(w,h);if(id.x>=w||id.y>=h)return;float2 uv=(id.xy+.5)/float2(w,h);float4 a=_Tex0.SampleLevel(PointSampler,uv,0),b=_Tex1.SampleLevel(PointSampler,uv,0),c=_Tex2.SampleLevel(PointSampler,uv,0);if(a.a<=0||(b.a>0&&b.a<a.a))a=b;if(a.a<=0||(c.a>0&&c.a<a.a))a=c;float4 d=_Tex3.SampleLevel(PointSampler,uv,0);if(a.a<=0||(d.a>0&&d.a<a.a))a=d;float4 e=_Tex4.SampleLevel(PointSampler,uv,0);if(a.a<=0||(e.a>0&&e.a<a.a))a=e;OutputUAV[id.xy]=a;}
