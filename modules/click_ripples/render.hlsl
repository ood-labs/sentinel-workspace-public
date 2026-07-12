// Maps the energy field through the selected palette and draws a brush-size
// cursor ring while the left button is held. Reads only derived state; the
// event ARRAY is consumed exclusively by the 1x1 events pass. Snapshot state
// (_ViewportPointerPosition, ViewportButtonDown, _ViewportWheelDelta) is safe
// to read in any pass.
RWTexture2D<float4> OutputUAV : register(u0);

float3 paletteColor(uint idx, float t) {
    if (idx == 0u) return lerp(float3(0.01, 0.02, 0.08), float3(0.15, 0.85, 1.0), t) + t * t * float3(0.8, 0.2, 0.6);
    if (idx == 1u) return lerp(float3(0.03, 0.01, 0.01), float3(1.0, 0.55, 0.10), t) + t * t * float3(0.9, 0.1, 0.3) * 0.4;
    if (idx == 2u) return lerp(float3(0.00, 0.03, 0.02), float3(0.25, 1.0, 0.45), t) + t * t * float3(0.9, 0.9, 0.2) * 0.3;
    return lerp(float3(0.03, 0.02, 0.05), float3(0.92, 0.92, 1.0), t);
}

[numthreads(8, 8, 1)]
void main(uint3 id : SV_DispatchThreadID) {
    if (id.x >= (uint)_Resolution.x || id.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)id.xy + 0.5) / _Resolution.xy;

    float4 ctrl = _Tex1.Load(int3(0, 0, 0));
    float e = saturate(_Tex0.Load(int3(id.xy, 0)).r);
    if (id.y <= 1u && id.x == 0u) e = 0.0; // bookkeeping pixels are not energy
    float t = pow(e, 0.65);
    float3 color = paletteColor((uint)round(ctrl.r), t);

    if (ViewportButtonDown(0)) {
        float aspect = _Resolution.x / _Resolution.y;
        float2 d = (uv - _ViewportPointerPosition) * float2(aspect, 1.0);
        float ring = abs(length(d) - ctrl.g * 0.5 * 0.38);
        color += smoothstep(0.006, 0.0, ring) * 0.6;
    }

    OutputUAV[id.xy] = float4(saturate(color), 1.0);
}
