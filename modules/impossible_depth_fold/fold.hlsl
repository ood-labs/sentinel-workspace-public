RWTexture2D<float4> OutputUAV : register(u0);

float hash_fold(float p) {
    p = frac(p * 0.1031);
    p *= p + 33.33;
    p *= p + p;
    return frac(p);
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    if (tid.x >= (uint)_Resolution.x || tid.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)tid.xy + 0.5) / _Resolution.xy;
    float aspect = _Resolution.x / _Resolution.y;
    float2 p = float2((uv.x - fold_center.x) * aspect, uv.y - fold_center.y);

    float2 gridUv = uv * float2(cell_count * aspect, cell_count);
    float2 cellId = floor(gridUv);
    float2 local = frac(gridUv) - 0.5;
    float cellHash = hash_fold(cellId.x + cellId.y * 37.0 + fold_seed * 11.0);
    float diagonal = fold_mode == 0 ? local.x + local.y :
                     fold_mode == 1 ? local.x - local.y :
                     fold_mode == 2 ? max(abs(local.x), abs(local.y)) - 0.25 :
                                      min(abs(local.x + local.y), abs(local.x - local.y)) - 0.12;
    float side = diagonal >= 0.0 ? 1.0 : -1.0;
    float2 foldDir = normalize(float2(
        (cellHash - 0.5) * 1.4 + side,
        (hash_fold(cellHash * 91.0) - 0.5) * 1.2 - side * 0.35
    ));
    float focus = smoothstep(field_radius, 0.0, length(p));
    float ridge = smoothstep(0.18, 0.0, abs(diagonal));
    float2 displacement = foldDir * fold_strength * focus *
                          (0.25 + ridge * 0.75) / _Resolution.xy * float2(1.0, aspect);

    float perspectiveGain = 1.0 + perspective * side *
                            smoothstep(0.52, 0.0, length(local));
    float2 sampleUv = fold_center + (uv + displacement - fold_center) / perspectiveGain;
    sampleUv = saturate(sampleUv);

    float3 original = _Tex0.SampleLevel(LinearSampler, uv, 0).rgb;
    float3 folded = _Tex0.SampleLevel(LinearSampler, sampleUv, 0).rgb;
    float foldMix = fold_amount * focus;
    float3 col = lerp(original, folded, foldMix);

    float seam = smoothstep(seam_width / _Resolution.y, 0.0,
                            abs(diagonal) / max(cell_count, 1.0));
    float gridSeam = max(
        smoothstep(1.2 / _Resolution.x, 0.0, min(frac(gridUv.x), 1.0 - frac(gridUv.x)) / max(cell_count, 1.0)),
        smoothstep(1.2 / _Resolution.y, 0.0, min(frac(gridUv.y), 1.0 - frac(gridUv.y)) / max(cell_count, 1.0))
    );
    float3 seamColor = side > 0.0 ? float3(0.95, 0.055, 0.03) : float3(0.025, 0.027, 0.035);
    col = lerp(col, seamColor, max(seam, gridSeam * 0.32) * seam_gain * focus);

    float lift = side * ridge * focus * fold_lighting;
    col *= 1.0 + lift;
    OutputUAV[tid.xy] = float4(saturate(col), 1.0);
}

