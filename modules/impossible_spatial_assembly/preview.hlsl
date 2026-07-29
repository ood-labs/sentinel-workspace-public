struct FaceRecord {
    float2 center; float2 size;
    float2 axis_x; float2 axis_y;
    float depth; float face_kind; float palette; float pattern;
    float source_id; float group_id; float phase; float active;
};

StructuredBuffer<FaceRecord> Faces : register(t0);
RWTexture2D<float4> OutputUAV : register(u0);

float3 faceColor(FaceRecord f) {
    if (f.face_kind > 1.5) return float3(0.025, 0.025, 0.035);
    if (f.face_kind > 0.5) return float3(0.86, 0.14, 0.07);
    float k = fmod(f.palette, 5.0);
    if (k < 0.5) return float3(0.90, 0.88, 0.80);
    if (k < 1.5) return float3(0.08, 0.09, 0.12);
    if (k < 2.5) return float3(0.06, 0.14, 0.31);
    if (k < 3.5) return float3(0.92, 0.11, 0.07);
    return float3(0.94, 0.42, 0.05);
}

float sdOrientedBox(float2 uv, FaceRecord f, float aspect) {
    float2 p = float2((uv.x - f.center.x) * aspect, uv.y - f.center.y);
    float2 ax = normalize(float2(f.axis_x.x * aspect, f.axis_x.y));
    float2 ay = normalize(float2(f.axis_y.x * aspect, f.axis_y.y));
    float2 q = float2(dot(p, ax), dot(p, ay));
    float2 b = f.size * float2(aspect, 1.0) * 0.5;
    float2 d = abs(q) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    if (tid.x >= (uint)_Resolution.x || tid.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)tid.xy + 0.5) / _Resolution.xy;
    float aspect = _Resolution.x / _Resolution.y;
    float3 col = float3(0.045, 0.047, 0.055);
    float minorGrid = min(abs(frac(uv.x * 32.0) - 0.5), abs(frac(uv.y * 18.0) - 0.5));
    col += smoothstep(0.022, 0.0, minorGrid) * 0.018;

    [loop]
    for (uint i = 0u; i < 288u; ++i) {
        FaceRecord f = Faces[i];
        if (f.active < 0.5) continue;
        float d = sdOrientedBox(uv, f, aspect);
        float aa = 1.4 / _Resolution.y;
        float fill = smoothstep(aa, -aa, d);
        float edge = smoothstep(aa * 2.5, 0.0, abs(d));
        float alpha = f.face_kind > 1.5 ? 0.28 : (f.face_kind > 0.5 ? 0.78 : 0.88);
        float3 fc = faceColor(f) * (0.76 + 0.24 * saturate(f.depth + 0.2));
        col = lerp(col, fc, fill * alpha);
        col = lerp(col, float3(0.015, 0.015, 0.02), edge * 0.7);
    }

    OutputUAV[tid.xy] = float4(saturate(col), 1.0);
}

