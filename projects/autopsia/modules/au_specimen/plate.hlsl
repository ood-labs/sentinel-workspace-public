// AUTOPSIA — the specimen plate. Topographic inscription of the living field.
// Constant-width contours (gradient-normalized), terraced body, bright nuclei
// that read as genuine masses to the observing Features node.
#include "types.hlsli"

StructuredBuffer<StimulusRecord> Stim : register(t1);
RWTexture2D<float4> Plate : register(u0);

float segDistance(float2 p, float2 a, float2 b) {
    float2 ab = b - a;
    float t = saturate(dot(p - a, ab) / max(dot(ab, ab), 1e-6));
    return length(p - (a + ab * t));
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    if (tid.x >= (uint)_Resolution.x || tid.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)tid.xy + 0.5) / _Resolution.xy;
    float aspect = _Resolution.x / max(_Resolution.y, 1.0);
    float2 p = (uv - 0.5) * float2(aspect, 1.0);

    uint fw, fh;
    _Tex0.GetDimensions(fw, fh);
    float texelRatio = (float)fw / max(_Resolution.x, 1.0); // field texels per screen pixel

    float4 field = _Tex0.SampleLevel(LinearSampler, uv, 0);
    float d = field.r;
    float2 grad = field.gb;          // density change per field texel
    float gmag = length(grad);
    float heat = field.a;

    // ---- contour system -----------------------------------------------------
    float bands = max(contour_bands, 2.0);
    float ph = d * bands;
    float phaseGradPerPixel = gmag * bands * texelRatio;
    float distPhase = abs(ph - round(ph));
    float pxDist = distPhase / max(phaseGradPerPixel, 1e-6);

    float w = max(contour_weight, 0.15);
    float minor = 1.0 - smoothstep(w, w + 1.15, pxDist);

    // index contours: every 5th level reads heavier, like a survey sheet
    float level = round(ph);
    float isIndex = step(0.5, 1.0 - abs(frac(level / 5.0) - 0.0) * 5.0);
    isIndex = (abs(fmod(abs(level), 5.0)) < 0.5) ? 1.0 : 0.0;
    float major = 1.0 - smoothstep(w * 1.9, w * 1.9 + 1.3, pxDist);

    float contour = max(minor * 0.55, major * isIndex);

    // ---- tissue mask: outside the specimen the plate stays truly empty ------
    float tissue = smoothstep(0.012, 0.055, d);
    // the shore: a single decisive stroke where tissue meets empty plate
    float shore = 1.0 - smoothstep(0.0, 1.55 * max(contour_weight, 0.15),
                                   abs(d - 0.030) / max(gmag * texelRatio, 1e-6));
    contour *= tissue;

    // ---- terraced body ------------------------------------------------------
    float terrace = floor(ph) / bands;
    float body = smoothstep(0.10, 0.72, terrace) * tissue;

    // ---- nuclei: compact high-density masses (the Features findings) --------
    float nuc = smoothstep(nucleus_level, nucleus_level + 0.10, d);
    float nucCore = smoothstep(nucleus_level + 0.07, nucleus_level + 0.15, d);

    // ---- membrane: strong-gradient boundaries -------------------------------
    float membrane = saturate(gmag * 26.0);
    membrane = smoothstep(0.18, 0.85, membrane) * tissue;

    // ---- registration structure: tick crosses, not a filled grid -----------
    float2 gridUV = uv * float2(32.0, 18.0);
    float2 gi = min(frac(gridUV), 1.0 - frac(gridUV));   // 0 exactly on a grid line
    float lineX = 1.0 - smoothstep(0.0, 0.018, gi.x);
    float lineY = 1.0 - smoothstep(0.0, 0.018, gi.y);
    // short ticks radiating from each intersection, plus a very faint full rule
    float ticks = saturate(lineX * (1.0 - smoothstep(0.06, 0.13, gi.y))
                         + lineY * (1.0 - smoothstep(0.06, 0.13, gi.x)));
    float rules = max(lineX, lineY) * 0.16;
    float grid = saturate(ticks + rules);

    // fine scan structure, very restrained
    float scan = smoothstep(0.35, 0.0, abs(frac(uv.y * _Resolution.y * 0.5) - 0.5));

    // ---- composite (monochrome instrument palette) --------------------------
    float3 col = float3(0.0016, 0.0018, 0.0020);
    col += float3(0.030, 0.032, 0.030) * grid * grid_gain;              // empty plate registration
    col += float3(0.068, 0.071, 0.069) * body * body_gain;
    col += float3(0.26, 0.265, 0.255) * membrane * membrane_gain;
    col += float3(0.80, 0.81, 0.785) * contour * contour_gain;
    col += float3(0.97, 0.975, 0.95) * shore * 0.95 * contour_gain;     // the decisive edge
    col += float3(0.88, 0.885, 0.86) * nuc * 0.22 * nucleus_gain;
    col += float3(1.00, 1.00, 0.985) * nucCore * 0.62 * nucleus_gain;
    col += float3(0.011, 0.012, 0.011) * scan * grid_gain;

    // ---- amber accent: reserved strictly for operator intervention ---------
    float amber = 0.0;
    [unroll] for (uint i = 0u; i < 16u; ++i) {
        StimulusRecord s = Stim[i];
        if (!stimulusActive(s)) continue;
        float2 sp = (s.position - 0.5) * float2(aspect, 1.0);
        float2 dv = p - sp;
        float r = max(s.radius, 0.012);
        float dist = length(dv);
        float ring = exp(-pow((dist - r) / max(r * 0.10, 0.0035), 2.0));
        float2 dir = normalize(s.direction + float2(1e-4, 1e-4));
        float leader = exp(-segDistance(p, sp, sp + dir * r * 1.7) * 300.0);
        float tick = exp(-pow((dist - r * 1.30) / max(r * 0.04, 0.002), 2.0))
                   * step(0.5, frac(atan2(dv.y, dv.x) * 2.8647));
        amber += (ring * 0.80 + leader * 0.30 + tick * 0.45) * s.strength;
    }
    // Heat is a broad field; at full contribution it floods the plate with a
    // glowing amber disc and the accent stops meaning "a finding". Keep it as a
    // faint bloom under the crisp ring and ticks that actually mark the deposit.
    amber += heat * 0.040;
    col += accent_color * amber * accent_gain;

    // ---- plate response -----------------------------------------------------
    float2 vc = (uv - 0.5) * float2(1.06, 1.72);
    float vignette = saturate(1.0 - dot(vc, vc) * 0.62);
    col *= 0.44 + 0.56 * vignette;
    col *= exposure;
    col = col / (1.0 + col);
    col = pow(saturate(col), 1.0 / 2.2);

    Plate[tid.xy] = float4(col, 1.0);
}
