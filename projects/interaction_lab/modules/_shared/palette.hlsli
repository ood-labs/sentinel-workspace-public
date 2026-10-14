// palette.hlsli - the "Palette" contract (Ramp Desk -> any consumer) and the colour maths behind
// it: OKLab / OKLCH, gamut mapping into sRGB by chroma, and colour-vision simulation.
//
// "Palette": float4 records
//   0        head   (stops n, entries 256, blend 0 OKLab | 1 OKLCH | 2 sRGB, revision)
//                   revision: a hash of the stops and the blend, an exact integer below 2^24.
//                   Equal revisions are equal palettes, so a consumer may skip work.
//   1..24    the stops in position order, two records each (12 at most):
//              1 + 2i   (t 0..1, midpoint toward the next stop 0..1 (0.5 even), -, -)
//              2 + 2i   (L 0..1, C asked for, h degrees, C shown)
//            C shown is C asked for brought inside sRGB at the same lightness and hue.
//   25..280  entry k, at t = k / 255: (r, g, b display sRGB 0..1, 1 where the blend left sRGB
//            and was brought back by reducing its chroma)
//   281..    the Ramp Desk's own working state (not part of the contract)
//
// A consumer samples with palSample(t) after naming its buffer:
//     StructuredBuffer<float4> P : register(t0);      // the Palette (data input)
//     #define PAL_BUFFER P
//     #include "../_shared/palette.hlsli"
#ifndef PALETTE_HLSLI
#define PALETTE_HLSLI

#define PAL_HEAD     0u
#define PAL_STOP0    1u
#define PAL_STOPS    12u
#define PAL_SAVED    25u                       // head + 12 stops: what a save or preset carries
#define PAL_ENTRY0   25u
#define PAL_ENTRIES  256u
#define PAL_RECORDS  281u

#define PAL_OKLAB 0u
#define PAL_OKLCH 1u
#define PAL_SRGB  2u

// ---------------------------------------------------------------- transfer
float3 palToLinear(float3 c)
{
    c = saturate(c);
    return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4);
}
float3 palToDisplay(float3 c)
{
    c = saturate(c);
    return c <= 0.0031308 ? c * 12.92 : 1.055 * pow(c, 1.0 / 2.4) - 0.055;
}

// ---------------------------------------------------------------- OKLab (Ottosson 2020)
float palCbrt(float x) { return sign(x) * pow(abs(x), 1.0 / 3.0); }

float3 palLinearToLab(float3 c)
{
    float l = 0.4122214708 * c.r + 0.5363325363 * c.g + 0.0514459929 * c.b;
    float m = 0.2119034982 * c.r + 0.6806995451 * c.g + 0.1073969566 * c.b;
    float s = 0.0883024619 * c.r + 0.2817188376 * c.g + 0.6299787005 * c.b;
    l = palCbrt(l); m = palCbrt(m); s = palCbrt(s);
    return float3(0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
                  1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
                  0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s);
}

float3 palLabToLinear(float3 c)
{
    float l = c.x + 0.3963377774 * c.y + 0.2158037573 * c.z;
    float m = c.x - 0.1055613458 * c.y - 0.0638541728 * c.z;
    float s = c.x - 0.0894841775 * c.y - 1.2914855480 * c.z;
    l = l * l * l; m = m * m * m; s = s * s * s;
    return float3( 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
                  -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
                  -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s);
}

float3 palLchToLab(float3 lch)
{
    float h = radians(lch.z);
    return float3(lch.x, lch.y * cos(h), lch.y * sin(h));
}
float3 palLabToLch(float3 lab)
{
    float h = degrees(atan2(lab.z, lab.y));
    return float3(lab.x, length(lab.yz), h < 0.0 ? h + 360.0 : h);
}

// ---------------------------------------------------------------- the sRGB gamut
bool palInGamut(float3 lin) { return all(lin >= -1e-4) && all(lin <= 1.0001); }

// The most chroma sRGB can show at lightness L and hue h.
float palMaxChroma(float L, float h)
{
    if (L <= 0.0 || L >= 1.0) return 0.0;
    float hr = radians(h);
    float2 dir = float2(cos(hr), sin(hr));
    float lo = 0.0, hi = 0.4;
    [loop] for (uint i = 0u; i < 16u; i++)
    {
        float m = 0.5 * (lo + hi);
        if (palInGamut(palLabToLinear(float3(L, m * dir)))) lo = m; else hi = m;
    }
    return lo;
}

