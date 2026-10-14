// BR_Rug / rug.hlsl -- the RUG design authority. One thread, once per cook.
//
// It decides what is woven into the rug BR_Furnish placed: the family (Tabriz medallion, Isfahan
// all-over, Heriz geometric), the proportions (border width, medallion size, field scale), the
// palette (a dye per colour slot, from a dyer's list), abrash, wear and the knot pitch. The rug's
// size and place stay BR_Furnish's; the drawing is the same function the renderer weaves with.
//
// Hand edits are deltas over the parameters: drag the medallion's tip to size it, drag the
// border's inner edge to widen or narrow the border, click a swatch to step that slot along its
// dyes, chips for the family, the palette, a re-roll and a reset. Every event is one branch of a
// single if/else chain (FXC drops stores made before a mid-body `continue`).
#include "../_shared/br_records.hlsli"
#include "../_shared/br_furn_defs.hlsli"
#include "../_shared/br_rug.hlsli"
#include "rug_layout.hlsli"

RWStructuredBuffer<BRRec> Rug : register(u0);

#define PLAN_VERSION 1.0
#define H_NONE   0
#define H_MED    1
#define H_BORDER 2

float sane(float v) { return (abs(v) < 1e5) ? v : 0.0; }

[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    float2 res = (_Resolution.x >= 64.0) ? _Resolution.xy : float2(1280.0, 900.0);
    // the rug's size is BR_Furnish's (slot 0); a 2.5 x 3.4 m rug stands in while it is unlinked
    float2 rugHalf = float2(1.25, 1.70);
    bool linked = _Data0_Count >= 1u && abs(_Data0[0].head.x - ROLE_FURN) < 0.5 && (int)round(_Data0[0].head.y) == FK_RUG;
    if (linked) rugHalf = max(_Data0[0].look.xz * 0.5, 0.2);
    RLayout L = rLayout(res, rugHalf);

    // ---- persistent state
    BRRec ed = Rug[RUG_EDITOR];
    bool fresh = !(abs(ed.head.x - ROLE_RUG_ED) < 0.5) || abs(sane(ed.head.w) - PLAN_VERSION) > 0.01;
    if (fresh)
    {
        BRRec z; z.head = float4(ROLE_DELTA, 0, 0, 0); z.dims = 0; z.look = 0; z.meta = 0;
        [loop] for (int i = RUG_DELTA0; i < RUG_RECORDS; i++) Rug[i] = z;
        ed.head = float4(ROLE_RUG_ED, 0, 0, PLAN_VERSION); ed.dims = 0; ed.look = 0; ed.meta = 0;
    }
    BRRec d0 = Rug[RUG_DELTA0];
    BRRec d1 = Rug[RUG_DELTA0 + 1];
    float borderO = clamp(sane(d0.dims.x), 0.0, 0.25);      // 0 = follow the parameter
    float medO = clamp(sane(d0.dims.y), 0.0, 0.8);
    float seedOff = sane(d0.dims.z);
    float presetOff = sane(d0.dims.w);
    float styleOff = sane(d0.look.x);
    float dye[RUG_SLOTS];
    dye[0] = sane(d1.dims.x); dye[1] = sane(d1.dims.y); dye[2] = sane(d1.dims.z); dye[3] = sane(d1.dims.w);
    dye[4] = sane(d1.look.x); dye[5] = sane(d1.look.y); dye[6] = sane(d1.look.z); dye[7] = sane(d1.look.w);
    int handle = (int)round(sane(ed.head.y));
    uint lastSeq = asuint(ed.meta.x);
    float handled = sane(ed.meta.y);
    float4 probe = ed.look;

    float bw = (borderO > 0.0) ? borderO : border;
    float md = (medO > 0.0) ? medO : medallion;

    // ---- events, each consumed once by sequence; ONE exit per event
    uint n = _ViewportEventCount;
    uint ringMax = 0u;
    [loop] for (uint ri = 0u; ri < n; ri++) ringMax = max(ringMax, _ViewportEvents[ri].sequence);
    if (n > 0u && ringMax < lastSeq) lastSeq = 0u;
    uint newLast = lastSeq;
    [loop] for (uint ei = 0u; ei < n; ei++)
    {
        ViewportEvent ev = _ViewportEvents[ei];
        bool isFresh = ev.sequence > lastSeq || (lastSeq - ev.sequence) > (1u << 20);
        if (isFresh)
        {
            newLast = (ev.sequence > lastSeq) ? max(newLast, ev.sequence) : ev.sequence;
            handled += 1.0;
            float2 px = ev.position * res;
            bool press = ev.type == 2u && ev.code == 0u && ev.phase == 1u;
            bool release = ev.type == 2u && ev.code == 0u && ev.phase == 3u;
            bool dragMove = ev.type == 5u && ev.code == 3u && (ev.phase == 6u || ev.phase == 7u);
            bool dragEnd = ev.type == 5u && ev.code == 3u && (ev.phase == 7u || ev.phase == 8u);
            int styNow = (((int)round(style + styleOff)) % 3 + 3) % 3;
            int chip = press ? rChipAt(L, px) : -1;
            int sw = (press && chip < 0) ? rSwatchAt(L, px) : -1;
            if (press) probe = float4(px, (float)chip, (float)sw);
            if (chip >= 0)
            {
                if (chip == 0) styleOff += 1.0;                          // family
                else if (chip == 1)
                {
                    presetOff += 1.0;                                    // palette preset (clears dye steps)
                    [unroll] for (int k = 0; k < RUG_SLOTS; k++) dye[k] = 0.0;
                }
                else if (chip == 2) seedOff += 1.0;                      // re-roll the drawing
                else
                {
                    borderO = 0.0; medO = 0.0; seedOff = 0.0; presetOff = 0.0; styleOff = 0.0;
                    [unroll] for (int k2 = 0; k2 < RUG_SLOTS; k2++) dye[k2] = 0.0;
                }
                handle = H_NONE;
            }
            else if (sw >= 0)
            {
                [unroll] for (int k3 = 0; k3 < RUG_SLOTS; k3++) if (k3 == sw) dye[k3] += 1.0;
                handle = H_NONE;
            }
            else if (press) handle = rHandleAt(L, px, bw, md, styNow);      // H_NONE / H_MED / H_BORDER
            else if (release || dragEnd) handle = H_NONE;
            else if (dragMove && handle == H_MED)
            {
                float2 q = rRugQ(L, px);
                float b3 = rugFieldInset(L.h.x, bw);
                medO = clamp(abs(q.y) / rugMedTipK(styNow) / max(min(L.h.x - b3, L.h.y - b3), 0.05), 0.2, 0.8);
                md = medO;
            }
            else if (dragMove && handle == H_BORDER)
            {
                float2 q = rRugQ(L, px);
                borderO = clamp(((L.h.x - abs(q.x)) - 0.010 - L.h.x * 0.045) / (2.0 * L.h.x), 0.04, 0.25);
                bw = borderO;
            }
        }
    }

    // ---- publish the design
    int sty = (((int)round(style + styleOff)) % 3 + 3) % 3;
    int pre = (((int)round(palette + presetOff)) % 4 + 4) % 4;
    BRRec h;
    h.head = float4(ROLE_RUG, sty, frac((seed + seedOff) * 0.6180339) * 97.0 + 0.37, PLAN_VERSION);
    h.dims = float4(bw, md, field_scale, abrash);
    h.look = float4(wear, knot, pre, 0);
    h.meta = float4(rugSrgb(rugDye(7, RUG_PRESET[pre * RUG_SLOTS + 7] + (int)round(dye[7]))), 0);
    Rug[0] = h;
    [unroll] for (int k4 = 0; k4 < 7; k4++)
    {
        BRRec c;
        c.head = float4(ROLE_RUG, 100 + k4, 0, 0);
        c.dims = float4(rugSrgb(rugDye(k4, RUG_PRESET[pre * RUG_SLOTS + k4] + (int)round(dye[k4]))), 0);
        c.look = 0; c.meta = 0;
        Rug[1 + k4] = c;
    }
    BRRec o0;
    bool any = borderO > 0.0 || medO > 0.0 || abs(seedOff) + abs(presetOff) + abs(styleOff) > 0.0;
    o0.head = float4(ROLE_DELTA, 0, any ? 1 : 0, 0);
    o0.dims = float4(borderO, medO, seedOff, presetOff);
    o0.look = float4(styleOff, 0, 0, 0);
    o0.meta = 0;
    Rug[RUG_DELTA0] = o0;
    BRRec o1;
    o1.head = float4(ROLE_DELTA, 1, 0, 0);
    o1.dims = float4(dye[0], dye[1], dye[2], dye[3]);
    o1.look = float4(dye[4], dye[5], dye[6], dye[7]);
    o1.meta = 0;
    Rug[RUG_DELTA0 + 1] = o1;
    ed.head = float4(ROLE_RUG_ED, handle, 0, PLAN_VERSION);
    ed.dims = float4(rugHalf, linked ? 1.0 : 0.0, 0);                // z: the size is BR_Furnish's
    ed.look = probe;
    ed.meta = float4(asfloat(newLast), handled, res);
    Rug[RUG_EDITOR] = ed;
}
