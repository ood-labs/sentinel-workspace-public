// SS_Renderer / vis_led - the pixel-bar texture the renderer and the venue sample (SS_Lighting's pixels layout: one row per run, u
// along the whole run), drawn from the battens' decoded DMX. A texel finds the batten under its place on the run and
// that batten's pixel there; where no batten sits (the slack at piece ends) it is dark, as the real run is. Values go
// back to the content's scale: colour times the show's pixel-bar peak (Show State row 1 z), which dmx_state divided out.
#define GDTF_RENDER _Data6
#include "../_shared/fe_tables.hlsli"
#include "vis_common.hlsli"

StructuredBuffer<SsRigInst> Inst : register(t0);
StructuredBuffer<float2> State : register(t1);
StructuredBuffer<uint> Runs : register(t2);
RWTexture2D<float4> OutputUAV : register(u0);
#include "vis_emit.hlsli"

[numthreads(8, 8, 1)]
void main(uint3 id : SV_DispatchThreadID)
{
    uint W, H;
    OutputUAV.GetDimensions(W, H);
    if (id.x >= W || id.y >= H) return;
    uint b = id.y;
    float3 c = 0.0;
    float total = 0.0;
    [unroll] for (uint j = 0u; j < SS_RIG_BAR_PIECES; j++)
    {
        uint q = b * SS_RIG_BAR_PIECES + j;
        total += (q < _Data2_Count && _Data2[q].w.z > 0.5) ? _Data2[q].w.x : 0.0;
    }
    if (b < 64u && total > 0.0 && frTablesValid())
    {
        float s = ((float)id.x + 0.5) / (float)W * total;
        uint own = 0u;
        float start = 0.0;
        for (uint u = 0u; u < 32u; u++)
        {
            uint e = Runs[b * 32u + u];
            float st = e > 0u ? (float)Inst[e - 1u].custom / 1000.0 : 0.0;
            uint cells = e > 0u ? max(visEmitterCells(Inst[e - 1u].type, 0u), 1u) : 1u;
            bool hit = own == 0u && e > 0u && s >= st && s < st + (float)cells * 0.05;
            own = hit ? e : own;
            start = hit ? st : start;
        }
        if (own > 0u)
        {
            uint k = own - 1u, type = Inst[k].type;
            uint cell = (uint)((s - start) / 0.05);
            VisEmit em = visEmit(k, type, visEmitter(type, 2u), cell);
            float3 rgb = em.colour;
            float dim = em.dim * em.gate;
            float peak = _Data5_Count >= 2u ? _Data5[1].value.z : 6.0;
            c = saturate(rgb) * saturate(dim) * peak;
        }
    }
    OutputUAV[id.xy] = float4(c, 1.0);
}
