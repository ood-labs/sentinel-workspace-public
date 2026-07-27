#include "../_shared/ui/sui_v2.hlsli"
#include "_ui.generated.hlsli"

struct EvidenceAgent
{
    float2 position;
    float2 direction;
    float weight;
    float radius;
    uint kind;
    uint sourceIndex;
    uint groupId;
    uint active;
    float phase;
    float pad;
};

struct PerformanceMacros
{
    float tension;
    float memory;
    float energy;
    float topology;
    float archiveCut;
    float holdMemory;
    float activeAgents;
    float meanWeight;
};

StructuredBuffer<EvidenceAgent> Agents : register(t1);
StructuredBuffer<PerformanceMacros> Macros : register(t2);
RWTexture2D<float4> OutputUAV : register(u0);

float generatedText(SuiContext c, float2 anchor, SuiTextStyle style, uint labelId)
{
    float coverage = 0.0;
    float advance = 8.0 * style.scalePx + style.trackingPx;
    [loop]
    for (int i = 0; i < uiLabelLength(labelId); ++i)
        coverage = max(coverage, suiGlyph(c, anchor + float2(i * advance, 0.0) * c.invResolution, style, uiLabelCode(labelId, i)));
    return coverage;
}

float4 fittedStage(float4 container, float2 resolution, float targetAspect)
{
    float2 sizePx = (container.zw - container.xy) * resolution;
    float containerAspect = sizePx.x / max(sizePx.y, 1.0);
    float4 stage = container;
    if (containerAspect > targetAspect)
    {
        float fittedWidthNorm = sizePx.y * targetAspect / resolution.x;
        float center = (container.x + container.z) * 0.5;
        stage.x = center - fittedWidthNorm * 0.5;
        stage.z = center + fittedWidthNorm * 0.5;
    }
    else
    {
        float fittedHeightNorm = sizePx.x / targetAspect / resolution.y;
        float center = (container.y + container.w) * 0.5;
        stage.y = center - fittedHeightNorm * 0.5;
        stage.w = center + fittedHeightNorm * 0.5;
    }
    return stage;
}

