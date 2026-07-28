// Living Room Furnishings Plan Editor — sui3 port.
//
// This remains a spatial editor: tool and command controls stay on Canvas
// because they operate the plan directly. Exact authored offsets stay in
// Properties.
#include "types.hlsli"
#include "../_shared/ui/sui3_controls.hlsli"
#include "_ui.generated.hlsli"

StructuredBuffer<PNode> _Tex0 : register(t0);
StructuredBuffer<EditorState> _Tex1 : register(t1);
RWTexture2D<float4> OutputUAV : register(u0);

float box2(float2 p, float2 b) {
    float2 q = abs(p) - b;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0);
}

float segment2(float2 p, float2 a, float2 b) {
    float2 pa = p - a, ba = b - a;
    float h = saturate(dot(pa, ba) / max(dot(ba, ba), 1e-6));
    return length(pa - ba * h);
}

float4 pxRect(float4 r, float2 R) {
    return float4(r.x * R.x, r.y * R.y, r.z * R.x, r.w * R.y);
}

float3 objectTone(uint objectId, Sui3Theme T) {
    float lane = fmod((float)objectId, 4.0) / 3.0;
    return lerp(T.mid * 0.72, T.ink * 0.78, lane);
}

[numthreads(8,8,1)]
void main(uint3 tid : SV_DispatchThreadID) {
    if (tid.x >= (uint)_Resolution.x || tid.y >= (uint)_Resolution.y) return;

    float2 R = _Resolution.xy;
    float2 P = (float2)tid.xy + 0.5;
    float2 uv = P / R;
    float k = min(R.x / 1280.0, R.y / 720.0);
    float sB = k >= 2.6 ? 3.0 : k >= 1.7 ? 2.0 : 1.0;
    float sN = 2.0 * sB;
    float sT = 3.0 * sB;
    float pad = max(12.0, 0.026 * R.x);

    Sui3Theme T = sui3Theme(SUI3_AMBER);
    EditorState editor = _Tex1[0];
    float3 col = T.field;

    // Toolbar: the declared host rects remain the single hit-test authority.
    float toolbarBottom = LR_PLAN_TOP * R.y;
    col += T.well * sui3RectIn(P, float4(0.0, 0.0, R.x, toolbarBottom));
    col += T.rule * sui3HairAt(P.y, toolbarBottom);

    float4 rects[6] = {
        pxRect(UI_RECT_MOVE, R), pxRect(UI_RECT_ROTATE, R),
        pxRect(UI_RECT_SNAP, R), pxRect(UI_RECT_FIT, R),
        pxRect(UI_RECT_RESET, R), pxRect(UI_RECT_RESET_ALL, R)
    };
    [unroll] for (uint i = 0u; i < 6u; ++i) {
        bool active = (i == 0u && editor.mode < 0.5)
                   || (i == 1u && editor.mode > 0.5)
                   || (i == 2u && editor.snap_enabled > 0.5);
        col += (i == 2u) ? sui3Toggle(P, rects[i], active, T)
                         : sui3BankCell(P, rects[i], active, T);
    }

    float ty0 = rects[0].y + max(3.0, (rects[0].w - rects[0].y - 7.0 * sB) * 0.5);
    float ty1 = rects[1].y + max(3.0, (rects[1].w - rects[1].y - 7.0 * sB) * 0.5);
    float ty2 = rects[2].y + max(3.0, (rects[2].w - rects[2].y - 7.0 * sB) * 0.5);
    float ty3 = rects[3].y + max(3.0, (rects[3].w - rects[3].y - 7.0 * sB) * 0.5);
    float ty4 = rects[4].y + max(3.0, (rects[4].w - rects[4].y - 7.0 * sB) * 0.5);
    float ty5 = rects[5].y + max(3.0, (rects[5].w - rects[5].y - 7.0 * sB) * 0.5);
    col += (editor.mode < 0.5 ? T.accent : T.ink) * sui3Text(P, float2(rects[0].x + 7.0*sB, ty0), sB, S_M,S_O,S_V,S_E,0,0,0,0,0,0,0,0);
    col += (editor.mode > 0.5 ? T.accent : T.ink) * sui3Text(P, float2(rects[1].x + 7.0*sB, ty1), sB, S_R,S_O,S_T,S_A,S_T,S_E,0,0,0,0,0,0);
    col += (editor.snap_enabled > 0.5 ? T.accent : T.ink) * sui3Text(P, float2(rects[2].x + 7.0*sB, ty2), sB, S_S,S_N,S_A,S_P,0,0,0,0,0,0,0,0);
    col += T.ink * sui3Text(P, float2(rects[3].x + 7.0*sB, ty3), sB, S_F,S_I,S_T,0,0,0,0,0,0,0,0,0);
    if (R.x >= 700.0) {
        col += T.ink * sui3Text(P, float2(rects[4].x + 7.0*sB, ty4), sB, S_R,S_E,S_S,S_E,S_T,0,0,0,0,0,0,0);
        col += T.ink * sui3Text(P, float2(rects[5].x + 7.0*sB, ty5), sB, S_R,S_E,S_S,S_E,S_T,S_SP,S_A,S_L,S_L,0,0,0);
    } else {
        // The hit regions remain unchanged; compact labels prevent command
        // text from colliding at the narrow dock proof extent.
        col += T.ink * sui3Text(P, float2(rects[4].x + 5.0, ty4), sB, S_R,S_S,S_T,0,0,0,0,0,0,0,0,0);
        col += T.ink * sui3Text(P, float2(rects[5].x + 5.0, ty5), sB, S_A,S_L,S_L,0,0,0,0,0,0,0,0,0);
    }

    // Aspect-correct plan field.
    if (uv.y >= LR_PLAN_TOP) {
        float4 plan = float4(0.0, toolbarBottom, R.x, R.y);
        float2 world = lrPlanWorld(uv, editor.view_pan, editor.view_zoom);
        float2 grid = abs(frac(world) - 0.5);
        float gridLine = 1.0 - smoothstep(0.47, 0.495, min(grid.x, grid.y));
        col += T.rule * 0.18 * gridLine;
        col += T.rule * 0.55 * (1.0 - smoothstep(0.012, 0.025, abs(world.x)));
        col += T.rule * 0.55 * (1.0 - smoothstep(0.012, 0.025, abs(world.y)));
        col += T.rule * 0.58 * sui3Registration(P - float2(0.0, toolbarBottom),
                                                float2(R.x, R.y - toolbarBottom),
                                                14.0 * sB);

        float worldPerPixel = lrPlanSpan().y
                            / max(R.y * (1.0 - LR_PLAN_TOP) * editor.view_zoom, 1.0);
        [loop] for (uint n = 0u; n < LR_RECORD_COUNT; ++n) {
            PNode node = _Tex0[n];
            uint objectId = lrObjectForRecord(n);
            float2 local = lrRotate(world - node.position.xz, -node.yaw);
            float d = box2(local, max(float2(node.width, node.depth) * 0.5, 0.05));
            float fill = smoothstep(worldPerPixel * 1.3, -worldPerPixel * 0.55, d);
            float edge = 1.0 - smoothstep(worldPerPixel * 0.65,
                                          worldPerPixel * 1.75, abs(d));
            bool selected = lrSelected(objectId);
            float3 tone = selected ? T.accent : objectTone(objectId, T);
            col = lerp(col, selected ? T.accent * 0.18 : tone * 0.23,
                       fill * (selected ? 0.72 : 0.52));
            col += tone * edge * (selected ? 1.15 : 0.76);
            float2 dir = normalize(node.dir + 1e-5);
            float arrow = 1.0 - smoothstep(worldPerPixel * 0.65,
                                            worldPerPixel * 1.75,
                                            segment2(world, node.position.xz,
                                                node.position.xz + dir * 0.42));
            col += tone * arrow * 0.66;
        }

        uint selectedId = _ViewportSelectionMeta.y;
        if (selectedId > 0u) {
            float2 center = 0.0;
            float count = 0.0;
            [loop] for (uint q = 0u; q < LR_RECORD_COUNT; ++q) {
                if (lrObjectForRecord(q) == selectedId) {
                    center += _Tex0[q].position.xz;
                    count += 1.0;
                }
            }
            center /= max(count, 1.0);
            float2 cpx = lrWorldPlan(center, editor.view_pan, editor.view_zoom) * R;
            if (editor.mode < 0.5) {
                col += T.accent * (1.0 - smoothstep(0.75, 1.8,
                    segment2(P, cpx, cpx + float2(58.0, 0.0))));
                col += T.ink * (1.0 - smoothstep(0.75, 1.8,
                    segment2(P, cpx, cpx + float2(0.0, -58.0))));
            } else {
                col += T.accent * (1.0 - smoothstep(0.75, 1.8,
                    abs(length(P - cpx) - 42.0)));
            }
        }

        // Three measured text scales, attached to real selection state.
        float titleY = toolbarBottom + 13.0 * sB;
        float titleW = R.x >= 700.0 ? 255.0 * sB : 126.0 * sB;
        col = lerp(col, T.field,
                   0.90 * sui3RectIn(P, float4(pad - 5.0*sB, titleY - 5.0*sB,
                                                pad + titleW, titleY + 43.0*sB)));
        if (R.x >= 700.0) {
            col += T.ink * sui3TextLong(P, float2(pad, titleY), sT,
                S_F,S_U,S_R,S_N,S_I,S_S,S_H,S_I,S_N,S_G,S_S,S_SP,
                S_P,S_L,S_A,S_N,0,0,0,0,0,0,0,0);
        } else {
            col += T.ink * sui3Text(P, float2(pad, titleY), sT,
                S_R,S_O,S_O,S_M,S_SP,S_P,S_L,S_A,S_N,0,0,0);
        }
        col += T.dim * sui3TextLong(P, float2(pad, titleY + 27.0*sB), sB,
            S_C,S_L,S_I,S_C,S_K,S_SP,S_SL,S_SP,S_D,S_R,S_A,S_G,
            S_SP,S_T,S_O,S_SP,S_E,S_D,S_I,S_T,0,0,0,0);
        if (_ViewportSelectionMeta.y > 0u) {
            col += T.accent * sui3DigitsRight(P, R.x - pad, titleY, sN,
                                              (int)_ViewportSelectionMeta.y, 2);
        }
    }

    OutputUAV[tid.xy] = float4(saturate(col), 1.0);
}
