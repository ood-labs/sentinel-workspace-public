// Spline Desk - renderer.
//
// Rebuilt on the sui3 kit. Two substantive changes from v1's renderer:
//
//  1. THE PATH IS DRAWN FROM THE KNOTS, NOT THE SAMPLE BUFFER. v1 walked all 512
//     PNode records for every pixel -- half a billion buffer loads on a 1.1
//     megapixel panel -- to draw what is usually three cubic segments. Walking
//     the 64 knots instead early-outs on the inactive ones immediately. The
//     Sampled Path output is unchanged and still published for downstream
//     consumers; it is simply not the thing this renderer reads.
//
//  2. SELECTION AND TANGENT MODE ARE STRUCTURE, NOT FILL. 3D's criterion 4 asks
//     that selection, tangent mode and the active lane be legible from the
//     render alone. A selected anchor gets an amber bracket ring; the tangent
//     mode changes the SHAPE of the handle terminals (free = open ring, aligned
//     = ring with a bar through it, mirrored = filled disc); the active lane is
//     drawn at full ink while the others drop to rule weight.
#include "types.hlsli"
#include "layout.hlsli"
#include "../_shared/ui/sui3_theme.hlsli"
#include "../_shared/ui/sui3_controls.hlsli"
#include "../_shared/ui/sui_interaction.hlsli"

struct PNode { float2 pos; float2 dir; float depth; float u; float v; float weight; float group; float kind; float seed; float active; };
struct SplineHeader { uint first_knot; uint knot_count; uint closed; uint active; };

StructuredBuffer<SplineKnot>   _Tex0 : register(t0);
StructuredBuffer<PNode>        _Tex1 : register(t1);
StructuredBuffer<EditorState>  _Tex2 : register(t2);
StructuredBuffer<SplineHeader> _Tex3 : register(t3);
RWTexture2D<float4> OutputUAV : register(u0);

