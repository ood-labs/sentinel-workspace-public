RWTexture2D<float4> OutputUAV : register(u0);

float3 sampleScene(float2 uv){ uint2 p=(uint2)(saturate(uv)*(_Resolution.xy-1)); return _Tex0.Load(int3(p,0)).rgb; }

[numthreads(8,8,1)]
void main(uint3 DTid:SV_DispatchThreadID)
{
    uint2 px=DTid.xy; if(px.x>=(uint)_Resolution.x||px.y>=(uint)_Resolution.y)return;
    float2 uv=((float2)px+.5)/_Resolution.xy;
    float3 c=sampleScene(uv);
    float2 texel=1.0/_Resolution.xy; float3 bloom=0;
    [unroll] for(int j=0;j<8;j++){ float a=j*.785398; float2 o=float2(cos(a),sin(a))*bloom_radius; float3 s=sampleScene(uv+o); bloom+=max(s-bloom_threshold,0); }
    c+=bloom*(bloom_intensity/8.0);
    c*=exposure; c=(c-.5)*contrast+.5;
    float l=dot(c,float3(.2126,.7152,.0722)); c=lerp(l.xxx,c,saturation);
    c=lerp(c,c*shadow_tint*2.0,(1-saturate(l*2))*split_tone);
    c=lerp(c,c*highlight_tint*1.25,saturate((l-.5)*2)*split_tone);
    float2 q=uv*(1-uv); float vig=pow(saturate(16*q.x*q.y),vignette); c*=lerp(1,vig,.72);
    float grain=frac(sin(dot(float2(px),float2(12.9898,78.233)))*43758.5453)-.5; c+=grain*grain_amount;
    OutputUAV[px]=float4(saturate(c),1);
}