// A colour sRGB can show, as linear RGB: outside the gamut, the chroma comes down at the same
// lightness and hue until it fits (CSS Color 4 maps the same way, on OKLCH).
float3 palGamutMap(float3 lab, out bool clipped)
{
    float3 lin = palLabToLinear(lab);
    clipped = !palInGamut(lin);
    if (!clipped) return saturate(lin);
    float L = lab.x;
    if (L <= 0.0) return 0.0;
    if (L >= 1.0) return 1.0;
    float C = length(lab.yz);
    float2 dir = C > 1e-6 ? lab.yz / C : float2(1.0, 0.0);
    float lo = 0.0, hi = C;
    [loop] for (uint i = 0u; i < 14u; i++)
    {
        float m = 0.5 * (lo + hi);
        if (palInGamut(palLabToLinear(float3(L, m * dir)))) lo = m; else hi = m;
    }
    return saturate(palLabToLinear(float3(L, lo * dir)));
}

// ---------------------------------------------------------------- blending two stops
// The midpoint bends the blend so that u = m lands halfway (a gradient editor's midpoint diamond).
float palBias(float u, float m)
{
    m = clamp(m, 0.05, 0.95);
    return pow(saturate(u), log(0.5) / log(m));
}

// Two stops (OKLCH, already inside sRGB) blended at u in a space, as linear RGB inside sRGB.
// OKLab goes straight across (complements meet in grey); OKLCH swings the hue the short way round
// (and keeps the chroma up); sRGB averages the encoded values, the way most software does.
float3 palBlend(float3 lchA, float3 lchB, float u, uint space, out bool clipped)
{
    clipped = false;
    float3 lin = 0.0;
    if (space == PAL_SRGB)
    {
        float3 a = palToDisplay(palLabToLinear(palLchToLab(lchA)));
        float3 b = palToDisplay(palLabToLinear(palLchToLab(lchB)));
        lin = palToLinear(lerp(a, b, u));
    }
    else if (space == PAL_OKLCH)
    {
        float ha = lchA.z, hb = lchB.z;
        if (lchA.y < 0.002) ha = hb;                    // a grey has no hue: take the other's
        if (lchB.y < 0.002) hb = ha;
        float dh = hb - ha;
        dh -= 360.0 * floor((dh + 180.0) / 360.0);
        lin = palGamutMap(palLchToLab(float3(lerp(lchA.x, lchB.x, u), lerp(lchA.y, lchB.y, u), ha + dh * u)), clipped);
    }
    else lin = palGamutMap(lerp(palLchToLab(lchA), palLchToLab(lchB), u), clipped);
    return lin;
}

// ---------------------------------------------------------------- colour vision (Machado 2009)
// Full-severity dichromacy on linear RGB.
float3 palProtan(float3 c) { return saturate(mul(float3x3( 0.152286,  1.052583, -0.204868,  0.114503,  0.786281,  0.099216, -0.003882, -0.048116,  1.051998), c)); }
float3 palDeutan(float3 c) { return saturate(mul(float3x3( 0.367322,  0.860646, -0.227968,  0.280085,  0.672501,  0.047413, -0.011820,  0.042940,  0.968881), c)); }
float3 palTritan(float3 c) { return saturate(mul(float3x3( 1.255528, -0.076749, -0.178779, -0.078411,  0.930809,  0.147602,  0.004733,  0.691367,  0.303900), c)); }

// ---------------------------------------------------------------- reading a Palette buffer
#ifdef PAL_BUFFER
uint   palStops()            { return clamp((uint)PAL_BUFFER[PAL_HEAD].x, 0u, PAL_STOPS); }
float4 palStopA(uint i)      { return PAL_BUFFER[PAL_STOP0 + 2u * i]; }
float4 palStopB(uint i)      { return PAL_BUFFER[PAL_STOP0 + 2u * i + 1u]; }
float3 palStopLch(uint i)    { float4 b = palStopB(i); return float3(b.x, b.w, b.z); }   // as shown
float4 palEntry(uint k)      { return PAL_BUFFER[PAL_ENTRY0 + min(k, PAL_ENTRIES - 1u)]; }
// display sRGB at t, linear between entries
float3 palSample(float t)
{
    float u = saturate(t) * 255.0;
    uint k = min((uint)u, 254u);
    return lerp(palEntry(k).rgb, palEntry(k + 1u).rgb, u - (float)k);
}
#endif

#endif
