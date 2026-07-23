#include "../_shared/ui/sui_v2.hlsli"
#include "_ui.generated.hlsli"
#include "../_shared/ui/sui_generated_text.hlsli"
#include "types.hlsli"
StructuredBuffer<SurfaceInstance> Instances:register(t0);
RWTexture2D<float4> OutputUAV:register(u0);

SuiTheme cTheme(){SuiTheme t=suiMonochromeTheme();t.background=float3(.005,.003,.009);t.panel=float3(.012,.008,.020);t.panelRaised=float3(.024,.014,.034);t.control=float3(.035,.022,.048);t.controlHover=float3(.07,.04,.09);t.controlDown=float3(.96,.45,.14);t.text=float3(.96,.92,.99);t.muted=float3(.49,.36,.58);t.border=float3(.18,.09,.25);t.accent=float3(.96,.45,.14);t.axisY=float3(.30,.92,.98);return t;}

[numthreads(8,8,1)]
void main(uint3 tid:SV_DispatchThreadID){
 if(tid.x>=(uint)_Resolution.x||tid.y>=(uint)_Resolution.y)return;SuiContext c=suiContext(tid.xy,_Resolution.xy);SuiTheme theme=cTheme();float3 col=theme.background;
 suiComposite(col,float3(.020,.012,.030),suiGridPx(c,24,.48));suiComposite(col,theme.panelRaised,suiFillRect(c,float4(0,0,1,.118)));suiComposite(col,theme.accent,suiFillRect(c,float4(0,0,.004,.118)));
 suiComposite(col,theme.text,suiLabelText(c,float2(.025,.037),suiTitleStyle(),UI_LABEL_TITLE));suiComposite(col,theme.muted,suiLabelText(c,float2(.025,.081),suiBodyStyle(),UI_LABEL_SUBTITLE));
 float4 mapRect=float4(.035,.155,.965,.905);suiPanel(col,c,theme,mapRect,true);suiComposite(col,theme.muted,suiLabelText(c,float2(.052,.176),suiSectionStyle(),UI_LABEL_MAP));
 [loop]for(uint i=0u;i<512u;i++){SurfaceInstance e=Instances[i];if(e.active<.5)continue;float2 uv=float2(lerp(mapRect.x+.025,mapRect.z-.025,e.uv.x),lerp(mapRect.w-.04,mapRect.y+.06,e.uv.y));float3 tint=e.type_id<.5?theme.accent:(e.type_id<1.5?lerp(theme.muted,theme.axisY,e.emissive):(e.type_id<2.5?float3(.82,.70,.32):float3(.78,.34,.86)));float sz=e.type_id<.5?3.2:(e.type_id<1.5?2.0:4.4);suiComposite(col,tint,suiDiscPx(c,uv,sz));if(e.type_id<.5)suiComposite(col,tint,suiLinePx(c,uv-float2(0,7)*c.invResolution,uv+float2(0,7)*c.invResolution,1));}
 float2 attract=attractor_field;float2 aperture=aperture_field;suiComposite(col,theme.accent,suiRingPx(c,attract,13,1.7));suiComposite(col,theme.axisY,suiRingPx(c,aperture,10,1.4));
 suiComposite(col,theme.accent,suiLinePx(c,float2(attract.x,mapRect.y),float2(attract.x,mapRect.w),.7)*.35);suiComposite(col,theme.axisY,suiLinePx(c,float2(mapRect.x,aperture.y),float2(mapRect.z,aperture.y),.7)*.35);
 OutputUAV[tid.xy]=float4(saturate(col),1);
}
