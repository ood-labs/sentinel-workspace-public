struct LightRecord {
    float4 position_radius;
    float4 color_intensity;
    float4 direction_type;
};
RWStructuredBuffer<LightRecord> OutputBuffer : register(u0);

void writeLight(int i, float3 pos, float radius, float3 color, float intensity, float3 dir, float type) {
    LightRecord l;
    l.position_radius = float4(pos, radius);
    l.color_intensity = float4(color, intensity);
    l.direction_type = float4(dir, type);
    OutputBuffer[i] = l;
}

[numthreads(1,1,1)]
void main(uint3 id : SV_DispatchThreadID) {
    float t = _Time * orbit_speed;
    float pulse = pulse_amount;
    writeLight(0, float3(-2.6, 2.8, 3.2), 6.0, float3(0.82,0.90,1.0), key_intensity, normalize(float3(0.3,-0.6,-1.0)), 0);
    writeLight(1, float3(2.4, 0.4, 2.0), 5.0, float3(0.30,0.38,0.52), fill_intensity, normalize(float3(-0.4,0.0,-1.0)), 0);
    writeLight(2, float3(-1.8, 1.4, -2.0), 4.0, float3(0.42,0.22,0.12), rim_intensity + pulse*0.8, normalize(float3(0.2,-0.1,1.0)), 1);
    writeLight(3, float3(1.7, 1.1, -2.3), 4.0, float3(0.34,0.28,0.24), rim_intensity + pulse*0.5, normalize(float3(-0.2,0.0,1.0)), 1);
    writeLight(4, float3(sin(t)*2.5, 0.3+cos(t*0.7)*0.7, 1.8), 3.5, float3(1.0,0.48,0.18), slash_intensity, normalize(float3(0.0,0.0,-1.0)), 1);
    writeLight(5, float3(cos(t*0.63)*2.2, 1.8+sin(t)*0.5, 0.8), 3.5, float3(0.82,0.54,0.30), slash_intensity, normalize(float3(0.0,-0.2,-1.0)), 1);
    writeLight(6, float3(0.0,-1.0,1.0), 1.8, float3(0.46,0.30,0.20), base_intensity, normalize(float3(0.0,1.0,-0.2)), 2);
    writeLight(7, float3(0.0,3.5,-0.5), 1.2, float3(1.0,0.30,0.10), pulse*1.4, normalize(float3(0.0,-1.0,0.0)), 1);
}