float stageMask(float2 uv, float4 r)
{
    return step(r.x, uv.x) * step(r.y, uv.y) * step(uv.x, r.z) * step(uv.y, r.w);
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    if (tid.x >= (uint)_Resolution.x || tid.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)tid.xy + 0.5) / _Resolution.xy;
    SuiContext c = suiContext(tid.xy, _Resolution.xy);
    SuiTheme theme = suiMonochromeTheme();
    PerformanceMacros m = Macros[0];

    float3 color = theme.background;
    suiComposite(color, float3(0.018, 0.019, 0.018), suiGridPx(c, 24.0, 0.65));
    float4 shell = float4(0.018, 0.025, 0.982, 0.975);
    suiPanel(color, c, theme, shell, false);
    suiComposite(color, theme.panelRaised, suiFillRect(c, float4(shell.x, shell.y, shell.z, 0.092)));
    suiComposite(color, current_color, suiFillRect(c, float4(shell.x, shell.y, shell.x + 0.0035, 0.092)));
    suiComposite(color, theme.text, generatedText(c, float2(0.038, 0.049), suiTitleStyle(), UI_LABEL_TITLE));

    float4 stageContainer = float4(0.035, 0.125, 0.665, 0.925);
    float4 stage = fittedStage(stageContainer, _Resolution.xy, 16.0 / 9.0);
    suiPanel(color, c, theme, stage, true);

    float inside = stageMask(uv, stage);
    if (inside > 0.5)
    {
        float2 stageUv = (uv - stage.xy) / max(stage.zw - stage.xy, float2(1e-5, 1e-5));
        float3 program = _Tex0.SampleLevel(LinearSampler, stageUv, 0).rgb;
        color = lerp(color, program, inside);

        // Live Evidence overlay: subtle normalized records on the true stage transform.
        float2 stagePx = (stage.zw - stage.xy) * _Resolution.xy;
        float aspect = stagePx.x / max(stagePx.y, 1.0);
        float2 sp = stageUv * float2(aspect, 1.0);
        float overlay = 0.0;
        float warmOverlay = 0.0;
        [loop]
        for (uint i = 0u; i < 64u; ++i)
        {
            EvidenceAgent a = Agents[i];
            if (a.active == 0u) continue;
            float2 q = a.position * float2(aspect, 1.0);
            float d = length(sp - q);
            float marker = 1.0 - smoothstep(0.005, 0.008, abs(d - (0.006 + a.weight * 0.005)));
            overlay = max(overlay, marker * (a.kind == 2u ? 0.55 : 0.25));
            warmOverlay = max(warmOverlay, marker * (a.kind == 1u ? 0.85 : 0.0));
        }
        color += theme.text * overlay;
        color += current_color * warmOverlay;
    }

    suiComposite(color, theme.muted, generatedText(c, float2(stage.x, 0.104), suiSectionStyle(), UI_LABEL_STAGE));
    suiComposite(color, theme.muted, generatedText(c, float2(0.705, 0.126), suiSectionStyle(), UI_LABEL_MACROS));

    suiXYPad(color, c, theme, UI_RECT_PERFORMANCE_PAD, suiInteraction(UI_INDEX_PERFORMANCE_PAD), performance_pad);
    suiSlider(color, c, theme, UI_RECT_ENERGY, suiInteraction(UI_INDEX_ENERGY), energy);
    suiSlider(color, c, theme, UI_RECT_TOPOLOGY, suiInteraction(UI_INDEX_TOPOLOGY), (float)topology / 2.0);
    suiButton(color, c, theme, UI_RECT_ARCHIVE_CUT, suiInteraction(UI_INDEX_ARCHIVE_CUT), archive_cut != 0);
    suiButton(color, c, theme, UI_RECT_HOLD_MEMORY, suiInteraction(UI_INDEX_HOLD_MEMORY), hold_memory != 0);

    SuiTextStyle body = suiBodyStyle();
    suiComposite(color, theme.muted, generatedText(c, float2(UI_RECT_PERFORMANCE_PAD.x, 0.194), body, UI_LABEL_CONTROL_PERFORMANCE_PAD));
    suiComposite(color, theme.muted, generatedText(c, float2(UI_RECT_ENERGY.x, 0.635), body, UI_LABEL_CONTROL_ENERGY));
    suiComposite(color, theme.muted, generatedText(c, float2(UI_RECT_TOPOLOGY.x, 0.744), body, UI_LABEL_CONTROL_TOPOLOGY));
    float2 topologyTextAnchor = float2(UI_RECT_TOPOLOGY.x + 0.012, UI_RECT_TOPOLOGY.y + 0.014);
    suiComposite(color, theme.text, generatedText(c, topologyTextAnchor, body, UI_LABEL_MODE_CHOIR) * (topology == 0));
    suiComposite(color, theme.text, generatedText(c, topologyTextAnchor, body, UI_LABEL_MODE_EXCAVATION) * (topology == 1));
    suiComposite(color, theme.text, generatedText(c, topologyTextAnchor, body, UI_LABEL_MODE_SEVERED) * (topology == 2));
    suiComposite(color, theme.muted, generatedText(c, float2(0.705, 0.865), body, UI_LABEL_EXECUTE));
    suiComposite(color, archive_cut != 0 ? current_color : theme.text, generatedText(c, float2(UI_RECT_ARCHIVE_CUT.x + 0.010, UI_RECT_ARCHIVE_CUT.y + 0.014), body, UI_LABEL_CONTROL_ARCHIVE_CUT));
    suiComposite(color, hold_memory != 0 ? current_color : theme.text, generatedText(c, float2(UI_RECT_HOLD_MEMORY.x + 0.010, UI_RECT_HOLD_MEMORY.y + 0.014), body, UI_LABEL_CONTROL_HOLD_MEMORY));

    float4 telemetry = float4(0.705, 0.535, 0.948, 0.598);
    suiControlFrame(color, c, theme, telemetry);
    float activeFill = saturate(m.activeAgents / 48.0);
    float weightFill = saturate(m.meanWeight);
    suiComposite(color, theme.text, suiFillRect(c, float4(telemetry.x + 0.012, telemetry.y + 0.016, lerp(telemetry.x + 0.012, telemetry.z - 0.012, activeFill), telemetry.y + 0.026)));
    suiComposite(color, current_color, suiFillRect(c, float4(telemetry.x + 0.012, telemetry.y + 0.038, lerp(telemetry.x + 0.012, telemetry.z - 0.012, weightFill), telemetry.y + 0.048)));

    float status = m.archiveCut > 0.5 ? 1.0 : (m.holdMemory > 0.5 ? 0.72 : m.energy);
    suiStatus(color, c, theme, float4(0.705, 0.945, 0.948, 0.966), status);

    OutputUAV[tid.xy] = float4(saturate(color), 1.0);
}
