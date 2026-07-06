// hud_labels — blit fixed scientifica-font strings at hand-authored screen
// anchors (percent readout, corner tabs, small technical labels). Self-contained
// (no data buffer): record-walk compiled out. Adapted from label_render.

#define OS_NO_RECORD_BUFFER
#include "../_shared/fonts/scientifica_ascii.hlsli"
#include "../_shared/os_terminal.hlsli"
#include "../_shared/os_text.hlsli"

RWTexture2D<float4> OutputUAV : register(u0);

int labLen(int id)
{
    if (id == 0) return 3;   // 25%
    if (id == 1) return 2;   // 4D
    if (id == 2) return 2;   // 1A
    if (id == 3) return 2;   // 3C
    if (id == 4) return 2;   // 2B
    if (id == 5) return 1;   // A
    if (id == 6) return 6;   // SYS.01
    if (id == 7) return 3;   // NAV
    if (id == 8) return 4;   // R.03
    return 4;                // X-14
}

int labChar(int id, int k)
{
    if (id == 0) { int s[3]={50,53,37};             return (k<3)?s[k]:0; }
    if (id == 1) { int s[2]={52,68};                return (k<2)?s[k]:0; }
    if (id == 2) { int s[2]={49,65};                return (k<2)?s[k]:0; }
    if (id == 3) { int s[2]={51,67};                return (k<2)?s[k]:0; }
    if (id == 4) { int s[2]={50,66};                return (k<2)?s[k]:0; }
    if (id == 5) { int s[1]={65};                   return (k<1)?s[k]:0; }
    if (id == 6) { int s[6]={83,89,83,46,48,49};    return (k<6)?s[k]:0; }
    if (id == 7) { int s[3]={78,65,86};             return (k<3)?s[k]:0; }
    if (id == 8) { int s[4]={82,46,48,51};          return (k<4)?s[k]:0; }
    int s[4]={88,45,49,52};                         return (k<4)?s[k]:0;
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;

    float2 fpix = (float2)pixel;
    float asp = _Resolution.x / _Resolution.y;

    // placement table: id, UV top-left, scale mult, tier(0=body,1=accent)
    const int   ID[10]  = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 };
    const float PX[10]  = { 0.700, 0.628, 0.947, 0.958, 0.943, 0.766, 0.028, 0.028, 0.205, 0.328 };
    const float PY[10]  = { 0.300, 0.104, 0.243, 0.433, 0.703, 0.050, 0.158, 0.330, 0.158, 0.760 };
    const float PS[10]  = { 2.6,   2.0,   1.6,   1.6,   1.6,   2.2,   1.3,   1.4,   1.3,   1.3 };
    const float PA[10]  = { 1.0,   1.0,   1.0,   1.0,   1.0,   1.0,   0.0,   0.0,   0.0,   0.0 };

    float bodyCov = 0.0;
    float accCov  = 0.0;
    float cellW = (float)SCIENTIFICA_GLYPH_W;

    [loop]
    for (int n = 0; n < 10; n++)
    {
        int id = ID[n];
        int len = labLen(id);
        float sc = max(round(PS[n] * text_scale), 1.0);
        // label 0 (the % readout) is anchored to the driven pct_pos so it can
        // track the hero focal point; the rest use the fixed placement table.
        float2 base = (n == 0) ? pct_pos : float2(PX[n], PY[n]);
        float2 anchor = base * _Resolution.xy;

        float cov = 0.0;
        [loop]
        for (int k = 0; k < 8; k++)
        {
            if (k >= len) break;
            int code = labChar(id, k);
            float2 a = anchor + float2((float)k * cellW * sc, 0.0);
            cov = max(cov, osBlitGlyph(fpix, a, sc, 0, code, PA[n] > 0.5));
        }
        // underline tick under the small technical labels
        if (id >= 6)
        {
            float2 la = anchor + float2(0.0, ((float)SCIENTIFICA_GLYPH_H + 1.0) * sc);
            float lw = (float)len * cellW * sc;
            if (fpix.x >= la.x && fpix.x <= la.x + lw && abs(fpix.y - la.y) <= sc * 0.5)
                cov = max(cov, 0.6);
        }

        if (PA[n] > 0.5) accCov = max(accCov, cov);
        else             bodyCov = max(bodyCov, cov);
    }

    float3 col = label_color * bodyCov + accent_color * accCov;
    col *= intensity * (1.0 + glow);
    float lum = max(col.r, max(col.g, col.b));
    OutputUAV[pixel] = float4(col, saturate(lum));
}
