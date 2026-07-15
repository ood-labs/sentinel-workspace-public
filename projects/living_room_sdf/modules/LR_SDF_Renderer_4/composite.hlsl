RWTexture2D<float4> OutputUAV : register(u0);
float4 nearestAt(int2 p){p=clamp(p,int2(0,0),int2(_Resolution.xy)-1);float4 a=_Tex0.Load(int3(p,0)),b=_Tex1.Load(int3(p,0)),c=_Tex2.Load(int3(p,0));float4 v=a.a<b.a?a:b;return c.a<v.a?c:v;}
float occSample(float center,int2 p)
{
    float z=nearestAt(p).a,delta=center-z;
    return saturate((delta-.018)*2.6)*saturate(1-delta*.24)*(z<999?1:0);
}
[numthreads(8,8,1)]
void main(uint3 id:SV_DispatchThreadID)
{
    if(id.x>=(uint)_Resolution.x||id.y>=(uint)_Resolution.y)return;
    int2 p=int2(id.xy);float4 v=nearestAt(p);
    float4 l=nearestAt(p+int2(-1,0)),r=nearestAt(p+int2(1,0)),u=nearestAt(p+int2(0,-1)),d=nearestAt(p+int2(0,1));
    float4 ul=nearestAt(p+int2(-1,-1)),ur=nearestAt(p+int2(1,-1)),dl=nearestAt(p+int2(-1,1)),dr=nearestAt(p+int2(1,1));
    float depthEdge=abs(l.a-r.a)+abs(u.a-d.a)+.5*(abs(ul.a-dr.a)+abs(ur.a-dl.a));
    float colorEdge=length(l.rgb-r.rgb)+length(u.rgb-d.rgb);float edge=saturate(depthEdge*.16+colorEdge*.18);
    float3 aa=(l.rgb+r.rgb+u.rgb+d.rgb)*.15+(ul.rgb+ur.rgb+dl.rgb+dr.rgb)*.10;
    float occ=0;
    occ+=occSample(v.a,p+int2(-2,0))+occSample(v.a,p+int2(2,0))+occSample(v.a,p+int2(0,-2))+occSample(v.a,p+int2(0,2));
    occ+=occSample(v.a,p+int2(-4,-3))+occSample(v.a,p+int2(4,-3))+occSample(v.a,p+int2(-4,3))+occSample(v.a,p+int2(4,3));
    occ+=occSample(v.a,p+int2(-8,0))+occSample(v.a,p+int2(8,0))+occSample(v.a,p+int2(0,-8))+occSample(v.a,p+int2(0,8));
    occ=saturate(occ/12)*saturate(ao_strength*.48)*(v.a<999?1:0);
    float contact=1-occ*.20;float aaMix=quality_mode==0?.30:.70;
    float3 color=lerp(v.rgb,aa,edge*aaMix)*contact;
    color*=1-.025*saturate((length((float2(id.xy)+.5)/_Resolution.xy-.5)-.32)*5);
    OutputUAV[id.xy]=float4(color,1);
}
