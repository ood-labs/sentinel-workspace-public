// Stage - the looks the Desk station's cue stack recalls, and how two of them blend.
//
// Eight cues, four fixtures hung on a truss. A cue is a cyclorama wash (top and bottom colour,
// level) and, per fixture, a colour, an intensity, a pan (where its beam lands across the floor,
// 0..1) and a focus (0 tight .. 1 wide). The Cue Brain Script only says WHICH two looks and how
// far between them (cue_a, cue_b, mix); what each look is lives here, with the renderer.
// Colours are linear.
#ifndef STAGE_HLSLI
#define STAGE_HLSLI

#define ST_CUES 8
#define ST_FIX  4

static const float ST_HANG[ST_FIX] = { 0.18, 0.39, 0.61, 0.82 };

//                                   PRESET               DAWN                 AMBER WASH           SPLIT
static const float3 ST_CYC_TOP[ST_CUES] = { float3(0.040, 0.030, 0.024), float3(0.20, 0.30, 0.55), float3(0.22, 0.10, 0.03), float3(0.015, 0.025, 0.050),
//                                   COLD                 SOLO                 STORM                FINALE
                                            float3(0.010, 0.020, 0.080), float3(0.0, 0.0, 0.0),   float3(0.08, 0.02, 0.16), float3(0.45, 0.26, 0.07) };
static const float3 ST_CYC_BOT[ST_CUES] = { float3(0.110, 0.075, 0.050), float3(0.95, 0.55, 0.33), float3(0.50, 0.24, 0.07), float3(0.040, 0.045, 0.080),
                                            float3(0.030, 0.070, 0.220), float3(0.0, 0.0, 0.0),   float3(0.16, 0.05, 0.32), float3(0.95, 0.58, 0.18) };
static const float  ST_CYC_LVL[ST_CUES] = { 0.55, 0.95, 0.65, 0.60, 0.85, 0.0, 0.75, 1.0 };

// per cue, fixtures left to right
static const float3 ST_COL[ST_CUES * ST_FIX] = {
    float3(1.00, 0.62, 0.30), float3(1.00, 0.62, 0.30), float3(1.00, 0.62, 0.30), float3(1.00, 0.62, 0.30),   // PRESET  tungsten
    float3(1.00, 0.70, 0.50), float3(1.00, 0.70, 0.50), float3(1.00, 0.70, 0.50), float3(1.00, 0.70, 0.50),   // DAWN    peach
    float3(1.00, 0.45, 0.10), float3(1.00, 0.45, 0.10), float3(1.00, 0.45, 0.10), float3(1.00, 0.45, 0.10),   // AMBER
    float3(0.20, 0.75, 0.95), float3(0.20, 0.75, 0.95), float3(1.00, 0.45, 0.10), float3(1.00, 0.45, 0.10),   // SPLIT   cyan | amber
    float3(0.35, 0.55, 1.00), float3(0.35, 0.55, 1.00), float3(0.35, 0.55, 1.00), float3(0.35, 0.55, 1.00),   // COLD    steel
    float3(1.00, 0.93, 0.85), float3(1.00, 0.93, 0.85), float3(1.00, 0.93, 0.85), float3(1.00, 0.93, 0.85),   // SOLO    open white
    float3(0.62, 0.45, 1.00), float3(0.20, 0.75, 0.95), float3(0.20, 0.75, 0.95), float3(0.62, 0.45, 1.00),   // STORM   lavender, cyan
    float3(1.00, 0.88, 0.70), float3(1.00, 0.93, 0.85), float3(1.00, 0.93, 0.85), float3(1.00, 0.88, 0.70) }; // FINALE
static const float ST_INT[ST_CUES * ST_FIX] = {
    0.22, 0.22, 0.22, 0.22,   0.55, 0.00, 0.00, 0.40,   0.85, 0.85, 0.85, 0.85,   0.95, 0.95, 0.95, 0.95,
    0.75, 0.75, 0.75, 0.75,   0.00, 1.00, 0.00, 0.00,   0.95, 0.95, 0.95, 0.95,   1.00, 1.00, 1.00, 1.00 };
static const float ST_PAN[ST_CUES * ST_FIX] = {
    0.18, 0.39, 0.61, 0.82,   0.34, 0.39, 0.61, 0.66,   0.20, 0.40, 0.60, 0.80,   0.24, 0.32, 0.68, 0.76,
    0.30, 0.45, 0.55, 0.70,   0.18, 0.50, 0.61, 0.82,   0.76, 0.86, 0.14, 0.24,   0.14, 0.38, 0.62, 0.86 };
static const float ST_FOC[ST_CUES * ST_FIX] = {
    0.85, 0.85, 0.85, 0.85,   0.95, 0.60, 0.60, 0.95,   0.90, 0.90, 0.90, 0.90,   0.45, 0.45, 0.45, 0.45,
    0.30, 0.30, 0.30, 0.30,   0.50, 0.20, 0.50, 0.50,   0.40, 0.40, 0.40, 0.40,   1.00, 1.00, 1.00, 1.00 };

struct StFixture { float3 col; float inten; float pan; float focus; };
struct StLook { float3 cycTop; float3 cycBot; float cycLevel; StFixture f[ST_FIX]; };

StLook stLook(uint c)
{
    c = min(c, ST_CUES - 1u);
    StLook L;
    L.cycTop = ST_CYC_TOP[c];
    L.cycBot = ST_CYC_BOT[c];
    L.cycLevel = ST_CYC_LVL[c];
    [unroll] for (uint i = 0u; i < ST_FIX; i++)
    {
        uint k = c * ST_FIX + i;
        L.f[i].col = ST_COL[k];
        L.f[i].inten = ST_INT[k];
        L.f[i].pan = ST_PAN[k];
        L.f[i].focus = ST_FOC[k];
    }
    return L;
}

// a crossfade moves the lights: pans and focus travel, colours and levels blend
StLook stBlend(StLook a, StLook b, float m)
{
    StLook L;
    L.cycTop = lerp(a.cycTop, b.cycTop, m);
    L.cycBot = lerp(a.cycBot, b.cycBot, m);
    L.cycLevel = lerp(a.cycLevel, b.cycLevel, m);
    [unroll] for (uint i = 0u; i < ST_FIX; i++)
    {
        // a fixture that is dark at one end keeps the other end's colour and aim while it fades
        float wa = a.f[i].inten, wb = b.f[i].inten;
        bool la = wa > 1e-4, lb = wb > 1e-4;
        float k = (la && !lb) ? 0.0 : ((!la && lb) ? 1.0 : m);
        L.f[i].col = lerp(a.f[i].col, b.f[i].col, k);
        L.f[i].pan = lerp(a.f[i].pan, b.f[i].pan, k);
        L.f[i].focus = lerp(a.f[i].focus, b.f[i].focus, k);
        L.f[i].inten = lerp(wa, wb, m);
    }
    return L;
}

#endif
