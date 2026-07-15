#include "types.hlsli"
#include "../_shared/ui/sui_v2.hlsli"
#include "_ui.generated.hlsli"
#include "../_shared/ui/sui_generated_text.hlsli"

struct PNode { float2 pos; float2 dir; float depth; float u; float v; float weight; float group; float kind; float seed; float active; };
StructuredBuffer<SplineKnot> _Tex0 : register(t0);
StructuredBuffer<PNode> _Tex1 : register(t1);
StructuredBuffer<EditorState> _Tex2 : register(t2);
RWTexture2D<float4> OutputUAV : register(u0);

float2 nodeUv(PNode n) { return float2(0.5 + n.pos.x / 3.56, 0.5 - n.pos.y * 0.5); }

float4 toolbarRect(uint index) {
    if (index == 0u) return UI_RECT_SELECT;
    if (index == 1u) return UI_RECT_PEN;
    if (index == 2u) return UI_RECT_TANGENT;
    if (index == 3u) return UI_RECT_CLOSE;
    return UI_RECT_DELETE;
}

uint toolbarControlIndex(uint index) {
    if (index == 0u) return UI_INDEX_SELECT;
    if (index == 1u) return UI_INDEX_PEN;
    if (index == 2u) return UI_INDEX_TANGENT;
    if (index == 3u) return UI_INDEX_CLOSE;
    return UI_INDEX_DELETE;
}

uint toolbarLabel(uint index) {
    if (index == 0u) return UI_LABEL_SELECT;
    if (index == 1u) return UI_LABEL_PEN;
    if (index == 2u) return UI_LABEL_TANGENT;
    if (index == 3u) return UI_LABEL_CLOSE;
    return UI_LABEL_DELETE;
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    if (tid.x >= (uint)_Resolution.x || tid.y >= (uint)_Resolution.y) return;
    SuiContext c = suiContext(tid.xy, _Resolution.xy);
    SuiTheme theme = suiMonochromeTheme();
    float3 color = theme.background;
    suiComposite(color, 0.011.xxx, suiGridPx(c, 24.0, 0.8));
    suiComposite(color, theme.panelRaised, suiFillRect(c, float4(0.0, 0.0, 1.0, 0.122)));
    suiComposite(color, theme.text, suiFillRect(c, float4(0.0, 0.0, 0.0042, 0.122)));

    [loop] for (uint i = 0u; i + 1u < 512u; ++i) {
        PNode a = _Tex1[i], b = _Tex1[i + 1u];
        if (a.active < 0.5 || b.active < 0.5 || (uint)round(a.group) != (uint)round(b.group)) continue;
        float level = 0.58 + 0.06 * fmod(a.group, 4.0);
        suiComposite(color, level.xxx, suiLinePx(c, nodeUv(a), nodeUv(b), path_weight));
    }

    [loop] for (uint i = 0u; i < 64u; ++i) {
        SplineKnot knot = _Tex0[i];
        if (knot.active < 0.5) continue;
        float guides = max(suiLinePx(c, knot.anchor, knot.handle_in, 1.0), suiLinePx(c, knot.anchor, knot.handle_out, 1.0));
        suiComposite(color, theme.muted, guides * 0.75);
        float handles = max(suiDiscPx(c, knot.handle_in, 5.0), suiDiscPx(c, knot.handle_out, 5.0));
        suiComposite(color, theme.accent, handles);
        suiComposite(color, knotSelected(knot) ? theme.text : theme.muted,
            suiDiscPx(c, knot.anchor, knotSelected(knot) ? 8.0 : 6.0));
    }

    EditorState state = _Tex2[0];
    if ((uint)round(state.target_kind) == 5u && state.command > 0.0 && state.command < 4.0) {
        suiMarquee(color, c, theme, float4(min(state.marquee_start, state.marquee_end), max(state.marquee_start, state.marquee_end)));
    }

    suiComposite(color, theme.text, suiLabelText(c, float2(0.025, 0.043), suiTitleStyle(), UI_LABEL_TITLE));
    [unroll] for (uint button = 0u; button < 5u; ++button) {
        float4 rect = toolbarRect(button);
        bool selected = (button == 0u && state.tool < 0.5) || (button == 1u && state.tool > 0.5);
        suiButton(color, c, theme, rect, suiInteraction(toolbarControlIndex(button)), selected);
        float3 labelColor = selected ? theme.background : theme.text;
        suiComposite(color, labelColor,
            suiLabelText(c, rect.xy + float2(10.0, 11.0) * c.invResolution, suiBodyStyle(), toolbarLabel(button)));
    }

    suiComposite(color, theme.panelRaised, suiFillRect(c, float4(0.0, 0.944, 1.0, 1.0)));
    suiComposite(color, theme.muted, suiLabelText(c, float2(0.825, 0.959), suiBodyStyle(), UI_LABEL_SPLINE));
    suiComposite(color, theme.text, suiInteger(c, float2(0.921, 0.959), suiBodyStyle(), (int)round(state.active_spline + 1.0), 1));
    OutputUAV[tid.xy] = float4(saturate(color), 1.0);
}
