// Depth merge of the six draw targets (alpha = distance to camera, 0 = empty).
RWTexture2D<float4>OutputUAV:register(u0);
void take(inout float4 a,float4 b){if(a.a<=0||(b.a>0&&b.a<a.a))a=b;}
[numthreads(8,8,1)]void main(uint3 id:SV_DispatchThreadID){uint w,h;OutputUAV.GetDimensions(w,h);if(id.x>=w||id.y>=h)return;float2 uv=(id.xy+.5)/float2(w,h);
 float4 a=_Tex0.SampleLevel(PointSampler,uv,0);take(a,_Tex1.SampleLevel(PointSampler,uv,0));take(a,_Tex2.SampleLevel(PointSampler,uv,0));
 take(a,_Tex3.SampleLevel(PointSampler,uv,0));take(a,_Tex4.SampleLevel(PointSampler,uv,0));take(a,_Tex5.SampleLevel(PointSampler,uv,0));OutputUAV[id.xy]=a;}
