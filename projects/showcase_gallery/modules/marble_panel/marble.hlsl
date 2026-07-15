// marble_panel — the melted fluid card (ref #8). A rectangular panel filled with a
// domain-warped fbm marble in the strata palette (indigo/orange/lime/ice veins + metallic
// sheen). The distortion IS the look — a self-animating fluid. Premultiplied-alpha RGBA
// (panel rect only), seedable. 2D screen-space; sits under the mass, framed by the wire.
#include "../_shared/sdf/sdf_ops.hlsli"
#include "../_shared/palette.hlsli"

RWTexture2D<float4> OutputUAV : register(u0);

float vnoise(float2 p)
{
    float2 i = floor(p), f = frac(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = sd_hash21(i), b = sd_hash21(i + float2(1, 0));
    float c = sd_hash21(i + float2(0, 1)), d = sd_hash21(i + float2(1, 1));
    return lerp(lerp(a, b, f.x), lerp(c, d, f.x), f.y);
}
float fbm(float2 p) { float s = 0, a = 0.5; [unroll] for (int i = 0; i < 5; i++) { s += a * vnoise(p); p *= 2.03; a *= 0.5; } return s; }

// marble colour ramp through the palette
float3 marbleRamp(float t)
{
    t = frac(t);
    if (t < 0.25) return lerp(str_palette(STR_INDIGO), str_palette(STR_ORANGE), t / 0.25);
    if (t < 0.5)  return lerp(str_palette(STR_ORANGE), str_palette(STR_LIME),  (t - 0.25) / 0.25);
    if (t < 0.75) return lerp(str_palette(STR_LIME),   str_palette(STR_ICE),   (t - 0.5) / 0.25);
    return lerp(str_palette(STR_ICE), str_palette(STR_INDIGO), (t - 0.75) / 0.25);
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 px = DTid.xy;
    if (px.x >= (uint)_Resolution.x || px.y >= (uint)_Resolution.y) return;
    float2 res = _Resolution.xy;
    float2 uv = ((float2)px + 0.5) / res;
    float aspect = res.x / res.y;
    float aa = 1.5 / res.y;

    // panel rect (point2D center + half-size, square in pixels via aspect)
    float2 c = panel_center;
    float2 hs = float2(panel_w, panel_h);
    float2 q = abs(uv - c) - hs;
    float inside = smoothstep(aa, -aa, max(q.x, q.y));
    if (inside < 0.003) { OutputUAV[px] = float4(0, 0, 0, 0); return; }

    // ---- domain-warped fbm marble ----
    float t = _Time * flow_speed;
    float2 puv = (uv - c) * float2(aspect, 1.0) * marble_scale + marble_seed;
    float2 w1 = float2(fbm(puv * warp_freq + t), fbm(puv * warp_freq + 5.2 - t * 0.7));
    float2 w2 = float2(fbm(puv * warp_freq * 2.1 + w1 * 3.0), fbm(puv * warp_freq * 2.1 + w1 * 3.0 + 9.1));
    float2 pw = puv + warp_amt * (w1 - 0.5) * 2.0 + warp_amt * 0.5 * (w2 - 0.5);
    float v = fbm(pw * 1.6 + 3.0);
    float veins = v * vein_count + fbm(pw * 3.0) * 1.5;
    float3 col = marbleRamp(veins);

    // metallic sheen from the marble gradient (fake normal off the noise slope)
    float e = 0.004;
    float gx = fbm((pw + float2(e, 0)) * 1.6) - fbm((pw - float2(e, 0)) * 1.6);
    float gy = fbm((pw + float2(0, e)) * 1.6) - fbm((pw - float2(0, e)) * 1.6);
    float3 n = normalize(float3(-gx, -gy, 0.12));
    float spec = pow(saturate(dot(n, normalize(float3(0.4, 0.6, 0.7)))), 24.0);
    col += spec * sheen * float3(1.0, 0.98, 0.92);
    col *= 0.75 + 0.5 * v;                              // depth shading

    // thin panel frame
    float fr = smoothstep(0.0, aa, min(-q.x, -q.y)) - smoothstep(0.0, 0.006, min(-q.x, -q.y));
    col = lerp(col, float3(0.9, 0.9, 0.92), saturate(fr) * 0.5);

    float a = inside * marble_opacity;
    OutputUAV[px] = float4(col * a, a);                 // premultiplied
}
