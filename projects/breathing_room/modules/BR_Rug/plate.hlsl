// BR_Rug / plate.hlsl -- the rug laid flat, woven per pixel by the same function the renderer
// uses, at the canvas's own footprint (so what you see is the design, knot-quantised when you are
// close enough). It is the content background the shared UI kit draws the chrome, handles and
// type over (ui.hlsl, from layout.hlsl's draw list). The rug is a material sample: its colour is
// the record's own, passed through ptInset so it cannot outshine the instrument's readouts.
#include "../_shared/br_records.hlsli"
#include "../_shared/br_furn_defs.hlsli"
#define RUG_REC(i) RugBuf[i]
StructuredBuffer<BRRec> RugBuf : register(t0);
#include "../_shared/br_rug.hlsli"
#include "rug_layout.hlsli"

RWTexture2D<float4> OutputUAV : register(u0);

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    uint Wd, Ht;
    OutputUAV.GetDimensions(Wd, Ht);
    if (tid.x >= Wd || tid.y >= Ht) return;
    float2 P = float2(tid.xy) + 0.5;
    BRRec ed = RugBuf[RUG_EDITOR];
    float2 rugHalf = (ed.dims.x > 0.05) ? ed.dims.xy : float2(1.25, 1.70);
    RLayout L = rLayout(float2(Wd, Ht), rugHalf);
    float3 col = IL_FIELD;

    // the rug pane's card (the kit draws its edge, header rule and title)
    float d = ilSdBox(P, L.rugPane, IL_RADIUS * L.s);
    if (d < 1.0)
    {
        ilOver(col, IL_PANEL, ilFill(d));
        float2 q = rRugQ(L, P);
        float2 qa = abs(q);
        if (rInRect(P, L.rugR, 0.0) && qa.x <= L.h.x && qa.y <= L.h.y + 0.07)
        {
            BRRugDesign R = rugFromRecs();
            if (qa.y <= L.h.y)
            {
                float pile;
                // q is (across, along); rugDesign wants x across, y along, with the half size to match
                float3 c = rugDesign(q, L.h, R, 0.75 / L.scale, pile);
                col = ptInset(c * (0.86 + 0.14 * pile) * 3.2);
            }
            else
            {
                // the fringe at the two short ends: warp ends, thinning as they hang
                float strand = abs(frac(q.x / 0.012) - 0.5);
                float a = (1.0 - smoothstep(0.18, 0.32, strand)) * (1.0 - (qa.y - L.h.y) / 0.07 * 0.5);
                ilOver(col, ptInset(R.ivory * 2.6), a);
            }
        }
    }
    OutputUAV[tid.xy] = float4(saturate(col), 1.0);
}
