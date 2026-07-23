RWTexture2D<float4> OutputUAV : register(u0);
[numthreads(8,8,1)]
void main(uint3 DTid:SV_DispatchThreadID)
{
    uint2 px=DTid.xy;if(px.x>=(uint)_Resolution.x||px.y>=(uint)_Resolution.y)return;
    float2 uv=((float2)px+0.5)/_Resolution;float2 p=uv-0.5;
    float a=feedback_rotation*0.003;float s=sin(a),c=cos(a);
    float2 q=float2(c*p.x-s*p.y,s*p.x+c*p.y)*(1.0-feedback_zoom*0.002)+0.5;
    float3 now=_Tex0.SampleLevel(LinearSampler,uv,0).rgb;
    float3 old=_Tex1.SampleLevel(LinearSampler,q,0).rgb;
    float lum=dot(now,float3(0.299,0.587,0.114));
    float gate=smoothstep(feedback_threshold,feedback_threshold+0.15,lum);
    // Energy-bounded memory: retain decayed historical maxima instead of
    // additively reinjecting the whole previous frame forever.
    float3 memory=old*feedback_decay*lerp(0.35,1.0,gate);
    float3 col=max(now,memory);
    col*=1.0-color_decay*float3(0.2,0.55,0.05);
    OutputUAV[px]=float4(col,1.0);
}
