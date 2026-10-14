// The decoded state, one row per fixture and one column per state slot. Values read as brightness; colour
// attributes show their own channel colour, pulled toward grey; a slot holding a function other than a plain
// value (open, strobe, kelvin, slot...) shows as a mid mark. Rows are grouped by type with a type swatch. Columns
// narrow to fit the rig's state stride (the FixtureRender port's).
#define GDTF_RENDER _Data2
#include "../_shared/fe_tables.hlsli"
#include "../_shared/fe_rig.hlsli"
#include "../_shared/plan_theme.hlsli"
#include "../_shared/ui/sui3_core.hlsli"
#include "../_shared/ui/sui3_text.hlsli"

StructuredBuffer<float2> StateIn : register(t0);
RWTexture2D<float4> OutputUAV : register(u0);

#define COLW 7.0
#define ROWH 6.0
static const float2 ORIGIN = float2(36.0, 46.0);

[numthreads(8, 8, 1)]
void main(uint3 id : SV_DispatchThreadID)
{
    uint w, h;
    OutputUAV.GetDimensions(w, h);
    if (id.x >= w || id.y >= h) return;
    float2 P = (float2)id.xy + 0.5;
    float3 col = PT_FIELD;
    col += PT_INK * sui3Text(P, float2(20.0, 10.0), 2.0, S_F, S_E, S_SP, S_D, S_E, S_C, S_O, S_D, S_E, 0, 0, 0);
    col += PT_DIM * sui3Text(P, float2(190.0, 20.0), 1.0, S_S, S_T, S_A, S_T, S_E, S_SP, S_S, S_L, S_O, S_T, S_S, 0);
    uint stride = min(feStateStride(), FE_STATE_CAP);
    float colw = clamp(((float)w - ORIGIN.x - 8.0) / (float)max(stride, 1u), 1.0, COLW);
    float2 g = (P - ORIGIN) / float2(colw, ROWH);
    if (g.x >= 0.0 && g.y >= 0.0)
    {
        uint slot = (uint)g.x, inst = (uint)g.y;
        if (inst < FE_N_MAX && inst < _Data0_Count && slot < stride && (_Data0[inst].flags & FE_INST_ACTIVE) != 0u
            && (_Data0[inst].flags & FE_INST_PLACEHOLDER) == 0u)
        {
            uint type = min(_Data0[inst].type, feTypeCount() - 1u);
            uint4 ti = FE_TYPE_INFO_AT(type);
            float2 f = frac(g);
            float inside = step(0.1, f.x) * step(f.x, 0.9) * step(0.12, f.y) * step(f.y, 0.88);
            if (slot < ti.z)
            {
                uint kind = 0u;
                for (uint a = 0u; a < FE_TYPE_ATTRN_AT(type); a++)
                {
                    uint4 x = FE_ATTR_AT(ti.w + a);
                    kind = (slot >= x.x && slot < x.x + x.y) ? x.z : kind;
                }
                float2 v = StateIn[inst * stride + slot];
                uint fn = (uint)(v.x + 0.5);
                float3 tint = kind == FE_KIND_RED ? float3(1, 0.25, 0.2) : (kind == FE_KIND_GREEN ? float3(0.3, 1, 0.35)
                            : (kind == FE_KIND_BLUE ? float3(0.3, 0.45, 1) : float3(1, 1, 1)));
                float3 c = fn == FE_FN_VALUE ? ptSampleColour(tint) * saturate(abs(v.y) <= 1.0 ? abs(v.y) : 0.6)
                         : (fn == FE_FN_NONE ? PT_GRID : PT_DIM);
                col = lerp(col, PT_WELL + c, inside);
            }
            // type swatch at the row start
            if (P.x < ORIGIN.x - 6.0 && P.x > ORIGIN.x - 14.0)
                col = lerp(col, ptId((int)type), step(0.15, f.y) * step(f.y, 0.85));
        }
    }
    OutputUAV[id.xy] = float4(col, 1.0);
}
