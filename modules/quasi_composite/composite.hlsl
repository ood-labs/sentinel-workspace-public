RWTexture2D<float4> OutputUAV : register(u0);
[numthreads(8,8,1)]
void main(uint3 DTid:SV_DispatchThreadID)
{
    uint2 px=DTid.xy;if(px.x>=(uint)_Resolution.x||px.y>=(uint)_Resolution.y)return;
    float2 uv=((float2)px+0.5)/_Resolution;
    float3 field=_Tex0.SampleLevel(LinearSampler,uv,0).rgb;
    float3 sdf=_Tex1.SampleLevel(LinearSampler,uv,0).rgb;
    float2 p=(uv-0.5)*float2(_Resolution.x/_Resolution.y,1.0);
    float ang=atan2(p.y,p.x);float r=length(p);
    float portal=smoothstep(portal_radius+portal_softness,portal_radius-portal_softness,r+sin(ang*5.0+phase*6.283)*portal_teeth);
    float latticeMask=saturate(dot(field,float3(0.299,0.587,0.114))*field_key);
    float mixv=saturate(portal*portal_mix+latticeMask*key_mix);
    float3 col=lerp(field*field_gain,sdf*sdf_gain,mixv);
    col+=field*sdf*cross_gain;
    float ring=pow(max(0.0,1.0-abs(r-portal_radius)/0.025),3.0);
    col+=ring*float3(0.3,0.75,1.2)*ring_gain;
    OutputUAV[px]=float4(col,1.0);
}
