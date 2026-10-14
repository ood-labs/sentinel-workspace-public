RWTexture2D<float4> OutputUAV : register(u0);

struct MaterialRecord {
    float3 base_color; float roughness;
    float3 secondary_color; float metallic;
    float texture_scale; float texture_strength; float pattern_id; float emissive;
    float specular; float normal_strength; float seed; float reserved;
};
StructuredBuffer<MaterialRecord> Materials : register(t0);

float hash21(float2 p){ return frac(sin(dot(p,float2(127.1,311.7)))*43758.5453); }

[numthreads(8,8,1)]
void main(uint3 id:SV_DispatchThreadID)
{
    if(id.x >= (uint)_Resolution.x || id.y >= (uint)_Resolution.y) return;
    float2 uv=((float2)id.xy+.5)/_Resolution.xy;
    float2 grid=uv*float2(6,4); uint2 cell=min((uint2)grid,uint2(5,3)); uint index=cell.y*6+cell.x;
    float2 q=frac(grid); MaterialRecord m=Materials[index];
    float pattern=.5+.5*sin((q.x+q.y*.37)*m.texture_scale*6.283+m.seed);
    pattern=lerp(hash21(floor(grid*32)),pattern,.55);
    float3 c=lerp(m.base_color,m.secondary_color,pattern*m.texture_strength);
    float bevel=smoothstep(.0,.08,min(min(q.x,q.y),min(1-q.x,1-q.y)));
    float light=.35+.65*saturate(dot(normalize(float3(q-.5,.34)),normalize(float3(-.4,-.5,1))));
    c*=light; c+=m.emissive*m.base_color*.20;
    c=lerp(float3(.012,.016,.022),c,bevel);
    OutputUAV[id.xy]=float4(pow(saturate(c/(1+c)),1/2.2),1);
}
