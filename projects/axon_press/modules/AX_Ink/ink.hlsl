// AX_Ink / ink.hlsl — the printed surface.
//
// The reference is not a render of a scene; it is INK ON PAPER, and about half of what makes it
// look the way it does happens after the image exists. The plates are slightly out of register,
// the ink gains at every edge, the stock has fibre in it, and nothing on the page is emissive.
//
// This node is that pass and nothing else. It changes no geometry, no palette and no
// composition — anything here that would change what the image IS belongs upstream in AX_Plan
// (placement, focus, travel) or AX_Press (form, plate, ink weight).
//
// THE SURFACE IS SCREEN-FIXED, DELIBERATELY. Grain, registration and paper tone do not move with
// the fall, because they are the sheet you are looking THROUGH rather than anything in the
// collage. That single decision is most of what stops the result reading as a 3D flythrough.
RWTexture2D<float4> OutputUAV : register(u0);
Texture2D<float4> Src : register(t0);

#define TAP(UV) Src[clamp(int2((UV) * _Resolution.xy), int2(0, 0), \
                          int2((int)_Resolution.x - 1, (int)_Resolution.y - 1))]

float ih(float2 p) { return frac(sin(dot(p, float2(127.1, 311.7))) * 43758.5453); }

// A sheet does not resolve infinitely. This is a real press property AND the last line of
// defence against sub-pixel shimmer out of a scene that is fractal by construction — every
// octave deeper adds structure finer than the one above it, so something has to band-limit.
float3 tapSoft(float2 uv, float2 texel, float r)
{
    if (r <= 0.01) return TAP(uv).rgb;
    float3 s = TAP(uv).rgb * 0.36;
    s += TAP(uv + float2( r, 0.0) * texel).rgb * 0.16;
    s += TAP(uv + float2(-r, 0.0) * texel).rgb * 0.16;
    s += TAP(uv + float2(0.0,  r) * texel).rgb * 0.16;
    s += TAP(uv + float2(0.0, -r) * texel).rgb * 0.16;
    return s;
}

// value noise, for paper fibre
float ivn(float2 p)
{
    float2 i = floor(p), f = frac(p);
    f = f * f * (3.0 - 2.0 * f);
    return lerp(lerp(ih(i), ih(i + float2(1, 0)), f.x),
                lerp(ih(i + float2(0, 1)), ih(i + float2(1, 1)), f.x), f.y);
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pix = DTid.xy;
    if (pix.x >= (uint)_Resolution.x || pix.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)pix + 0.5) / _Resolution.xy;
    float2 texel = 1.0 / _Resolution.xy;
    float aspect = _Resolution.x / max(_Resolution.y, 1.0);

    // --- MISREGISTRATION. The three plates are laid down fractions of a millimetre apart. Kept
    // in the sub-two-pixel range on purpose: past that it stops reading as bad printing and
    // starts reading as a chromatic aberration filter, which is a screen artifact, not a press
    // one. Each plate gets its OWN direction — a single shared axis reads as motion blur.
    float3 col;
    {
        float r = reg * texel.y;
        float2 oR = float2( 0.94,  0.34) * r;
        float2 oG = float2(-0.42,  0.91) * r;
        float2 oB = float2(-0.55, -0.83) * r;
        float sr = soften;
        col = float3(tapSoft(uv + oR, texel, sr).r,
                     tapSoft(uv + oG, texel, sr).g,
                     tapSoft(uv + oB, texel, sr).b);
    }

    // --- DOT GAIN. Ink spreads where it lands, so a printed edge is fatter and darker than the
    // artwork. Taking the MINIMUM of a small neighbourhood grows dark into light, which is what
    // gain physically does; a symmetric blur just softens the image and loses the hard cut edges
    // that make a collage a collage.
    if (bleed > 0.001)
    {
        float3 mn = col;
        [unroll] for (int k = 0; k < 4; k++)
        {
            float2 d = (k == 0) ? float2(1, 0) : ((k == 1) ? float2(-1, 0)
                     : ((k == 2) ? float2(0, 1) : float2(0, -1)));
            mn = min(mn, TAP(uv + d * texel * (1.0 + bleed * 2.0)).rgb);
        }
        col = lerp(col, min(col, mn * 0.35 + col * 0.65), bleed);
    }

    // --- HALFTONE SCREEN. The whole page is a reproduction, so it carries one screen of its own
    // over everything, at a different angle from anything in the artwork. Low by default: the
    // plates upstream already resolve their own dots, and two screens fighting is moiré.
    if (screen_amt > 0.001)
    {
        float a = 0.4363;                                  // ~25 degrees, the usual black angle
        float2 sp = float2(uv.x * aspect * cos(a) - uv.y * sin(a),
                           uv.x * aspect * sin(a) + uv.y * cos(a)) * max(screen_lpi, 8.0);
        float2 f = frac(sp) - 0.5;
        float lum = dot(col, float3(0.2126, 0.7152, 0.0722));
        float rad = sqrt(saturate(1.0 - lum)) * 0.62;
        float dot_ = 1.0 - smoothstep(rad - 0.12, rad + 0.05, length(f));
        col = lerp(col, col * lerp(1.12, 0.72, dot_), screen_amt);
    }

    // --- PAPER. Fibre at two scales, plus a slow blotch in the stock itself. Multiplied rather
    // than added: paper takes ink away, it never emits.
    if (grain > 0.001)
    {
        float2 gp = uv * _Resolution.xy / max(grain_scale, 0.25);
        float fib = ivn(gp) * 0.62 + ivn(gp * 3.1 + 17.0) * 0.38;
        float blotch = ivn(uv * 6.0 + 3.0);
        col *= 1.0 - grain * (0.34 * (fib - 0.5) + 0.16 * (blotch - 0.5) + 0.10);
    }

    // --- TONE. Ink on stock has no true black and no emissive white: the shadows lift onto the
    // paper's own tone and the highlights stop at what the sheet reflects. Desaturating slightly
    // toward that warm point is what turns screen colour into printed colour.
    {
        float3 stock = float3(0.878, 0.855, 0.804);
        float lum = dot(col, float3(0.2126, 0.7152, 0.0722));
        col = lerp(col, lum.xxx, saturate(desat));
        col = lerp(col, col * lerp(float3(1.0, 1.0, 1.0), stock, 0.85), saturate(warmth));
        col = lerp(col, black_lift * stock * 0.22 + col * (1.0 - black_lift * 0.22),
                   1.0 - smoothstep(0.0, 0.35, lum));
        col = min(col, stock * white_cap + (1.0 - white_cap));
    }

    // --- THE SHEET'S EDGE. A soft fall toward the corners, as a page lit from in front always
    // has, plus a hint of the fibre running heavier at the margins.
    {
        float2 d = (uv - 0.5) * float2(aspect, 1.0) * 2.0;
        float v = 1.0 - vignette * saturate(dot(d, d) * 0.30);
        col *= v;
    }

    col *= max(gain, 0.0);
    OutputUAV[pix] = float4(max(col, 0.0), 1.0);
}
