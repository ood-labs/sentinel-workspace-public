#include "types.hlsli"
#include "../_shared/ui/sui_v2.hlsli"
#include "_ui.generated.hlsli"
#include "../_shared/ui/sui_generated_text.hlsli"
StructuredBuffer<PNode> _Tex0 : register(t0); StructuredBuffer<EditorState> _Tex1 : register(t1); RWTexture2D<float4> OutputUAV : register(u0);

float box2(float2 p,float2 b){float2 q=abs(p)-b;return length(max(q,0))+min(max(q.x,q.y),0);}
float segment2(float2 p,float2 a,float2 b){float2 pa=p-a,ba=b-a;float h=saturate(dot(pa,ba)/max(dot(ba,ba),1e-6));return length(pa-ba*h);}
float inRect(float2 uv,float4 r){return step(r.x,uv.x)*step(r.y,uv.y)*step(uv.x,r.z)*step(uv.y,r.w);}
float rectEdge(float2 uv,float4 r){float2 c=(r.xy+r.zw)*0.5,b=(r.zw-r.xy)*0.5;return 1.0-smoothstep(0.0015,0.0045,abs(box2(uv-c,b)));}

[numthreads(8,8,1)]
void main(uint3 tid:SV_DispatchThreadID){uint2 px=tid.xy;if(px.x>=(uint)_Resolution.x||px.y>=(uint)_Resolution.y)return;float2 uv=((float2)px+0.5)/_Resolution.xy;EditorState editor=_Tex1[0];
    float3 col=lerp(float3(0.014,0.019,0.027),float3(0.034,0.026,0.043),uv.y);
    float toolbar=1.0-step(LR_PLAN_TOP,uv.y);col=lerp(col,float3(0.025,0.031,0.044),toolbar);col+=exp(-abs(uv.y-LR_PLAN_TOP)*900.0)*float3(0.16,0.24,0.34);
    if(uv.y>=LR_PLAN_TOP){float2 world=lrPlanWorld(uv,editor.view_pan,editor.view_zoom);float2 grid=abs(frac(world)-0.5);float gridLine=1.0-smoothstep(0.47,0.495,min(grid.x,grid.y));col+=gridLine*float3(0.045,0.052,0.069);col+=(1.0-smoothstep(0.012,0.025,abs(world.x)))*float3(0.12,0.19,0.26);col+=(1.0-smoothstep(0.012,0.025,abs(world.y)))*float3(0.12,0.19,0.26);
        float worldPerPixel=lrPlanSpan().y/max(_Resolution.y*(1.0-LR_PLAN_TOP)*editor.view_zoom,1.0);[loop]for(uint i=0u;i<LR_RECORD_COUNT;++i){PNode n=_Tex0[i];uint objectId=lrObjectForRecord(i);float2 local=lrRotate(world-n.position.xz,-n.yaw);float d=box2(local,max(float2(n.width,n.depth)*0.5,0.05));float fill=smoothstep(worldPerPixel*1.3,-worldPerPixel*0.55,d),edge=1.0-smoothstep(worldPerPixel*0.65,worldPerPixel*1.75,abs(d));float3 tint=lrObjectColor(objectId);bool selected=lrSelected(objectId);if(selected)tint=float3(1.0,0.30,0.72);col=lerp(col,tint*(selected?0.52:0.30),fill*(selected?0.68:0.46));col+=edge*tint*(selected?1.50:0.78);float2 dir=normalize(n.dir+1e-5);float arrow=1.0-smoothstep(worldPerPixel*0.65,worldPerPixel*1.75,segment2(world,n.position.xz,n.position.xz+dir*0.42));col+=arrow*tint*0.68;}
    }
    float4 rects[6]={UI_RECT_MOVE,UI_RECT_ROTATE,UI_RECT_SNAP,UI_RECT_FIT,UI_RECT_RESET,UI_RECT_RESET_ALL};[unroll]for(uint i=0u;i<6u;++i){bool active=(i==0u&&editor.mode<0.5)||(i==1u&&editor.mode>0.5)||(i==2u&&editor.snap_enabled>0.5);bool destructive=i>=4u;bool hover=suiInteraction(i).hovered;float mask=inRect(uv,rects[i]);float3 base=active?float3(0.12,0.48,0.66):(destructive?float3(0.30,0.12,0.22):float3(0.08,0.11,0.16));if(hover)base+=float3(0.08,0.08,0.10);col=lerp(col,base,mask*0.92);col+=rectEdge(uv,rects[i])*(active?float3(0.28,0.90,1.0):float3(0.22,0.32,0.44));}
    SuiContext c=suiContext(px,_Resolution.xy);float4 labelRects[6]={UI_RECT_MOVE,UI_RECT_ROTATE,UI_RECT_SNAP,UI_RECT_FIT,UI_RECT_RESET,UI_RECT_RESET_ALL};uint labelIds[6]={UI_LABEL_MOVE,UI_LABEL_ROTATE,UI_LABEL_SNAP,UI_LABEL_FIT,UI_LABEL_RESET,UI_LABEL_RESET_ALL};[unroll]for(uint labelIndex=0u;labelIndex<6u;++labelIndex){bool activeLabel=(labelIndex==0u&&editor.mode<0.5)||(labelIndex==1u&&editor.mode>0.5)||(labelIndex==2u&&editor.snap_enabled>0.5);suiComposite(col,activeLabel?float3(0.02,0.04,0.06):float3(0.88,0.93,1.0),suiLabelText(c,labelRects[labelIndex].xy+float2(10.0,11.0)*c.invResolution,suiBodyStyle(),labelIds[labelIndex]));}
    uint selectedId=_ViewportSelectionMeta.y;if(selectedId>0u){float2 center=0.0;float count=0.0;[loop]for(uint i=0u;i<LR_RECORD_COUNT;++i)if(lrObjectForRecord(i)==selectedId){center+=_Tex0[i].position.xz;count+=1.0;}center/=max(count,1.0);float2 cpx=lrWorldPlan(center,editor.view_pan,editor.view_zoom)*_Resolution.xy,ppx=uv*_Resolution.xy;if(editor.mode<0.5){float gx=1.0-smoothstep(0.75,1.8,segment2(ppx,cpx,cpx+float2(58,0)));float gz=1.0-smoothstep(0.75,1.8,segment2(ppx,cpx,cpx+float2(0,-58)));col+=gx*float3(1.0,0.20,0.25)+gz*float3(0.20,0.85,1.0);}else{float ringGizmo=1.0-smoothstep(0.75,1.8,abs(length(ppx-cpx)-42.0));col+=ringGizmo*float3(1.0,0.34,0.72);}}
    OutputUAV[px]=float4(saturate(col),1);
}
