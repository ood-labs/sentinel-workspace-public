#include "../_shared/anim/anim.hlsli"

RWTexture2D<float4> OutputUAV : register(u0);

float2 rotateField(float2 p, float a)
{
    float s = sin(a);
    float c = cos(a);
    return float2(c * p.x - s * p.y, s * p.x + c * p.y);
}

float organicField(float2 p, float phase)
{
    float2 q = p * field_scale;

    if (field_mode == 0)
    {
        // Advect the entire domain, not only the noise seed. This makes contour
        // topology travel through frame and continuously refreshes real Features.
        float domainTurn = sin(phase * 0.43) * 0.24;
        float2 advected = rotateField(q, domainTurn) + phase * float2(0.31, -0.19);
        float wx = fbm2D(advected * 0.58 + phase * float2(0.11, -0.07), 4);
        float wy = fbm2D(advected * 0.61 + phase * float2(-0.08, 0.13) + 13.71, 4);
        float2 warped = advected + (float2(wx, wy) - 0.5) * warp_amount * 2.2;
        return fbm2D(warped + phase * float2(0.09, -0.055), 5);
    }

    if (field_mode == 1)
    {
        float2 advected = rotateField(q, sin(phase * 0.36) * 0.16) + phase * float2(0.22, 0.09);
        float n = fbm2D(advected * 0.47 + float2(phase * 0.08, phase * 0.04), 4);
        float2 bent = advected + (n - 0.5) * warp_amount * float2(1.7, -1.2);
        float a = sin(bent.x * 1.35 + bent.y * 0.42 + phase * 0.9);
        float b = cos(bent.y * 1.71 - bent.x * 0.31 - phase * 0.63);
        float c = sin(length(bent - float2(0.8, -0.35)) * 2.4 - phase * 0.74);
        return saturate(0.5 + (a + b + c) / 6.0 + (n - 0.5) * 0.28);
    }

    float2 advected = rotateField(q, sin(phase * 0.29) * 0.12) + phase * float2(0.18, -0.11);
    float n0 = fbm2D(advected * 0.52 + float2(phase * 0.07, -phase * 0.03), 5);
    float n1 = fbm2D(rotateField(advected, 1.047) * 0.78 + float2(-phase * 0.06, phase * 0.05), 4);
    float fold = 1.0 - abs(n0 * 2.0 - 1.0);
    float crease = 1.0 - abs(n1 * 2.0 - 1.0);
    return saturate(lerp(fold, fold * crease * 1.45, warp_amount * 0.42));
}

float contourLine(float value, float density, float width)
{
    float d = abs(frac(value * density) - 0.5);
    return 1.0 - smoothstep(width, width * 2.4, d);
}

[numthreads(8, 8, 1)]
void main(uint3 id : SV_DispatchThreadID)
{
    if (id.x >= (uint)_Resolution.x || id.y >= (uint)_Resolution.y) return;

    float2 uv = ((float2)id.xy + 0.5) / _Resolution.xy;
    float aspect = _Resolution.x / _Resolution.y;
    float2 p = (uv - 0.5) * float2(aspect, 1.0);
    float4 state = _Tex0.Load(int3(0, 0, 0));
    float phase = state.r;

    float field = organicField(p, phase);
    float eps = 1.75 / _Resolution.y;
    float fieldX = organicField(p + float2(eps, 0.0), phase);
    float fieldY = organicField(p + float2(0.0, eps), phase);
    float gradient = saturate(length(float2(fieldX - field, fieldY - field)) / max(eps, 1e-5) * 0.11);

    float primary = contourLine(field, max(2.0, contour_density * 0.24), contour_width * 1.35);
    float2 p2 = rotateField(p * 0.91 + float2(0.13, -0.07), 0.73);
    float secondaryField = organicField(p2, phase + 1.83);
    float secondary = contourLine(secondaryField, max(2.0, contour_density * 0.19), contour_width * 1.55);

    // Broad anti-aliased fluid masses are the semantic signal. The sparse
    // internal contour is subordinate material detail, not the detector target.
    float fluidMass = smoothstep(field_threshold - 0.025, field_threshold + 0.035, field);
    float boundaryDistance = abs(field - field_threshold);
    float fluidBoundary = 1.0 - smoothstep(contour_width * 0.42, contour_width * 1.65, boundaryDistance);
    float body = fluidMass * (0.50 + fill_amount * 0.85) * (0.82 + gradient * 0.18);
    float interiorFlow = primary * fluidMass * (0.08 + secondary_contours * 0.08);
    float crossCurrent = secondary * fluidMass * secondary_contours * 0.035;

    float gray = 0.002 + body + fluidBoundary * contour_intensity * 0.48;
    gray += interiorFlow + crossCurrent;
    float scan = step(0.5, frac(uv.y * _Resolution.y * 0.5)) * scanline_amount;
    gray = max(0.0, gray - scan);
    gray = pow(saturate(gray), max(contrast, 0.2));

    float grain = (hash21((float2)id.xy + floor(phase * 12.0)) - 0.5) * grain_amount;
    float3 color = saturate(gray + grain).xxx;

    float vignette = smoothstep(1.05, 0.28, length((uv - 0.5) * float2(0.82, 1.0)));
    color *= lerp(0.58, 1.0, vignette);
    OutputUAV[id.xy] = float4(saturate(color), 1.0);
}
