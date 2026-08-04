// TP_Caustics / caustics_out.hlsl — publish wavelength-separated irradiance.
//
// The photon solve is deliberately scalar: tracing three atomic photon fields would triple its
// dominant cost. Water dispersion is small enough that the useful visible consequence is the
// coloured separation at a focus-line edge, so reconstruct it here by shifting the scalar
// irradiance along its local gradient. The luma correction keeps the result energy-neutral:
// dispersion adds colour, not brightness. A flat atlas remains exactly float3(1,1,1).
#include "../_shared/tessera.hlsli"

RWTexture2D<float4> OutputUAV : register(u0);

float4 regionBounds(float2 uv, out bool valid)
{
    bool cx = uv.x >= TP_A_C0 && uv.x <= TP_A_C1;
    bool cy = uv.y >= TP_A_C0 && uv.y <= TP_A_C1;
    valid = true;

    if (cx && cy)             return float4(TP_A_C0, TP_A_C0, TP_A_C1, TP_A_C1);
    if (cy && uv.x < TP_A_C0) return float4(TP_A_LO, TP_A_C0, TP_A_C0, TP_A_C1);
    if (cy && uv.x > TP_A_C1) return float4(TP_A_C1, TP_A_C0, TP_A_HI, TP_A_C1);
    if (cx && uv.y < TP_A_C0) return float4(TP_A_C0, TP_A_LO, TP_A_C1, TP_A_C0);
    if (cx && uv.y > TP_A_C1) return float4(TP_A_C0, TP_A_C1, TP_A_C1, TP_A_HI);

    valid = false;
    return 0.0;
}

float irradiance(float2 uv, float4 bounds, float2 halfTexel)
{
    uv = clamp(uv, bounds.xy + halfTexel, bounds.zw - halfTexel);
    return _Tex0.SampleLevel(LinearSampler, uv, 0).r;
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    uint W, H;
    OutputUAV.GetDimensions(W, H);
    if (tid.x >= W || tid.y >= H) return;

    float2 texel = 1.0 / float2(W, H);
    float2 uv = ((float2)tid.xy + 0.5) * texel;
    bool valid;
    float4 bounds = regionBounds(uv, valid);
    if (!valid)
    {
        OutputUAV[tid.xy] = 0.0;
        return;
    }

    float e = irradiance(uv, bounds, texel * 0.5);
    float eL = irradiance(uv - float2(texel.x, 0.0), bounds, texel * 0.5);
    float eR = irradiance(uv + float2(texel.x, 0.0), bounds, texel * 0.5);
    float eD = irradiance(uv - float2(0.0, texel.y), bounds, texel * 0.5);
    float eU = irradiance(uv + float2(0.0, texel.y), bounds, texel * 0.5);

    float2 grad = float2(eR - eL, eU - eD);
    float gradLen = length(grad);
    float2 direction = (gradLen > 1e-5) ? (grad / gradLen) : 0.0;
    float spread = max(dispersion, 0.0);

    // Atlas seams are bookkeeping, not optical edges. Fade the split before a region boundary
    // so the unfolded floor/wall cuts cannot acquire synthetic coloured outlines.
    float2 edgeLo = (uv - bounds.xy) / texel;
    float2 edgeHi = (bounds.zw - uv) / texel;
    float edgePx = min(min(edgeLo.x, edgeLo.y), min(edgeHi.x, edgeHi.y));
    spread *= smoothstep(spread + 1.0, spread + 3.0, edgePx);
    float2 shift = direction * texel * spread;

    // Red bends slightly less and blue slightly more. The symmetric approximation has no
    // preferred screen direction; the irradiance gradient supplies the only meaningful axis.
    float3 spectral = float3(irradiance(uv - shift, bounds, texel * 0.5),
                             e,
                             irradiance(uv + shift, bounds, texel * 0.5));

    float spectralLuma = dot(spectral, float3(0.2126, 0.7152, 0.0722));
    spectral = max(spectral + (e - spectralLuma).xxx, 0.0);

    // Hard guarantee at the unfolded-atlas cuts. Even the scalar reconstruction can slope
    // toward a neighbouring face there; that discontinuity is geometric bookkeeping and must
    // stay neutral rather than masquerading as dispersion.
    if (edgePx < 4.0) spectral = e.xxx;

    OutputUAV[tid.xy] = float4(spectral, 1.0);
}
