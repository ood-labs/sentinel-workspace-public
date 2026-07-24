RWTexture2D<float4> OutputUAV : register(u0);

struct Part {
    float4 transform_a;
    float4 transform_b;
    float4 rotation;
    float4 meta;
};
StructuredBuffer<Part> Parts : register(t0);

float3 groupColor(float groupId, float kind) {
    if (kind > 3.5 && kind < 4.5) return float3(0.48,0.43,0.35);
    if (groupId > 6.5) return float3(0.72,0.34,0.18);
    if (groupId > 5.5) return float3(0.82,0.72,0.43);
    if (groupId > 3.5) return float3(0.86,0.28,0.16);
    if (groupId > 2.5) return float3(0.62,0.66,0.70);
    return float3(0.86,0.86,0.82);
}

float2 rotate2(float2 p, float a) {
    float c = cos(a); float s = sin(a);
    return float2(c*p.x-s*p.y, s*p.x+c*p.y);
}

[numthreads(8,8,1)]
void main(uint3 DTid : SV_DispatchThreadID) {
    uint2 px = DTid.xy;
    if (px.x >= (uint)_Resolution.x || px.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)px + 0.5) / _Resolution.xy;
    float2 p = (uv - float2(0.50,0.50)) * float2(2.65, 2.65 * _Resolution.y / _Resolution.x);
    float3 col = float3(0.012,0.014,0.017);

    // Faint construction grid: the preview is an instrument, not a final look.
    float gx = smoothstep(0.008,0.0,abs(frac(p.x*4.0)-0.5)-0.48);
    float gy = smoothstep(0.008,0.0,abs(frac(p.y*4.0)-0.5)-0.48);
    col += float3(0.025,0.028,0.030) * (gx + gy);

    for (int i = 0; i < 20; ++i) {
        Part q = Parts[i];
        if (q.meta.w < 0.5) continue;
        float2 lp = rotate2(p - q.transform_a.xy, -q.rotation.z);
        float2 s = max(q.transform_b.xy, float2(0.015,0.015));
        float radial = length(lp / s) - 1.0;
        float edge = abs(radial);
        float solid = smoothstep(0.05,-0.03,radial);
        float body = (q.transform_a.w < 3.5 && q.transform_a.w > 2.5) ? solid :
                     ((q.transform_a.w < 3.5) ? solid : smoothstep(0.13,0.02,edge));
        float rim = smoothstep(0.06,0.008,edge);
        float3 c = groupColor(q.meta.y, q.transform_a.w);
        if (q.transform_a.w > 2.5 && q.transform_a.w < 3.5) {
            col = lerp(col, float3(0.005,0.006,0.008), body * 0.95);
            col += float3(0.38,0.12,0.06) * rim * 0.42;
        } else if (q.transform_a.w > 4.5) {
            col += c * smoothstep(0.045,0.006,edge) * 0.72;
        } else {
            col = lerp(col, c * (0.42 + 0.12 * q.meta.y), body * 0.76);
            col += c * rim * 0.55;
        }
        float2 mark = q.transform_a.xy;
        float marker = smoothstep(0.035,0.0,length(p-mark));
        col += float3(1.0,0.78,0.38) * marker * (q.meta.x < 1.0 ? 0.9 : 0.25);
    }
    col += float3(0.10,0.08,0.05) * smoothstep(0.008,0.0,abs(p.y+1.33));
    OutputUAV[px] = float4(saturate(col),1.0);
}
