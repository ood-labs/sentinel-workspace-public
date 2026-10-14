// What the console is sending: every live universe as a 32 x 16 grid, channel 1 at the top left (the same
// layout as the DMX In / Out node bodies), level as brightness. Unpatched channels stay dark.
#include "../_shared/fe_tables.hlsli"
#include "../_shared/dmx_schema_v2.hlsli"
#include "../_shared/plan_theme.hlsli"
#include "../_shared/ui/sui3_core.hlsli"
#include "../_shared/ui/sui3_text.hlsli"

struct DmxRecord { uint channels[512]; };
StructuredBuffer<DmxRecord> Records : register(t0);
RWTexture2D<float4> OutputUAV : register(u0);

#define COLS 6u
#define CELL 6.0

float drawNum(float2 P, float2 anchor, uint n)
{
    uint d = n >= 1000u ? 4u : (n >= 100u ? 3u : (n >= 10u ? 2u : 1u));
    if (sui3RunMiss(P, anchor, 1.0, (int)d)) return 0.0;
    float cov = 0.0;
    uint p10 = 1u;
    for (uint q = 1u; q < d; q++) p10 *= 10u;
    [loop] for (uint k = 0u; k < d; k++)
    {
        cov = max(cov, sui3Glyph(P, anchor + float2((float)k * SUI3_ADVANCE, 0.0), 1.0, S_0 + (int)((n / p10) % 10u)));
        p10 = max(p10 / 10u, 1u);
    }
    return cov;
}

[numthreads(8, 8, 1)]
void main(uint3 id : SV_DispatchThreadID)
{
    uint w, h;
    OutputUAV.GetDimensions(w, h);
    if (id.x >= w || id.y >= h) return;
    float2 P = (float2)id.xy + 0.5;
    float3 col = PT_FIELD;
    uint live = Records[0].channels[1];
    col += PT_INK * sui3Text(P, float2(20.0, 10.0), 2.0, S_F, S_E, S_SP, S_C, S_O, S_N, S_S, S_O, S_L, S_E, 0, 0);
    col += PT_MID * drawNum(P, float2(200.0, 20.0), live);
    col += PT_DIM * sui3Text(P, float2(200.0 + 4.0 * SUI3_ADVANCE, 20.0), 1.0, S_U, S_N, S_I, S_V, S_E, S_R, S_S, S_E, S_S, 0, 0, 0);
    // Universe blocks.
    float2 block = float2(32.0 * CELL + 14.0, 16.0 * CELL + 26.0);
    float2 origin = float2(20.0, 50.0);
    float2 q = (P - origin) / block;
    if (q.x >= 0.0 && q.y >= 0.0 && q.x < (float)COLS)
    {
        uint bx = (uint)q.x, by = (uint)q.y;
        uint u = by * COLS + bx;
        float2 local = P - origin - float2(bx, by) * block;
        if (u < live && u < DMX_MAX_UNIVERSES)
        {
            col += PT_DIM * sui3Text(P, origin + float2(bx, by) * block, 1.0, S_U, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0);
            col += PT_MID * drawNum(P, origin + float2(bx, by) * block + float2(SUI3_ADVANCE, 0.0), u + 1u);
            float2 g = local - float2(0.0, 14.0);
            if (g.x >= 0.0 && g.y >= 0.0 && g.x < 32.0 * CELL && g.y < 16.0 * CELL)
            {
                uint cx = (uint)(g.x / CELL), cy = (uint)(g.y / CELL);
                uint ch = cy * 32u + cx;
                float v = (float)Records[DMX_UNIVERSE_RECORD_BASE + u].channels[ch] / 255.0;
                float2 f = frac(g / CELL);
                float inside = step(0.08, f.x) * step(0.08, f.y) * step(f.x, 0.92) * step(f.y, 0.92);
                col = lerp(col, PT_WELL + v * (PT_INK - PT_WELL), inside);
            }
        }
    }
    OutputUAV[id.xy] = float4(col, 1.0);
}
