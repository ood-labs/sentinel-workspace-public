// palette.hlsli — the shared colour language for the `strata` plate system, transcribed
// from reference #7/#8: saturated glossy accents + red graphic marks + black/white chrome,
// all sung against a neutral studio gray. EVERY plate draws from str_palette() so 10,000
// seeds all read as one artist. Display-space albedos (renderers do the final pow 1/2.2).
// No includes, no state — pure constants + helpers. Include after sdf_ops if used together.
#ifndef STRATA_PALETTE_HLSLI
#define STRATA_PALETTE_HLSLI

// ---- the 10-colour palette (indices are stable; layout buffers store these) ----
#define STR_ICE     0   // pale cyan / ice-blue
#define STR_LIME    1   // chartreuse green
#define STR_INDIGO  2   // deep navy
#define STR_ORANGE  3   // hot orange
#define STR_LAV     4   // lavender / mauve
#define STR_PURPLE  5   // violet
#define STR_RED     6   // pure red accent
#define STR_WHITE   7   // chrome white
#define STR_BLACK   8   // chrome black
#define STR_GRAY    9   // matte neutral sphere
#define STR_NCOL    10

float3 str_palette(int i)
{
    i = ((i % STR_NCOL) + STR_NCOL) % STR_NCOL;
    if (i == STR_ICE)    return float3(0.64, 0.85, 0.87);
    if (i == STR_LIME)   return float3(0.72, 0.85, 0.07);
    if (i == STR_INDIGO) return float3(0.14, 0.14, 0.40);
    if (i == STR_ORANGE) return float3(0.96, 0.49, 0.12);
    if (i == STR_LAV)    return float3(0.73, 0.68, 0.81);
    if (i == STR_PURPLE) return float3(0.40, 0.25, 0.53);
    if (i == STR_RED)    return float3(0.90, 0.16, 0.11);
    if (i == STR_WHITE)  return float3(0.95, 0.95, 0.95);
    if (i == STR_BLACK)  return float3(0.030, 0.030, 0.040);
    return float3(0.55, 0.56, 0.58);   // GRAY
}

// two-stop gradient between palette entries — the signature "mapped along the form" look.
float3 str_grad(int a, int b, float t)
{
    return lerp(str_palette(a), str_palette(b), saturate(t));
}

// ---- studio backdrop --------------------------------------------------------
// neutral cool-gray void with a soft top-lit vertical gradient + radial vignette.
// used by the bg plate AND as the environment colour for chrome reflection / rim.
// uv is 0..1 with y up; returns display-space gray.
float3 str_studio(float2 uv)
{
    float2 c = uv - float2(0.5, 0.54);
    float vign = 1.0 - dot(c, c) * 0.85;                 // gentle darkening to edges
    float vert = lerp(0.58, 0.74, saturate(uv.y * 0.9 + 0.15)); // lighter toward top
    float3 base = float3(vert, vert, vert) * float3(1.005, 1.0, 1.01); // a hair cool
    return base * saturate(vign);
}

// env colour for a reflection ray direction (cheap studio: sky-ish up, floor-ish down).
float3 str_envColor(float3 rd)
{
    float up = saturate(rd.y * 0.5 + 0.5);
    float3 lo = float3(0.40, 0.41, 0.43);
    float3 hi = float3(0.82, 0.83, 0.85);
    return lerp(lo, hi, up);
}

#endif // STRATA_PALETTE_HLSLI
