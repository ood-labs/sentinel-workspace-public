RWTexture2D<float4> OutputUAV : register(u0);
struct LightRecord { float3 position; float type_id; float3 direction; float range; float3 color; float intensity; float2 size; float softness; float enabled; };
StructuredBuffer<LightRecord> Lights : register(t0);

float circle(float2 p,float r){ return length(p)-r; }
float segment(float2 p,float2 a,float2 b){ float2 pa=p-a,ba=b-a; return length(pa-ba*saturate(dot(pa,ba)/max(dot(ba,ba),.0001))); }

[numthreads(8,8,1)]
void main(uint3 id:SV_DispatchThreadID)
{
    if(id.x>=(uint)_Resolution.x||id.y>=(uint)_Resolution.y)return;
    float2 uv=((float2)id.xy+.5)/_Resolution.xy; float2 world=(uv-.5)*float2(10,7.5);
    float3 col=float3(.012,.018,.027);
    float2 grid=abs(frac(world)-.5); col+=.025*(1-smoothstep(.46,.5,min(grid.x,grid.y)));
    [loop] for(uint i=0;i<6;i++){
        LightRecord l=Lights[i]; if(l.enabled<.5)continue;
        float2 p=l.position.xz; float radius=.13+.035*l.range;
        float ring=1-smoothstep(.025,.07,abs(circle(world-p,radius)));
        float core=1-smoothstep(.04,.13,length(world-p));
        col+=l.color*(ring*.65+core)*saturate(.35+l.intensity*.28);
        float2 dir=normalize(l.direction.xz+float2(.0001,.0001));
        float arrow=1-smoothstep(.025,.06,segment(world,p,p+dir*.65)); col+=l.color*arrow*.75;
    }
    float border=min(min(uv.x,uv.y),min(1-uv.x,1-uv.y)); col+=float3(.95,.48,.16)*(1-smoothstep(.004,.012,border));
    OutputUAV[id.xy]=float4(pow(saturate(col),1/2.2),1);
}
