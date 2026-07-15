// label_render — blit real scientifica-font strings at each Label anchor (data:0).
// Uses the shared font + os_text glyph-blit helpers (record-walk compiled out).

#define OS_NO_RECORD_BUFFER
#include "../_shared/fonts/scientifica_ascii.hlsli"
#include "../_shared/os_terminal.hlsli"
#include "../_shared/os_text.hlsli"

struct LabelRecord
{
    float2 pos; float scale; float label_id;
    float color_mix; float rotation; float active; float pad0;
};

RWTexture2D<float4> OutputUAV : register(u0);

// tiny technical-string table (ASCII codes), selected by label_id 0..7
int labelLen(int id)
{
    if (id == 0) return 4;   // MA-2
    if (id == 1) return 4;   // [24]
    if (id == 2) return 4;   // [27]
    if (id == 3) return 5;   // SEC-9
    if (id == 4) return 4;   // R.03
    if (id == 5) return 4;   // X-14
    if (id == 6) return 2;   // N7
    return 4;                // [08]
}

int labelChar(int id, int k)
{
    if (id == 0) { int s[4] = {77, 65, 45, 50};      return (k < 4) ? s[k] : 0; }
    if (id == 1) { int s[4] = {91, 50, 52, 93};      return (k < 4) ? s[k] : 0; }
    if (id == 2) { int s[4] = {91, 50, 55, 93};      return (k < 4) ? s[k] : 0; }
    if (id == 3) { int s[5] = {83, 69, 67, 45, 57};  return (k < 5) ? s[k] : 0; }
    if (id == 4) { int s[4] = {82, 46, 48, 51};      return (k < 4) ? s[k] : 0; }
    if (id == 5) { int s[4] = {88, 45, 49, 52};      return (k < 4) ? s[k] : 0; }
    if (id == 6) { int s[2] = {78, 55};              return (k < 2) ? s[k] : 0; }
    int s[4] = {91, 48, 56, 93};                     return (k < 4) ? s[k] : 0;
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;

    float2 fpix = (float2)pixel;
    float3 col = float3(0.0, 0.0, 0.0);
    float aAcc = 0.0;

    uint cnt = min((uint)_Data0_Count, 48u);
    [loop]
    for (uint i = 0u; i < 48u; i++)
    {
        if (i >= cnt) break;
        LabelRecord L = _Data0[i];
        if (L.active < 0.5) continue;

        int id = (int)(L.label_id + 0.5);
        int len = labelLen(id);
        float sc = max(round(L.scale * text_scale), 1.0);
        float2 anchor = L.pos * _Resolution.xy;
        float cellW = (float)SCIENTIFICA_GLYPH_W;

        float cov = 0.0;
        [loop]
        for (int k = 0; k < 8; k++)
        {
            if (k >= len) break;
            int code = labelChar(id, k);
            float2 a = anchor + float2((float)k * cellW * sc, 0.0);
            cov = max(cov, osBlitGlyph(fpix, a, sc, 0, code, false));
        }

        // optional underline tick
        if (show_ticks != 0)
        {
            float2 la = anchor + float2(0.0, ((float)SCIENTIFICA_GLYPH_H + 1.0) * sc);
            float lw = (float)len * cellW * sc;
            if (fpix.x >= la.x && fpix.x <= la.x + lw && abs(fpix.y - la.y) <= sc * 0.5)
                cov = max(cov, 0.7);
        }

        float3 tint = lerp(label_color, dim_color, L.color_mix);
        col = max(col, tint * cov);
        aAcc = max(aAcc, cov);
    }

    OutputUAV[pixel] = float4(col * intensity * (1.0 + glow), saturate(aAcc));
}
