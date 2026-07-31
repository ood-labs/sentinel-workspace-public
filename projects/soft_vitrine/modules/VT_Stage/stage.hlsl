// VT_Stage / stage.hlsl — the cyclorama the whole show sits in.
//
// A seamless studio wall curving into a floor: a vertical blue gradient with sprayed-plaster
// grain, a bright cyan seam where the two meet, and a bumpy dark floor whose texture
// compresses into perspective. It reads the horizon off the plan's stage record so the
// backdrop and the reflection compositor can never disagree about where the ground is.
//
// Output is linear HDR (RGBA16F) so VT_Post has real highlight headroom at the seam.
#include "../_shared/vitrine.hlsli"

StructuredBuffer<PlanRec> Plan : register(t0);
RWTexture2D<float4> OutputUAV : register(u0);

// four-stop vertical wall ramp, from the reference's near-black top to its cyan base
float3 wallRamp(float t)
{
    // Stops pushed late so the top third stays the near-black navy the reference keeps there.
    float3 c = lerp(wall_top.rgb, wall_mid.rgb, smoothstep(0.06, 0.62, t));
    c = lerp(c, wall_low.rgb, smoothstep(0.60, 0.955, t));
    c = lerp(c, horizon_col.rgb, smoothstep(0.88, 1.00, t) * horizon_lift);
    return c;
}

// Sprayed plaster height field. `freq` is in CYCLES PER UV, so a value near 200 gives the
// few-pixel orange-peel grain the reference wall actually has. Cheap blobby noise at freq ~5
// reads as haze, not as a surface.
float stuccoH(float2 p, float freq)
{
    return vt_fbm2(p * freq, 3) + 0.55 * vt_vnoise2(p * freq * 2.9 + 7.13);
}

// Two-tap gradient with the epsilon in real uv units. The earlier version scaled the epsilon
// by the frequency and sampled several screens away, which flattened the relief to nothing.
float3 plasterShade(float2 p, float freq, float amount, float3 base, float3 lightDir)
{
    float e = 1.15 / max(_Resolution.x, 1.0);
    float h0 = stuccoH(p, freq);
    float hx = stuccoH(p + float2(e, 0.0), freq);
    float hy = stuccoH(p + float2(0.0, e), freq);
    float2 grad = float2(hx - h0, hy - h0) / e;

    float3 n = normalize(float3(-grad * 0.0022, 1.0));
    float lam = saturate(dot(n, lightDir)) * 2.0 - 1.0;

    float3 c = base * (1.0 + lam * amount);
    c += base * (h0 - 1.05) * amount * 0.22;                  // shallow cavity darkening
    c += float3(1, 1, 1) * saturate(lam) * amount * 0.012;    // tiny specular on the peaks
    return c;
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)pixel + 0.5) / _Resolution.xy;

    float hz = clamp(Plan[PLAN_STAGE].pos.x, 0.05, 0.99);
    float depth = max(Plan[PLAN_STAGE].pos.y, 0.05);

    float3 col;

    if (uv.y < hz)
    {
        // ---------------------------------------------------------------- wall
        float t = saturate(uv.y / hz);
        col = wallRamp(t);

        // lateral warmth: the reference's wall is brighter toward the lower left, which is
        // what sells it as a lit cyclorama rather than a gradient fill
        float lateral = 1.0 + (0.5 - uv.x) * side_lift * (0.25 + 0.75 * t);
        col *= lateral;

        // plaster relief. Grain gets finer toward the horizon so the wall reads as receding.
        float freq = lerp(150.0, 320.0, t) * grain_scale;
        col = plasterShade(uv, freq, grain, col, normalize(float3(-0.46, -0.52, 0.72)));
    }
    else
    {
        // ---------------------------------------------------------------- floor
        // Perspective: distance along the ground goes 1/(y - hz), so texture compresses into
        // the seam exactly the way a real floor does.
        float fy = (uv.y - hz) / max(1.0 - hz, 1e-4);
        float persp = depth / max(fy + 0.035 * depth, 1e-4);
        float2 fp = float2((uv.x - 0.5) * persp * 0.55, persp * 0.30);

        float3 far = floor_far.rgb;
        float3 near = floor_col.rgb;
        col = lerp(far, near, smoothstep(0.0, 0.55, fy));

        // Coarse ground relief in the perspective-warped plane. Epsilon is taken in the SAME
        // warped space, so the grain shrinks toward the seam instead of banding across it.
        float ge = 0.006;
        float g  = vt_fbm2(fp * 14.0 * grain_scale, 4);
        float gx = vt_fbm2((fp + float2(ge, 0)) * 14.0 * grain_scale, 4);
        float gy = vt_fbm2((fp + float2(0, ge)) * 14.0 * grain_scale, 4);
        float3 n = normalize(float3(-(gx - g) / ge * 0.03, -(gy - g) / ge * 0.03, 1.0));
        float lam = saturate(dot(n, normalize(float3(-0.42, -0.40, 0.81))));
        col *= (1.0 + (lam * 2.0 - 1.0) * 0.55 * floor_grain);

        // wet sheen: a broad specular sweep, brightest just under the seam. This is the
        // floor's own light, not a reflection — VT_Composite adds the object mirrors on top.
        float sheen = exp(-fy * 3.1 / max(floor_gloss, 0.05)) * floor_gloss;
        float sweep = exp(-pow(abs(uv.x - 0.5 - sheen_offset) * 1.7, 2.0));
        col += horizon_col.rgb * sheen * sweep * 0.42;
        col += far * exp(-fy * 9.0) * 0.55;

        // the floor falls into near-black at the bottom of frame, as in the reference
        col *= lerp(1.0, 0.42, smoothstep(0.35, 1.0, fy));
    }

    // ---------------------------------------------------------------- seam
    // The bright line where wall meets floor, plus its bloom into both surfaces.
    // Soft band, not a laser line: the reference's seam is a glow with a bright core.
    float dSeam = abs(uv.y - hz);
    col += horizon_col.rgb * exp(-dSeam * (240.0 / max(seam_width, 0.15))) * seam_gain * 0.75;
    col += horizon_col.rgb * exp(-dSeam * (34.0 / max(seam_width, 0.15))) * seam_gain * 0.28;

    // ---------------------------------------------------------------- frame falloff
    float2 vq = (uv - 0.5) * 2.0;
    float vig = 1.0 - vignette * dot(vq, vq) * 0.34;
    col *= saturate(vig);

    col = max(col * exposure, 0.0);
    OutputUAV[pixel] = float4(col, 1.0);
}
