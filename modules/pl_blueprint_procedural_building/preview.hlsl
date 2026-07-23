#include "types.hlsli"
#include "../_shared/ui/sui_v2.hlsli"
#include "_ui.generated.hlsli"
#include "../_shared/ui/sui_generated_text.hlsli"
StructuredBuffer<PNode> _Tex0 : register(t0);
StructuredBuffer<EditorState> _Tex1 : register(t1);
RWTexture2D<float4> OutputUAV : register(u0);

SuiTheme buildingTheme() {
    SuiTheme t = suiMonochromeTheme();
    t.background=float3(.006,.007,.009); t.panel=float3(.012,.013,.016); t.panelRaised=float3(.020,.021,.025);
    t.control=float3(.030,.032,.038); t.controlHover=float3(.050,.053,.060); t.controlDown=float3(.82,.60,.24);
    t.text=float3(.88,.90,.92); t.muted=float3(.42,.45,.49); t.border=float3(.12,.13,.15); t.accent=float3(.82,.60,.24);
    t.axisX=t.accent; t.axisY=float3(.58,.60,.63); t.axisZ=float3(.72,.74,.77); return t;
}
float box2(float2 p,float2 b){float2 q=abs(p)-b;return length(max(q,0))+min(max(q.x,q.y),0);}
float segment2(float2 p,float2 a,float2 b){float2 pa=p-a,ba=b-a;float h=saturate(dot(pa,ba)/max(dot(ba,ba),1e-6));return length(pa-ba*h);}
float inRect(float2 uv,float4 r){return step(r.x,uv.x)*step(r.y,uv.y)*step(uv.x,r.z)*step(uv.y,r.w);}
float rectEdge(float2 uv,float4 r){float2 cc=(r.xy+r.zw)*.5,b=(r.zw-r.xy)*.5;return 1-smoothstep(.0015,.0045,abs(box2(uv-cc,b)));}

[numthreads(8,8,1)]
void main(uint3 tid : SV_DispatchThreadID) {
    uint2 px=tid.xy; if(px.x>=(uint)_Resolution.x||px.y>=(uint)_Resolution.y)return;
    SuiContext c=suiContext(px,_Resolution.xy); SuiTheme theme=buildingTheme(); EditorState editor=_Tex1[0]; float3 col=theme.background;
    suiComposite(col,float3(.018,.019,.022),suiGridPx(c,24.0,.42));
    suiPanel(col,c,theme,float4(.012,.018,.988,.982),false);
    suiComposite(col,theme.panelRaised,suiFillRect(c,float4(.012,.018,.988,.092)));
    suiComposite(col,theme.accent,suiFillRect(c,float4(.012,.018,.016,.092)));
    suiComposite(col,theme.text,suiLabelText(c,float2(.032,.041),suiTextStyle(1.45,.15),UI_LABEL_TITLE));
    suiPanel(col,c,theme,PB_PLAN_RECT,true);
    if(pbInPlan(c.uv)){
        float2 world=pbPlanWorld(c.uv,editor.view_pan,editor.view_zoom); float2 grid=abs(frac(world)-.5);
        float gridLine=1-smoothstep(.47,.495,min(grid.x,grid.y)); col+=gridLine*float3(.038,.040,.045);
        col+=(1-smoothstep(.012,.028,abs(world.x)))*float3(.10,.105,.115);
        col+=(1-smoothstep(.012,.028,abs(world.y)))*float3(.10,.105,.115);
        float worldPerPixel=pbPlanSpan().y/max(_Resolution.y*(PB_PLAN_RECT.w-PB_PLAN_RECT.y)*editor.view_zoom,1.0);
        [loop]for(uint i=0u;i<PB_RECORD_COUNT;++i){PNode n=_Tex0[i];uint objectId=pbObjectForRecord(i);float2 local=pbRotate(world-n.position.xz,-n.yaw);float d=box2(local,max(float2(n.width,n.depth)*.5,.05));float fill=smoothstep(worldPerPixel*1.4,-worldPerPixel*.55,d),edge=1-smoothstep(worldPerPixel*.65,worldPerPixel*1.8,abs(d));bool selected=objectId>0u&&pbSelected(objectId);float shade=.20+.035*min(n.kind_id,7.0);float3 tint=selected?theme.accent:float3(shade,shade+.008,shade+.016);if(objectId==0u)tint=float3(.10,.105,.115);col=lerp(col,tint*(selected?1.1:.72),fill*(selected?.78:.58));col+=edge*tint*(selected?1.65:.92);}
    }
    suiComposite(col,theme.border,suiStrokeRect(c,PB_PLAN_RECT,1.0));

    float4 rects[6]={UI_RECT_MOVE,UI_RECT_ROTATE,UI_RECT_SNAP,UI_RECT_FIT,UI_RECT_RESET,UI_RECT_RESET_ALL};
    uint labelIds[6]={UI_LABEL_MOVE,UI_LABEL_ROTATE,UI_LABEL_SNAP,UI_LABEL_FIT,UI_LABEL_RESET,UI_LABEL_RESET_ALL};
    [unroll]for(uint b=0u;b<6u;++b){bool active=(b==0u&&editor.mode<.5)||(b==1u&&editor.mode>.5)||(b==2u&&editor.snap_enabled>.5);bool destructive=b>=4u;float mask=inRect(c.uv,rects[b]);float3 base=active?theme.accent:(destructive?float3(.10,.075,.07):theme.control);if(suiInteraction(b).hovered)base+=.045;col=lerp(col,base,mask*.95);col+=rectEdge(c.uv,rects[b])*(active?theme.accent:theme.border);suiComposite(col,active?float3(.025,.022,.016):theme.text,suiLabelText(c,rects[b].xy+float2(8,10)*c.invResolution,suiBodyStyle(),labelIds[b]));}

    uint selectedId=_ViewportSelectionMeta.y;
    if(selectedId>0u){float2 center=0;float count=0;[loop]for(uint i=0u;i<PB_RECORD_COUNT;++i)if(pbObjectForRecord(i)==selectedId){center+=_Tex0[i].position.xz;count+=1;}center/=max(count,1.0);float2 centerPx=pbWorldPlan(center,editor.view_pan,editor.view_zoom)*_Resolution.xy,pixel=(float2)px+.5;if(editor.mode<.5){float gx=1-smoothstep(.8,1.9,segment2(pixel,centerPx,centerPx+float2(54,0)));float gz=1-smoothstep(.8,1.9,segment2(pixel,centerPx,centerPx+float2(0,-54)));col+=gx*theme.accent+gz*float3(.72,.74,.77);}else{float ring=1-smoothstep(.8,1.9,abs(length(pixel-centerPx)-40));col+=ring*theme.accent;}}
    suiComposite(col,theme.muted,suiLabelText(c,float2(PB_PLAN_RECT.x,PB_PLAN_RECT.w)+float2(4,13)*c.invResolution,suiTextStyle(.68,0),UI_LABEL_PLAN));
    OutputUAV[px]=float4(saturate(col),1);
}
