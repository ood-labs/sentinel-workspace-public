#include "../_shared/ui/sui_v2.hlsli"
#include "_ui.generated.hlsli"
#include "../_shared/ui/sui_generated_text.hlsli"

RWTexture2D<float4> OutputUAV : register(u0);

float luminance(float3 c)
{
    return dot(c, float3(0.2126, 0.7152, 0.0722));
}

float rectMask(float2 uv, float4 rect)
{
    return step(rect.x, uv.x) * step(rect.y, uv.y) *
           step(uv.x, rect.z) * step(uv.y, rect.w);
}

float2 rectUv(float2 uv, float4 rect)
{
    return saturate((uv - rect.xy) / max(rect.zw - rect.xy, float2(1e-5, 1e-5)));
}

float sampleLuma(Texture2D<float4> tex, float2 uv)
{
    return luminance(tex.SampleLevel(PointSampler, saturate(uv), 0).rgb);
}

float sourceEnergy(Texture2D<float4> tex, float2 uv)
{
    float3 c = tex.SampleLevel(PointSampler, saturate(uv), 0).rgb;
    return max(c.r, max(c.g, c.b));
}

float lineSegmentPx(SuiContext c, float2 a, float2 b, float widthPx)
{
    return suiLinePx(c, a, b, widthPx);
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;

    SuiContext c = suiContext(pixel, _Resolution.xy);
    SuiTheme theme = suiMonochromeTheme();
    theme.accent = accent;

    uint loomW, loomH, seismicW, seismicH, towerW, towerH;
    _Tex0.GetDimensions(loomW, loomH);
    _Tex1.GetDimensions(seismicW, seismicH);
    _Tex2.GetDimensions(towerW, towerH);
    float2 loomTexel = 1.0 / max(float2(loomW, loomH), float2(1.0, 1.0));
    float2 seismicTexel = 1.0 / max(float2(seismicW, seismicH), float2(1.0, 1.0));

    const float4 loomRect = float4(0.035, 0.105, 0.275, 0.390);
    const float4 seismicRect = float4(0.035, 0.455, 0.275, 0.735);
    const float4 stageRect = UI_RECT_IMPACT_CENTER;
    const float4 traceRect = float4(0.035, 0.805, 0.965, 0.940);

    float3 col = theme.background;
    float panelGrid = suiGridPx(c, 48.0, 1.0);
    suiComposite(col, theme.panel, panelGrid * 0.34);

    float loomInside = rectMask(c.uv, loomRect);
    float seismicInside = rectMask(c.uv, seismicRect);
    float stageInside = rectMask(c.uv, stageRect);
    float traceInside = rectMask(c.uv, traceRect);

    float2 loomUv = rectUv(c.uv, loomRect);
    float2 seismicUv = rectUv(c.uv, seismicRect);
    float2 stageUv = rectUv(c.uv, stageRect);
    float2 traceUv = rectUv(c.uv, traceRect);

    float3 loomPreview = _Tex0.SampleLevel(PointSampler, loomUv, 0).rgb;
    float3 seismicPreview = _Tex1.SampleLevel(PointSampler, seismicUv, 0).rgb;
    loomPreview = pow(saturate(loomPreview), 0.82);
    seismicPreview = pow(saturate(seismicPreview), 0.78);
    suiComposite(col, loomPreview, loomInside);
    suiComposite(col, seismicPreview, seismicInside);

    // The impact center relocates the Seismic domain itself. This is the
    // producer/consumer contract: the pad moves force, not just a reticle.
    float2 fromImpact = stageUv - impact_center;
    float fieldExtent = max(lens_radius * 1.55, 0.10);
    float2 fieldUv = saturate(0.5 + fromImpact / fieldExtent);
    float s0 = sourceEnergy(_Tex1, fieldUv);
    float sxp = sourceEnergy(_Tex1, fieldUv + float2(seismicTexel.x, 0.0));
    float sxm = sourceEnergy(_Tex1, fieldUv - float2(seismicTexel.x, 0.0));
    float syp = sourceEnergy(_Tex1, fieldUv + float2(0.0, seismicTexel.y));
    float sym = sourceEnergy(_Tex1, fieldUv - float2(0.0, seismicTexel.y));
    float2 seismicGradient = float2(sxp - sxm, syp - sym) * 0.5;

    float l0 = sampleLuma(_Tex0, stageUv);
    float lxp = sampleLuma(_Tex0, stageUv + float2(loomTexel.x, 0.0));
    float lxm = sampleLuma(_Tex0, stageUv - float2(loomTexel.x, 0.0));
    float lyp = sampleLuma(_Tex0, stageUv + float2(0.0, loomTexel.y));
    float lym = sampleLuma(_Tex0, stageUv - float2(0.0, loomTexel.y));
    float2 loomGradient = float2(lxp - lxm, lyp - lym) * 0.5;

    float impactDistance = length(fromImpact * float2(1.0, 1.13));
    float lens = 1.0 - smoothstep(lens_radius * 0.38, lens_radius, impactDistance);
    float2 radial = fromImpact / max(impactDistance, 1e-4);
    float seismicEnergy = saturate(s0 * seismic_gain);
    float seismicEdge = saturate(length(seismicGradient) * 10.0);
    float cellGate = smoothstep(0.08, 0.62, seismicEnergy);
    float phaseWave = sin(6.2831853 * (master_phase + stageUv.y * 0.22));

    float2 pushForce = (-seismicGradient * 4.5 + radial * (0.12 + seismicEnergy * 0.88));
    pushForce.y += seismicEnergy * (0.72 + 0.28 * phaseWave);
    float2 shearForce = float2(
        (seismicEnergy - 0.22) * (stageUv.y - impact_center.y) * 2.8,
        -seismicGradient.x * 1.6 + seismicEnergy * 0.28);
    float foldSign = stageUv.x < impact_center.x ? -1.0 : 1.0;
    float2 foldForce = float2(
        foldSign * seismicEnergy * (0.34 + 0.66 * lens),
        abs(stageUv.x - impact_center.x) * seismicEnergy * 1.25);

    float modePush = 1.0 - step(0.5, interaction_mode);
    float modeShear = step(0.5, interaction_mode) * (1.0 - step(1.5, interaction_mode));
    float modeFold = step(1.5, interaction_mode);
    float2 force = pushForce * modePush + shearForce * modeShear + foldForce * modeFold;
    force += loomGradient * frame_tension * (5.0 + 3.0 * l0);
    force *= lens * cellGate;

    float amount = displacement * response *
                   (0.42 + 0.42 * master_envelope + 0.16 * master_pulse);
    float2 displacementVector = force * amount;
    float2 towerUv = saturate(stageUv - displacementVector);
    float3 towerBody = _Tex2.SampleLevel(PointSampler, towerUv, 0).rgb;

    float trailLuma = 0.0;
    float3 trailColor = 0.0;
    [unroll] for (int i = 1; i <= 6; ++i)
    {
        float t = (float)i / 6.0;
        float2 trailUv = saturate(stageUv - displacementVector * (1.0 - t) +
                                  float2(0.0, amount * seismicEnergy * t * 0.48));
        float3 tap = _Tex2.SampleLevel(PointSampler, trailUv, 0).rgb;
        float tapLuma = luminance(tap);
        float wins = step(trailLuma, tapLuma);
        trailColor = lerp(trailColor, tap, wins);
        trailLuma = max(trailLuma, tapLuma);
    }

    float bodyLuma = luminance(towerBody);
    float exposedTrail = saturate(trailLuma - bodyLuma * 0.78);
    float3 stageColor = towerBody;
    stageColor = saturate((stageColor - 0.28) * tower_contrast + 0.28);
    stageColor += theme.muted * exposedTrail * 0.62;
    stageColor = lerp(stageColor, accent, seismicEdge * lens * 0.20);

    float tear = smoothstep(0.055, 0.36, length(displacementVector) * 8.0);
    float fracture = seismicEdge * lens * tear;
    stageColor += accent * fracture * 0.42;

    float loomQuant = abs(frac((l0 + stageUv.y * 0.35) * 12.0) - 0.5);
    float tensionMark = (1.0 - smoothstep(0.47, 0.50, loomQuant)) *
                        (1.0 - smoothstep(0.05, 0.22, exposedTrail));
    stageColor += theme.text * tensionMark * frame_tension * 0.13;
    suiComposite(col, stageColor, stageInside);

    // A live oscilloscope strip sampled from the real Seismic and Loom fields.
    float traceEnergy = sourceEnergy(_Tex1, float2(traceUv.x, 0.5 + 0.18 * sin(6.2831853 * master_phase)));
    float traceLoom = sampleLuma(_Tex0, float2(traceUv.x, 0.5));
    float energyY = 0.72 - saturate(traceEnergy * seismic_gain) * 0.48;
    float loomY = 0.72 - saturate(traceLoom) * 0.48;
    float energyLine = 1.0 - smoothstep(0.010, 0.026, abs(traceUv.y - energyY));
    float loomLine = 1.0 - smoothstep(0.008, 0.021, abs(traceUv.y - loomY));
    float3 traceColor = theme.panel;
    traceColor += accent * energyLine;
    traceColor += theme.text * loomLine * 0.55;
    suiComposite(col, traceColor, traceInside);

    // Relationship lines make the input-to-force contract explicit.
    [unroll] for (int lane = 0; lane < 5; ++lane)
    {
        float t = ((float)lane + 0.5) / 5.0;
        float e = sourceEnergy(_Tex1, float2(t, 0.5));
        float l = sampleLuma(_Tex0, float2(t, 0.5));
        float2 a = float2(seismicRect.z, lerp(seismicRect.y, seismicRect.w, t));
        float2 loomA = float2(loomRect.z, lerp(loomRect.y, loomRect.w, t));
        float2 b = lerp(stageRect.xy, stageRect.zw, impact_center);
        b += float2((l - 0.5) * 0.025, (e - 0.5) * 0.04);
        float relation = lineSegmentPx(c, a, b, 0.65 + 1.25 * saturate(e));
        float loomRelation = lineSegmentPx(c, loomA, b, 0.55 + 0.85 * saturate(l));
        suiComposite(col, lerp(theme.muted, accent, saturate(e)), relation * 0.42);
        suiComposite(col, theme.muted, loomRelation * frame_tension * 0.22);
    }

    // Input frames remain independent; the main frame flexes with the field.
    suiComposite(col, theme.border, suiStrokeRect(c, loomRect, 2.0));
    suiComposite(col, theme.border, suiStrokeRect(c, seismicRect, 2.0));
    suiComposite(col, theme.border, suiStrokeRect(c, traceRect, 2.0));
    float stageFrame = suiStrokeRect(c, stageRect, 2.0 + frame_tension * 1.5);
    SuiInteraction impactInteraction = suiInteraction(UI_INDEX_IMPACT_CENTER);
    suiComposite(col, impactInteraction.hovered ? theme.text : theme.border, stageFrame);

    float2 impactUv = lerp(stageRect.xy, stageRect.zw, impact_center);
    float radiusPx = lens_radius * min(stageRect.z - stageRect.x, stageRect.w - stageRect.y) *
                     min(c.resolution.x, c.resolution.y);
    suiComposite(col, accent, suiRingPx(c, impactUv, max(radiusPx, 18.0), impactInteraction.down ? 2.6 : 1.2) * 0.34);
    suiComposite(col, theme.text, suiRingPx(c, impactUv, impactInteraction.down ? 9.0 : 6.0, 2.0));
    suiComposite(col, theme.text, suiLinePx(c, impactUv - float2(12.0, 0.0) * c.invResolution,
                                            impactUv + float2(12.0, 0.0) * c.invResolution, 1.0));
    suiComposite(col, theme.text, suiLinePx(c, impactUv - float2(0.0, 12.0) * c.invResolution,
                                            impactUv + float2(0.0, 12.0) * c.invResolution, 1.0));

    SuiTextStyle titleStyle = suiTitleStyle();
    SuiTextStyle sectionStyle = suiSectionStyle();
    suiComposite(col, theme.text, suiLabelText(c, float2(0.035, 0.035), titleStyle, UI_LABEL_TITLE));
    suiComposite(col, theme.text, suiLabelText(c, float2(loomRect.x, 0.075), sectionStyle, UI_LABEL_LOOM));
    suiComposite(col, theme.text, suiLabelText(c, float2(seismicRect.x, 0.425), sectionStyle, UI_LABEL_SEISMIC));
    suiComposite(col, theme.text, suiLabelText(c, float2(stageRect.x, 0.075), sectionStyle, UI_LABEL_DISPLACED_STAGE));
    suiComposite(col, theme.text, suiLabelText(c, float2(traceRect.x, 0.775), sectionStyle, UI_LABEL_FORCE_TRACE));

    OutputUAV[pixel] = float4(saturate(col), 1.0);
}
