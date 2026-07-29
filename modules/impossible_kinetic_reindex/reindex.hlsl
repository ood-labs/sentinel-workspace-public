RWTexture2D<float4> OutputUAV : register(u0);

float hash_index(float p) {
    p = frac(p * 0.1031);
    p *= p + 33.33;
    p *= p + p;
    return frac(p);
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    if (tid.x >= (uint)_Resolution.x || tid.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)tid.xy + 0.5) / _Resolution.xy;
    float2 gridCount = float2(columns, rows);
    float2 gridUv = uv * gridCount;
    float2 cell = floor(gridUv);
    float2 local = frac(gridUv);
    float cellIndex = cell.x + cell.y * columns;
    float h = hash_index(cellIndex + index_seed * 17.0);
    float quantized = floor(index_phase * index_steps) / max(index_steps, 1.0);

    float2 direction = reindex_mode == 0 ? float2(1.0, 0.0) :
                       reindex_mode == 1 ? float2(0.0, 1.0) :
                       reindex_mode == 2 ? normalize(float2(1.0, -0.62)) :
                                          normalize(float2(h - 0.5, hash_index(h * 37.0) - 0.5));
    float signedIndex = (h > 0.5 ? 1.0 : -1.0);
    float pulse = sin((quantized + h) * 6.2831853);
    float2 shiftCells = direction * signedIndex * pulse * travel;
    float2 shiftedUv = (cell + local + shiftCells * reindex_amount) / gridCount;

    if (mirror_tiles != 0 && h > 0.66) {
        float2 mirroredLocal = local;
        mirroredLocal.x = 1.0 - mirroredLocal.x;
        shiftedUv = (cell + mirroredLocal + shiftCells * reindex_amount) / gridCount;
    }

    float3 original = _Tex0.SampleLevel(LinearSampler, uv, 0).rgb;
    float3 shifted = _Tex0.SampleLevel(LinearSampler, saturate(shiftedUv), 0).rgb;
    float stagger = smoothstep(0.0, 0.18, frac(index_phase + h)) *
                    smoothstep(1.0, 0.82, frac(index_phase + h));
    float localMix = reindex_amount * lerp(1.0, stagger, stagger_mix);
    float3 col = lerp(original, shifted, localMix);

    float gutterDist = min(min(local.x, 1.0 - local.x), min(local.y, 1.0 - local.y));
    float gutter = smoothstep(gutter_width + 1.5 / _Resolution.y, gutter_width, gutterDist);
    float3 gutterColor = fmod(cellIndex, 7.0) < 1.0 ?
                         float3(0.94, 0.055, 0.03) :
                         float3(0.018, 0.020, 0.028);
    col = lerp(col, gutterColor, gutter * gutter_gain * reindex_amount);

    OutputUAV[tid.xy] = float4(saturate(col), 1.0);
}

