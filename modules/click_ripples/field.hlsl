// Full-resolution energy field. Never reads _ViewportEvents; consumes the
// splat queue the events pass wrote into the state buffer, exactly once per
// queue generation (last consumed generation is remembered at field (0,1)).
RWTexture2D<float4> OutputUAV : register(u0);

[numthreads(8, 8, 1)]
void main(uint3 id : SV_DispatchThreadID) {
    if (id.x >= (uint)_Resolution.x || id.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)id.xy + 0.5) / _Resolution.xy;

    float4 ctrl = _Tex1.Load(int3(0, 0, 0));          // state: palette, brush, queue gen
    float lastGen = _Tex0.Load(int3(0, 1, 0)).r;      // field: last consumed generation
    bool fresh = (ctrl.b != lastGen);

    if (id.x == 0u && id.y == 1u) {                   // generation bookkeeping pixel
        OutputUAV[id.xy] = float4(ctrl.b, 0.0, 0.0, 1.0);
        return;
    }

    // CRITICAL: modules cook at an uncapped rate (often far above display rate),
    // so per-cook constants are wrong. Scale decay by _DeltaTime: this behaves
    // like `decay` per frame at 60 FPS regardless of the actual cook rate.
    float energy = _Tex0.Load(int3(id.xy, 0)).r * pow(saturate(decay), _DeltaTime * 60.0);

    if (fresh) {
        float aspect = _Resolution.x / _Resolution.y;
        for (uint s = 0; s < 8u; ++s) {
            float4 q = _Tex1.Load(int3(1 + (int)s, 0, 0));
            if (q.w != ctrl.b) continue;              // stale queue entry
            if (q.z < 0.0) { energy = 0.0; continue; } // clear request
            if (q.z > 0.0) {
                float2 d = (uv - q.xy) * float2(aspect, 1.0);
                float r = ctrl.g * (q.z > 0.9 ? 0.5 : 0.3);
                energy += splat_gain * q.z * exp(-dot(d, d) / max(r * r * 0.15, 1e-6));
            }
        }
    }

    OutputUAV[id.xy] = float4(min(energy, 4.0), 0.0, 0.0, 1.0);
}
