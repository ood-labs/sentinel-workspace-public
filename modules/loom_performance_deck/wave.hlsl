// A damped two-state wave equation. R is the current height, G the previous
// height, and B remembers which event generation this pixel consumed.
RWTexture2D<float4> OutputUAV : register(u0);

float currentAt(int2 p) {
    int2 hi = int2((int)_Resolution.x - 1, (int)_Resolution.y - 1);
    return _Tex0.Load(int3(clamp(p, int2(0, 0), hi), 0)).r;
}

[numthreads(8, 8, 1)]
void main(uint3 id : SV_DispatchThreadID) {
    if (id.x >= (uint)_Resolution.x || id.y >= (uint)_Resolution.y) return;
    int2 px = int2(id.xy);
    float2 uv = ((float2)id.xy + 0.5) / _Resolution.xy;
    float4 old = _Tex0.Load(int3(px, 0));
    float4 ctrl = _Tex1.Load(int3(0, 0, 0));
    bool fresh = abs(ctrl.g - old.b) > 0.25;

    float cur = old.r;
    float prev = old.g;
    float lap = currentAt(px + int2(1, 0)) + currentAt(px - int2(1, 0))
              + currentAt(px + int2(0, 1)) + currentAt(px - int2(0, 1)) - 4.0 * cur;
    float propagation = lerp(0.08, 0.34, saturate(wave_speed));
    float next = (2.0 * cur - prev + lap * propagation) * pow(saturate(wave_decay), _DeltaTime * 60.0);

    if (fresh) {
        float aspect = _Resolution.x / max(_Resolution.y, 1.0);
        for (uint s = 0u; s < 8u; ++s) {
            float4 q = _Tex1.Load(int3(1 + (int)s, 0, 0));
            if (abs(q.w - ctrl.g) > 0.25) continue;
            if (q.z < 0.0) { next = 0.0; cur = 0.0; continue; }
            if (q.z > 0.0) {
                float2 d = (uv - q.xy) * float2(aspect, 1.0);
                float radius = ctrl.r * (q.z > 0.9 ? 0.42 : 0.28);
                float impulse = exp(-dot(d, d) / max(radius * radius * 0.12, 1e-6));
                next += impulse * injection_gain * q.z;
            }
        }
    }

    next = clamp(next, -2.0, 2.0);
    OutputUAV[id.xy] = float4(next, cur, ctrl.g, 1.0);
}
