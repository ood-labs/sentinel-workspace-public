#include "types.hlsli"
#include "../_shared/ui/sui_v2.hlsli"
#include "_ui.generated.hlsli"
#include "../_shared/ui/sui_generated_text.hlsli"

StructuredBuffer<StimulusRecord> Stimuli : register(t0);
StructuredBuffer<EditorState> State : register(t1);
RWTexture2D<float4> OutputUAV : register(u0);

float4 toolbarRect(uint index) {
    if (index == 0u) return UI_RECT_SEED;
    if (index == 1u) return UI_RECT_VORTEX;
    if (index == 2u) return UI_RECT_ERASE;
    return UI_RECT_CLEAR;
}

uint toolbarIndex(uint index) {
    if (index == 0u) return UI_INDEX_SEED;
    if (index == 1u) return UI_INDEX_VORTEX;
    if (index == 2u) return UI_INDEX_ERASE;
    return UI_INDEX_CLEAR;
}

uint toolbarLabel(uint index) {
    if (index == 0u) return UI_LABEL_SEED;
    if (index == 1u) return UI_LABEL_VORTEX;
    if (index == 2u) return UI_LABEL_ERASE;
    return UI_LABEL_CLEAR;
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    if (tid.x >= (uint)_Resolution.x || tid.y >= (uint)_Resolution.y) return;
    SuiContext context = suiContext(tid.xy, _Resolution.xy);
    SuiTheme theme = suiMonochromeTheme();
    float2 panelUv = ((float2)tid.xy + 0.5) / _Resolution.xy;
    float4 stageRect = seedLabStageRect();
    float3 color = theme.background;
    suiComposite(color, 0.010.xxx, suiGridPx(context, 24.0, 0.75));
    suiComposite(color, theme.panelRaised, suiFillRect(context, float4(0.0, 0.0, 1.0, 72.0 / _Resolution.y)));
    suiComposite(color, theme.text, suiFillRect(context, float4(0.0, 0.0, 4.0 / _Resolution.x, 72.0 / _Resolution.y)));
    suiComposite(color, 0.004.xxx, suiFillRect(context, stageRect));

    float stageBorder = max(
        suiLinePx(context, stageRect.xy, float2(stageRect.z, stageRect.y), 1.0),
        max(suiLinePx(context, float2(stageRect.z, stageRect.y), stageRect.zw, 1.0),
        max(suiLinePx(context, stageRect.zw, float2(stageRect.x, stageRect.w), 1.0),
            suiLinePx(context, float2(stageRect.x, stageRect.w), stageRect.xy, 1.0))));
    suiComposite(color, 0.22.xxx, stageBorder);

    EditorState editor = State[0];
    uint activeCount = 0u;
    [loop] for (uint i = 0u; i < 64u; ++i) {
        StimulusRecord stimulus = Stimuli[i];
        if (!stimulusActive(stimulus)) continue;
        activeCount += 1u;
        float2 p = seedLabStageToPanel(stimulus.position);
        float2 stageSizePx = (stageRect.zw - stageRect.xy) * _Resolution.xy;
        float2 deltaPx = (panelUv - p) * _Resolution.xy;
        float radiusPx = stimulus.radius * stageSizePx.y;
        float distancePx = length(deltaPx);
        float ring = smoothstep(1.6, 0.2, abs(distancePx - radiusPx));
        float core = smoothstep(7.0, 1.5, distancePx);
        float halo = exp(-distancePx * distancePx / max(radiusPx * radiusPx * 0.55, 1.0));
        float strengthUnit = saturate((stimulus.strength - 0.1) / 2.4);
        bool dragged = editor.drag_active > 0.5 && (int)round(editor.target) == (int)i;
        float3 seedColor = dragged
            ? float3(1.0, 0.44, 0.08)
            : (stimulus.mode > 0.5 ? float3(1.0, 0.33, 0.05) : float3(0.78, 0.79, 0.76));
        color += seedColor * (ring * 0.55
            + core * lerp(0.42, 1.05, strengthUnit)
            + halo * lerp(0.035, 0.19, strengthUnit));
        float2 arrowEndStage = saturate(stimulus.position + stimulus.direction * stimulus.radius * 0.65);
        suiComposite(color, seedColor,
            suiLinePx(context, p, seedLabStageToPanel(arrowEndStage), stimulus.mode > 0.5 ? 2.0 : 1.0));
    }

    if (seedLabInsideStage(_ViewportPointerPosition)) {
        float2 cursor = _ViewportPointerPosition;
        float2 stageSizePx = (stageRect.zw - stageRect.xy) * _Resolution.xy;
        float cursorRadius = editor.radius * stageSizePx.y;
        float cursorDistance = length((panelUv - cursor) * _Resolution.xy);
        float cursorRing = smoothstep(1.5, 0.0, abs(cursorDistance - cursorRadius));
        color += (editor.tool > 1.5 ? float3(0.72, 0.12, 0.05) : float3(0.78, 0.79, 0.76)) * cursorRing * 0.55;
    }

    suiComposite(color, theme.text, suiLabelText(context, float2(0.022, 0.030), suiTitleStyle(), UI_LABEL_TITLE));
    [unroll] for (uint button = 0u; button < 4u; ++button) {
        float4 rect = toolbarRect(button);
        bool selected = (button == 0u && editor.tool < 0.5)
                     || (button == 1u && editor.tool > 0.5 && editor.tool < 1.5)
                     || (button == 2u && editor.tool > 1.5);
        suiButton(color, context, theme, rect, suiInteraction(toolbarIndex(button)), selected);
        suiComposite(color, selected ? theme.background : theme.text,
            suiLabelText(context, rect.xy + float2(10.0, 10.0) * context.invResolution,
                         suiBodyStyle(), toolbarLabel(button)));
    }

    suiComposite(color, theme.panelRaised, suiFillRect(context, float4(0.0, 1.0 - 36.0 / _Resolution.y, 1.0, 1.0)));
    suiComposite(color, theme.muted,
        suiLabelText(context, float2(0.022, 1.0 - 27.0 / _Resolution.y), suiBodyStyle(), UI_LABEL_ACTIVE));
    suiComposite(color, theme.text,
        suiInteger(context, float2(0.112, 1.0 - 27.0 / _Resolution.y), suiBodyStyle(), (int)activeCount, 2));
    OutputUAV[tid.xy] = float4(saturate(color), 1.0);
}
