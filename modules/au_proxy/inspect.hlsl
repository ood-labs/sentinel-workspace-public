// AUTOPSIA — the analysis lens's own inspection preview.
// Shows what the instrument observes, WHICH pixels will survive as blob
// candidates, and the real luma distribution with the threshold marked on it.
RWTexture2D<float4> Inspect : register(u0);
StructuredBuffer<uint4> Hist : register(t1);

float rectMask(float2 uv, float4 r) {
    return step(r.x, uv.x) * step(uv.x, r.z) * step(r.y, uv.y) * step(uv.y, r.w);
}

float rectEdge(float2 uv, float4 r, float2 texel) {
    float inner = rectMask(uv, float4(r.x + texel.x, r.y + texel.y, r.z - texel.x, r.w - texel.y));
    return rectMask(uv, r) - inner;
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    if (tid.x >= (uint)_Resolution.x || tid.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)tid.xy + 0.5) / _Resolution.xy;
    float2 texel = 1.0 / _Resolution.xy;

    float v = _Tex0.Load(int3(tid.xy, 0)).r;

    // observed image, held back so the overlay stays legible
    float3 col = float3(v, v, v) * 0.62;

    // ---- candidate mask: exactly what will survive the blob threshold -------
    float hatch = step(frac((uv.x * _Resolution.x + uv.y * _Resolution.y) / 7.0), 0.30);
    float candidate = step(mark_low, v) * (1.0 - step(mark_high + 1e-4, v));
    col += accent_color * candidate * hatch * 0.30;

    // ---- histogram panel ----------------------------------------------------
    float4 panel = float4(0.030, 0.760, 0.970, 0.968);
    float inPanel = rectMask(uv, panel);
    if (inPanel > 0.5) {
        col = float3(0.014, 0.015, 0.016);
        float local = (uv.x - panel.x) / max(panel.z - panel.x, 1e-5);
        uint bin = min((uint)(local * 64.0), 63u);
        float peak = max((float)Hist[64].x, 1.0);
        // log scale: the plate background is orders of magnitude larger than
        // specimen content, so a linear bar chart would read as empty
        float h = saturate(log(1.0 + (float)Hist[bin].x) / log(1.0 + peak));
        float up = (panel.w - uv.y) / max(panel.w - panel.y, 1e-5);
        float bar = step(up, h);
        col += float3(0.62, 0.63, 0.60) * bar * 0.85;

        // threshold markers, the only amber in the panel
        float mLow = 1.0 - smoothstep(0.0, 1.6 * texel.x, abs(local - mark_low));
        float mHigh = 1.0 - smoothstep(0.0, 1.6 * texel.x, abs(local - mark_high));
        col = lerp(col, accent_color, saturate(mLow + mHigh) * 0.92);

        // quartile rules
        float q = 1.0 - smoothstep(0.0, 1.1 * texel.x, min(min(abs(local - 0.25), abs(local - 0.5)), abs(local - 0.75)));
        col += float3(0.10, 0.105, 0.10) * q;
    }
    col += float3(0.34, 0.345, 0.33) * rectEdge(uv, panel, texel * 1.0);

    // ---- observation frame + corner registration ---------------------------
    float4 frame = float4(0.012, 0.012, 0.988, 0.988);
    col += float3(0.30, 0.305, 0.29) * rectEdge(uv, frame, texel * 1.0);

    float2 c = min(uv, 1.0 - uv);
    float corner = step(c.x, 0.055) * step(c.y, 0.0055) + step(c.y, 0.055) * step(c.x, 0.0055);
    col += float3(0.75, 0.755, 0.73) * saturate(corner);

    // centre cross of the observation field
    float cross = (1.0 - smoothstep(0.0, texel.x, abs(uv.x - 0.5))) * step(abs(uv.y - 0.5), 0.035)
                + (1.0 - smoothstep(0.0, texel.y, abs(uv.y - 0.5))) * step(abs(uv.x - 0.5), 0.022);
    col += float3(0.28, 0.285, 0.27) * saturate(cross);

    Inspect[tid.xy] = float4(saturate(col), 1.0);
}
