#include "../_shared/ui/sui_v2.hlsli"
#include "_ui.generated.hlsli"
#include "../_shared/ui/sui_generated_text.hlsli"
#include "types.hlsli"

StructuredBuffer<FacadeElement> Facade:register(t1);StructuredBuffer<FacadeControlState> Controls:register(t2); RWTexture2D<float4> OutputUAV:register(u0);

SuiTheme facadeTheme(){SuiTheme t=suiMonochromeTheme();t.background=float3(.006,.007,.009);t.panel=float3(.012,.013,.016);t.panelRaised=float3(.020,.021,.025);t.control=float3(.030,.032,.038);t.controlHover=float3(.050,.053,.060);t.controlDown=float3(.82,.60,.24);t.text=float3(.88,.90,.92);t.muted=float3(.42,.45,.49);t.border=float3(.12,.13,.15);t.accent=float3(.82,.60,.24);t.axisY=float3(.66,.68,.71);return t;}
float sdBoxPx(float2 p,float2 c,float2 b){float2 q=abs(p-c)-b;return length(max(q,0))+min(max(q.x,q.y),0);}

[numthreads(8,8,1)]
void main(uint3 id:SV_DispatchThreadID){
 if(id.x>=(uint)_Resolution.x||id.y>=(uint)_Resolution.y)return;SuiContext c=suiContext(id.xy,_Resolution.xy);SuiTheme theme=facadeTheme();float3 col=theme.background;
 suiComposite(col,float3(.018,.019,.022),suiGridPx(c,26,.42));suiPanel(col,c,theme,float4(.012,.018,.988,.982),false);suiComposite(col,theme.panelRaised,suiFillRect(c,float4(.012,.018,.988,.092)));suiComposite(col,theme.accent,suiFillRect(c,float4(.012,.018,.016,.092)));
 suiComposite(col,theme.text,suiLabelText(c,float2(.032,.041),suiTextStyle(1.45,.15),UI_LABEL_TITLE));
 float4 elev=FC_EDIT_RECT;suiPanel(col,c,theme,elev,true);float2 px=(float2)id.xy+.5;float2 minPx=elev.xy*_Resolution.xy,maxPx=elev.zw*_Resolution.xy;
 if(all(px>=minPx)&&all(px<=maxPx)){float2 local=(c.uv-elev.xy)/max(elev.zw-elev.xy,.0001);float fine=(1-smoothstep(.47,.495,min(abs(frac(local.x*18)-.5),abs(frac(local.y*12)-.5))));col+=fine*float3(.032,.034,.038);float2 shellC=float2(lerp(elev.x,elev.z,.5),lerp(elev.y,elev.w,.5))*_Resolution.xy;float2 shellH=float2((elev.z-elev.x)*.46,(elev.w-elev.y)*.40)*_Resolution.xy;float shell=sdBoxPx(px,shellC,shellH);col=lerp(col,float3(.055,.057,.062),smoothstep(2,-2,shell));col+=(1-smoothstep(.7,2,abs(shell)))*theme.border;
  float3 buildingBase=_Data0_Count>=3?float3(_Data0[2].position[0],_Data0[2].position[1],_Data0[2].position[2]):0;float buildingW=_Data0_Count>=3?max(_Data0[2].width,.001):13.0,buildingH=_Data0_Count>=3?max(_Data0[2].height,.001):14.0;float2 gridSize=FC_GRID_RECT_LOCAL.zw-FC_GRID_RECT_LOCAL.xy;
  [loop]for(uint j=0u;j<160u;j++){FacadeElement e=Facade[j];if(e.active<.5||abs(e.yaw)>.5)continue;float2 fitted=float2(lerp(FC_GRID_RECT_LOCAL.x,FC_GRID_RECT_LOCAL.z,.5+(e.position.x-buildingBase.x)/buildingW),lerp(FC_GRID_RECT_LOCAL.w,FC_GRID_RECT_LOCAL.y,(e.position.y-buildingBase.y)/buildingH));float2 cc=lerp(elev.xy,elev.zw,fitted)*_Resolution.xy;float2 hs=float2(e.size.x/buildingW*gridSize.x,e.size.y/buildingH*gridSize.y)*(elev.zw-elev.xy)*_Resolution.xy*.5;float d=sdBoxPx(px,cc,max(hs,1.0));float fill=smoothstep(1.8,-1,d),edge=1-smoothstep(.5,1.5,abs(d));float3 tint=lerp(float3(.34,.35,.37),theme.accent,e.emissive*.65);col=lerp(col,tint*.68,fill*.92);col+=edge*tint;}
 }
 float2 rhythmHandle=fcCanvasFromLocal(Controls[0].position);float3 helperBase=_Data0_Count>=3?float3(_Data0[2].position[0],_Data0[2].position[1],_Data0[2].position[2]):0;float helperW=_Data0_Count>=3?_Data0[2].width:13.0,helperH=_Data0_Count>=3?_Data0[2].height:14.0;float2 featureHandle=fcFeatureCanvas(Controls[1].position,helperBase,helperW,helperH);float3 rhythmColor=fcSelected(1)?theme.accent:theme.axisY,featureColor=fcSelected(2)?theme.accent:theme.axisY;
 suiComposite(col,theme.border,suiStrokeRect(c,elev,1));suiComposite(col,rhythmColor,suiRingPx(c,rhythmHandle,fcSelected(1)?10:7,1.6));suiComposite(col,featureColor,suiRingPx(c,featureHandle,fcSelected(2)?10:7,1.6));
 float rhythmLabelX=rhythmHandle.x>.86?-58.0:12.0,featureLabelX=featureHandle.x>.86?-58.0:12.0;
 suiComposite(col,rhythmColor,suiLabelText(c,rhythmHandle+float2(rhythmLabelX,-16)*c.invResolution,suiTextStyle(.72,0),UI_LABEL_RHYTHM));suiComposite(col,featureColor,suiLabelText(c,featureHandle+float2(featureLabelX,12)*c.invResolution,suiTextStyle(.72,0),UI_LABEL_FEATURE));
 suiPanel(col,c,theme,UI_RECT_RESET,false);suiPanel(col,c,theme,UI_RECT_RESET_ALL,false);suiComposite(col,theme.text,suiLabelText(c,UI_RECT_RESET.xy+float2(8,10)*c.invResolution,suiBodyStyle(),UI_LABEL_RESET));suiComposite(col,theme.text,suiLabelText(c,UI_RECT_RESET_ALL.xy+float2(8,10)*c.invResolution,suiBodyStyle(),UI_LABEL_RESET_ALL));
 suiComposite(col,theme.muted,suiLabelText(c,float2(elev.x,elev.w)+float2(4,13)*c.invResolution,suiTextStyle(.72,0),UI_LABEL_ELEVATION));OutputUAV[id.xy]=float4(saturate(col),1);
}
