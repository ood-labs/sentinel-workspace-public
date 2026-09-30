struct Level { float value; float raw; float live; float pad; };
StructuredBuffer<Level> _Level : register(t0);

float4 main(VS_OUTPUT input) : SV_TARGET0 {
    Level l = _Level[0];
    float lit = input.Uv.x <= l.value ? 1.0 : 0.12;
    float3 tint = l.live > 0.5 ? float3(0.35, 0.85, 1.0) : float3(0.5, 0.5, 0.5);
    return float4(tint * lit, 1.0);
}
