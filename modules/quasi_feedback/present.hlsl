RWTexture2D<float4> OutputUAV : register(u0);
float3 sampleTrail(float2 uv){return _Tex0.SampleLevel(LinearSampler,uv,0).rgb;}
float hash21(float2 p){p=frac(p*float2(123.34,345.45));p+=dot(p,p+34.345);return frac(p.x*p.y);}
[numthreads(8,8,1)]
void main(uint3 DTid:SV_DispatchThreadID)
{
    uint2 px=DTid.xy;if(px.x>=(uint)_Resolution.x||px.y>=(uint)_Resolution.y)return;
    float2 uv=((float2)px+0.5)/_Resolution;float2 d=uv-0.5;
    float3 col;col.r=sampleTrail(uv+d*chroma*0.006).r;col.g=sampleTrail(uv).g;col.b=sampleTrail(uv-d*chroma*0.006).b;
    float3 bloom=0.0;[unroll]for(int i=0;i<8;i++){float a=(float)i*0.785398;float2 o=float2(cos(a),sin(a))*bloom_radius/_Resolution*900.0;bloom+=sampleTrail(uv+o);}bloom/=8.0;
    col+=max(bloom-bloom_threshold,0.0)*bloom_gain;col*=exposure;
    float l=dot(col,float3(0.299,0.587,0.114));col=lerp(l.xxx,col,saturation);
    col*=1.0-vignette*saturate(dot(d,d)*2.2);col=1.0-exp(-max(col,0.0));
    col+=(hash21((float2)px+frac(_Time)*73.0)-0.5)/255.0;
    OutputUAV[px]=float4(pow(saturate(col),1.0/2.2),1.0);
}
