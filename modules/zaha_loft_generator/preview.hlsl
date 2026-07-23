#include "../_shared/ui/sui_v2.hlsli"
#include "_ui.generated.hlsli"
#include "../_shared/ui/sui_generated_text.hlsli"
#include "types.hlsli"

StructuredBuffer<LoftSection> Sections : register(t0);
RWTexture2D<float4> OutputUAV : register(u0);

SuiTheme zTheme() {
    SuiTheme t = suiMonochromeTheme();
    t.background = float3(0.003, 0.005, 0.008);
    t.panel = float3(0.010, 0.014, 0.020);
    t.panelRaised = float3(0.018, 0.025, 0.034);
    t.control = float3(0.025, 0.035, 0.046);
    t.controlHover = float3(0.050, 0.075, 0.092);
    t.controlDown = float3(0.20, 0.95, 0.78);
    t.text = float3(0.88, 0.96, 0.98);
    t.muted = float3(0.35, 0.48, 0.55);
    t.border = float3(0.08, 0.20, 0.24);
    t.accent = float3(0.20, 0.95, 0.78);
    t.axisY = float3(0.95, 0.32, 0.62);
    return t;
}

float2 sideUv(LoftSection s) {
    return float2(0.25 + s.center.x / 42.0, 0.86 - s.center.y / 32.0);
}

float2 planUv(LoftSection s) {
    return float2(0.75 + s.center.x / 42.0, 0.53 + s.center.z / 26.0);
}

[numthreads(8,8,1)]
void main(uint3 tid : SV_DispatchThreadID) {
    if (tid.x >= (uint)_Resolution.x || tid.y >= (uint)_Resolution.y) return;
    SuiContext c = suiContext(tid.xy, _Resolution.xy);
    SuiTheme theme = zTheme();
    float3 col = theme.background;
    suiComposite(col, float3(0.012,0.018,0.024), suiGridPx(c, 28.0, 0.45));
    suiComposite(col, theme.panelRaised, suiFillRect(c, float4(0.0,0.0,1.0,0.115)));
    suiComposite(col, theme.accent, suiFillRect(c, float4(0.0,0.0,0.004,0.115)));
    suiComposite(col, theme.text, suiLabelText(c, float2(0.025,0.038), suiTitleStyle(), UI_LABEL_TITLE));
    suiComposite(col, theme.muted, suiLabelText(c, float2(0.025,0.082), suiBodyStyle(), UI_LABEL_SUBTITLE));

    float4 sideRect = float4(0.03,0.15,0.48,0.91);
    float4 planRect = float4(0.52,0.15,0.97,0.91);
    suiPanel(col,c,theme,sideRect,true);
    suiPanel(col,c,theme,planRect,true);
    suiComposite(col,theme.muted,suiLabelText(c,float2(0.05,0.17),suiSectionStyle(),UI_LABEL_MORPH));
    suiComposite(col,theme.muted,suiLabelText(c,float2(0.54,0.17),suiSectionStyle(),UI_LABEL_TORSION));

    [loop] for (uint i=0u;i<96u;i++) {
        LoftSection s=Sections[i]; if(s.active<0.5) continue;
        float fade=0.18+0.82*s.u;
        float3 tint=lerp(theme.axisY,theme.accent,s.skin_bias)*fade;
        float2 a=sideUv(s); float2 b=planUv(s);
        float sideR=max(1.2,s.radius_x/21.0*_Resolution.x);
        float planRX=max(1.0,s.radius_x/21.0*_Resolution.x);
        float planRY=max(1.0,s.radius_z/13.0*_Resolution.y);
        float sideBand=suiLinePx(c,a-float2(sideR,0)*c.invResolution,a+float2(sideR,0)*c.invResolution,0.75);
        float planBand=suiRingPx(c,b,max(planRX,planRY)*0.22,0.8);
        suiComposite(col,tint,sideBand*0.62);
        suiComposite(col,tint,planBand*0.36);
        if((i%8u)==0u){suiComposite(col,theme.text,suiDiscPx(c,a,2.2));suiComposite(col,theme.accent,suiDiscPx(c,b,2.0));}
    }

    suiComposite(col,theme.accent,suiRingPx(c,morph_field,11.0,1.5));
    suiComposite(col,theme.axisY,suiRingPx(c,torsion_field,11.0,1.5));
    suiComposite(col,theme.accent,suiLinePx(c,float2(morph_field.x,sideRect.y),float2(morph_field.x,sideRect.w),0.7)*0.45);
    suiComposite(col,theme.axisY,suiLinePx(c,float2(planRect.x,torsion_field.y),float2(planRect.z,torsion_field.y),0.7)*0.45);
    OutputUAV[tid.xy]=float4(saturate(col),1.0);
}
