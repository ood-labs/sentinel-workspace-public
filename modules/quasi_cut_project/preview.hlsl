struct QuasiRecord { float3 position; float scale; float phase; float family; float hue; float active; float3 normal; float pad; };
StructuredBuffer<QuasiRecord> Quasi : register(t0);
RWTexture2D<float4> OutputUAV : register(u0);

float3 pal(float t) { return 0.55 + 0.45*cos(6.28318*(t + float3(0.00,0.18,0.36))); }

[numthreads(8,8,1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 px = DTid.xy;
    if (px.x >= (uint)_Resolution.x || px.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)px + 0.5) / _Resolution;
    float asp = _Resolution.x / _Resolution.y;
    float2 p = (uv - 0.5) * float2(asp,1.0);
    float3 col = float3(0.002,0.004,0.012);
    [loop] for(uint i=0u;i<243u;i++) {
        QuasiRecord q = Quasi[i];
        if(q.active < 0.5) continue;
        float2 c = q.position.xz * 0.115;
        float d = length(p-c);
        float r = max(q.scale*0.0035,0.0015);
        float core = smoothstep(r,0.0,d);
        float glow = pow(max(0.0,1.0-d/(r*7.0)),2.0);
        col += pal(q.hue)*(core*2.0+glow*0.35);
    }
    float spokes = abs(sin(atan2(p.y,p.x)*5.0));
    col += (1.0-smoothstep(0.0,0.025,spokes))*0.025;
    OutputUAV[px] = float4(col,1.0);
}