int nextActiveKnot(uint splineId, int after) {
    [loop] for (int i = after + 1; i < 64; i++)
        if (_Tex0[i].active > 0.5 && _Tex0[i].spline_id == splineId) return i;
    return -1;
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    if (tid.x >= (uint)_Resolution.x || tid.y >= (uint)_Resolution.y) return;
    float2 R = _Resolution.xy;
    float2 P = ((float2)tid.xy) + 0.5;

    Sui3Theme T = sui3Theme(accent_color.rgb);
    float sB  = sdTextScale(R);
    float pad = 0.016 * R.x;

    EditorState st = _Tex2[0];
    uint lane = (uint)round(clamp(st.active_spline, 0.0, 7.0));
    uint tmode = (uint)round(clamp(st.tangent_mode, 0.0, 2.0));

    float3 col = T.field;

    // ---- field graticule ----------------------------------------------------
    col += T.rule * 0.18 * sui3Graticule(P, float4(0.0, 0.0, R.x, R.y), float2(16.0, 9.0));

    // ---- paths --------------------------------------------------------------
    // Outer loop is over lanes so the active one can be weighted differently
    // without a second pass over the knots.
    [loop] for (uint s = 0u; s < 8u; s++) {
        int a = nextActiveKnot(s, -1);
        if (a < 0) continue;
        bool isActive = (s == lane);
        float3 ink = isActive ? T.ink : T.rule;
        float  amt = isActive ? 0.95 : 0.55;

        int b = nextActiveKnot(s, a);
        [loop] while (b >= 0) {
            float2 p0 = _Tex0[a].anchor * R;
            float2 c0 = _Tex0[a].handle_out * R;
            float2 c1 = _Tex0[b].handle_in * R;
            float2 p1 = _Tex0[b].anchor * R;
            float2 prev = p0;
            [loop] for (int k = 1; k <= 16; k++) {
                float t = (float)k / 16.0;
                float2 cur = cubicPoint(p0, c0, c1, p1, t);
                col += ink * amt * sui3Line(P, prev, cur, isActive ? 1.6 : 1.2);
                prev = cur;
            }
            a = b; b = nextActiveKnot(s, a);
        }

        // Closing segment, so a closed path reads as closed rather than as an
        // open path that happens to end near its start.
        if (_Tex3[s].closed != 0u) {
            int first = nextActiveKnot(s, -1);
            if (first >= 0 && a >= 0 && a != first) {
                float2 p0 = _Tex0[a].anchor * R, c0 = _Tex0[a].handle_out * R;
                float2 c1 = _Tex0[first].handle_in * R, p1 = _Tex0[first].anchor * R;
                float2 prev = p0;
                [loop] for (int k = 1; k <= 16; k++) {
                    float2 cur = cubicPoint(p0, c0, c1, p1, (float)k / 16.0);
                    col += ink * amt * sui3Line(P, prev, cur, isActive ? 1.6 : 1.2);
                    prev = cur;
                }
            }
        }
    }

    // ---- knots, handles, selection -----------------------------------------
    [loop] for (uint i = 0u; i < 64u; i++) {
        SplineKnot k = _Tex0[i];
        if (k.active < 0.5) continue;
        bool sel  = knotSelected(k);
        bool mine = (k.spline_id == lane);
        float2 aPx  = k.anchor * R;
        float2 hiPx = k.handle_in * R;
        float2 hoPx = k.handle_out * R;

        // Handle guides stay at rule weight: they are scaffolding, not content.
        col += T.rule * 0.75 * (sui3Line(P, aPx, hiPx, 1.0) + sui3Line(P, aPx, hoPx, 1.0));

        // TANGENT MODE IS THE TERMINAL SHAPE. A number in a corner would tell
        // you the mode of the selection; the shape tells you the mode of the
        // knot you are looking at, which is the question you actually have while
        // editing.
        float term = 0.0;
        if (k.tangent_mode == 0u) {                     // free: open ring
            term = sui3Ring(P, hiPx, 4.0, 1.2) + sui3Ring(P, hoPx, 4.0, 1.2);
        } else if (k.tangent_mode == 1u) {              // aligned: ring plus bar
            term = sui3Ring(P, hiPx, 4.0, 1.2) + sui3Ring(P, hoPx, 4.0, 1.2);
            float2 d = normalize(hoPx - hiPx + 1e-5);
            term += sui3Line(P, hiPx - d * 5.0, hiPx + d * 5.0, 1.0);
            term += sui3Line(P, hoPx - d * 5.0, hoPx + d * 5.0, 1.0);
        } else {                                        // mirrored: filled
            term = sui3Disc(P, hiPx, 3.6) + sui3Disc(P, hoPx, 3.6);
        }
        col += (mine ? T.mid : T.rule) * saturate(term);

        // Anchor: a square reads as an editable vertex where a disc reads as a
        // sample point, and the two must not be confused on a desk that shows
        // both.
        float half = sel ? 5.0 : 3.5;
        float4 box = float4(aPx - half, aPx + half);
        col += (sel ? T.ink : (mine ? T.mid : T.rule)) * sui3Frame(P, box);

        // SELECTION IS A BRACKET, NOT A FILL. Amber is reserved for meaning and
        // selection is the meaning; brackets keep the anchor's own position
        // readable underneath instead of covering it.
        if (sel) col += T.accent * sui3Brackets(P, float4(aPx - 9.0, aPx + 9.0), 4.0);
    }

    // ---- marquee ------------------------------------------------------------
    if ((uint)round(st.target_kind) == 5u && st.command > 0.0 && st.command < 4.0) {
        float4 m = float4(min(st.marquee_start, st.marquee_end) * R,
                          max(st.marquee_start, st.marquee_end) * R);
        col += T.accent * 0.85 * sui3Frame(P, m);
        col += T.accent * 0.06 * sui3RectIn(P, m);
    }

    // ---- toolbar ------------------------------------------------------------
    float4 rTool = sdPx(UI_RECT_TOOL, R);
    float4 rTan  = sdPx(UI_RECT_TANGENT, R);
    float4 rCls  = sdPx(UI_RECT_CLOSE, R);
    float4 rDel  = sdPx(UI_RECT_DELETE, R);

    // A plate behind the toolbar so the field cannot show through and make the
    // labels unreadable over a dense path.
    float4 bar = float4(0.0, 0.0, R.x, rTool.w + 0.014 * R.y);
    col = lerp(col, T.field, sui3RectIn(P, bar) * 0.92);
    col += T.rule * sui3HairAt(P.y, bar.w);

    if (sdCapFits(rTool.y, sB))
        col += T.ink * sui3Text(P, float2(pad, rTool.y - 12.0 * sB), sB,
            S_S,S_P,S_L,S_I,S_N,S_E,S_SP,S_D,S_E,S_S,S_K,0);

    // Tool: two cells on one slider. The selected cell is amber-underlined --
    // an established live value, which is exactly what the accent is reserved
    // for -- and the unselected one is plain.
    {
        float cw = (rTool.z - rTool.x) * 0.5;
        [loop] for (int c = 0; c < 2; c++) {
            float4 rc = float4(rTool.x + (float)c * cw, rTool.y,
                               rTool.x + (float)(c + 1) * cw - 3.0, rTool.w);
            bool on = ((int)round(st.tool) == c);
            if (sui3RectIn(P, rc) > 0.5 || sui3Frame(P, rc) > 0.0) {
                col = lerp(col, float3(0,0,0), sui3RectIn(P, rc));
                col += sui3BankCell(P, rc, on, T);
            }
            float2 ta = float2(rc.x + 6.0 * sB, rc.y + (rc.w - rc.y) * 0.5 - 5.0 * sB);
            col += (on ? T.accent : T.dim) * (c == 0
                ? sui3Text(P, ta, sB, S_S,S_E,S_L,0,0,0,0,0,0,0,0,0)
                : sui3Text(P, ta, sB, S_P,S_E,S_N,0,0,0,0,0,0,0,0,0));
        }
    }

    // Action plates. The pressed look comes from the control's own down bit, so
    // it reflects the real host interaction rather than a value the shader keeps.
    {
        float4 rs[3]  = { rTan, rCls, rDel };
        bool  down[3] = { suiInteraction(UI_INDEX_TANGENT).down,
                          suiInteraction(UI_INDEX_CLOSE).down,
                          suiInteraction(UI_INDEX_DELETE).down };
        [loop] for (int a2 = 0; a2 < 3; a2++) {
            float4 rc = rs[a2];
            if (sui3RectIn(P, rc) > 0.5 || sui3Frame(P, rc) > 0.0) {
                col = lerp(col, float3(0,0,0), sui3RectIn(P, rc));
                col += T.well * sui3RectIn(P, rc) * (down[a2] ? 2.2 : 1.0);
                col += T.rule * sui3Frame(P, rc);
            }
            float2 ta = float2(rc.x + 6.0 * sB, rc.y + (rc.w - rc.y) * 0.5 - 5.0 * sB);
            if (a2 == 0) col += T.dim * sui3Text(P, ta, sB, S_T,S_A,S_N,S_G,0,0,0,0,0,0,0,0);
            if (a2 == 1) col += T.dim * sui3Text(P, ta, sB, S_C,S_L,S_S,0,0,0,0,0,0,0,0,0);
            if (a2 == 2) col += T.dim * sui3Text(P, ta, sB, S_D,S_E,S_L,0,0,0,0,0,0,0,0,0);
        }
    }

    // ---- telemetry ----------------------------------------------------------
    // Counted here rather than published as a control output because these are
    // facts about what is on screen, and they must agree with what is on screen.
    int selCount = 0, knotCount = 0, laneCount = 0;
    [loop] for (uint q = 0u; q < 64u; q++) {
        if (_Tex0[q].active < 0.5) continue;
        knotCount++;
        if (_Tex0[q].spline_id == lane) laneCount++;
        if (knotSelected(_Tex0[q])) selCount++;
    }

    float ty = R.y - pad - 11.0 * sB;
    float tx = pad;
    col += T.dim * sui3Text(P, float2(tx, ty), sB, S_L,S_A,S_N,S_E,0,0,0,0,0,0,0,0);
    tx += sui3TextWidth(5, sB);
    col += T.accent * sui3Digits(P, float2(tx, ty), sB, (int)lane + 1, 1);
    tx += sui3TextWidth(3, sB);

    col += T.dim * sui3Text(P, float2(tx, ty), sB, S_T,S_A,S_N,S_G,0,0,0,0,0,0,0,0);
    tx += sui3TextWidth(5, sB);
    // The mode spelled out, because "1" is not a tangent mode anyone recognises.
    col += T.accent * (tmode == 0u ? sui3Text(P, float2(tx, ty), sB, S_F,S_R,S_E,S_E,0,0,0,0,0,0,0,0)
                     : tmode == 1u ? sui3Text(P, float2(tx, ty), sB, S_A,S_L,S_G,S_N,0,0,0,0,0,0,0,0)
                                   : sui3Text(P, float2(tx, ty), sB, S_M,S_I,S_R,S_R,0,0,0,0,0,0,0,0));
    tx += sui3TextWidth(6, sB);

    col += T.dim * sui3Text(P, float2(tx, ty), sB, S_S,S_E,S_L,0,0,0,0,0,0,0,0,0);
    tx += sui3TextWidth(4, sB);
    col += T.accent * sui3Digits(P, float2(tx, ty), sB, selCount, 2);
    tx += sui3TextWidth(4, sB);

    col += T.dim * sui3Text(P, float2(tx, ty), sB, S_K,S_N,S_O,S_T,S_S,0,0,0,0,0,0,0);
    tx += sui3TextWidth(6, sB);
    col += T.ink * sui3Digits(P, float2(tx, ty), sB, laneCount, 2);
    col += T.dim * sui3Text(P, float2(tx + sui3TextWidth(2, sB), ty), sB, S_SL,0,0,0,0,0,0,0,0,0,0,0);
    col += T.dim * sui3Digits(P, float2(tx + sui3TextWidth(3, sB), ty), sB, knotCount, 2);

    col += T.rule * 0.7 * sui3Registration(P, R, 14.0 * sB);

    OutputUAV[tid.xy] = float4(saturate(col), 1.0);
}
