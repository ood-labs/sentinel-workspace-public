#include "types.hlsli"
#include "../_shared/ui/sui_core.hlsli"
#include "../_shared/ui/sui_typography.hlsli"
#include "_ui.generated.hlsli"
#include "../_shared/ui/sui_generated_text.hlsli"

StructuredBuffer<PNode> PreviewNodes : register(t0);
StructuredBuffer<ArchitectureEditorState> EditorStateBuffer : register(t1);
RWTexture2D<float4> OutputUAV : register(u0);

float2 rotate2(float2 p, float a) { float s=sin(a),c=cos(a); return float2(c*p.x-s*p.y,s*p.x+c*p.y); }
float box2(float2 p,float2 b){float2 q=abs(p)-b;return length(max(q,0.0))+min(max(q.x,q.y),0.0);}
float segment2(float2 p,float2 a,float2 b){float2 pa=p-a,ba=b-a;float h=saturate(dot(pa,ba)/max(dot(ba,ba),0.00001));return length(pa-ba*h);}

float3 kindColor(float k) {
    if (k < 0.5) return float3(0.28,0.38,0.44);
    if (k < 3.5) return float3(0.25,0.68,0.82);
    if (k < 4.5) return float3(0.18,0.82,0.96);
    if (k < 5.5) return float3(0.96,0.48,0.20);
    if (k < 14.0) return float3(0.78,0.30,0.20);
    if (k < 18.0) return float3(0.88,0.34,0.58);
    return float3(0.96,0.72,0.24);
}

[numthreads(8,8,1)]
void main(uint3 tid : SV_DispatchThreadID) {
    uint2 px=tid.xy;if(px.x>=(uint)_Resolution.x||px.y>=(uint)_Resolution.y)return;
    float2 uv=((float2)px+0.5)/_Resolution.xy;
    ArchitectureEditorState editor=EditorStateBuffer[0];
    float3 col=lerp(float3(0.010,0.014,0.020),float3(0.022,0.026,0.035),uv.y);
    float toolbar=1.0-step(ARCH_PLAN_TOP,uv.y);
    col=lerp(col,float3(0.018,0.023,0.032),toolbar);
    col+=exp(-abs(uv.y-ARCH_PLAN_TOP)*900.0)*float3(0.12,0.22,0.30);

    if(uv.y>=ARCH_PLAN_TOP){
        float2 world=archPlanWorld(uv,editor.view_pan,editor.view_zoom);
        float2 gridUv=abs(frac(world)-0.5);
        float gridLine=1.0-smoothstep(0.48,0.496,min(gridUv.x,gridUv.y));
        col+=gridLine*float3(0.032,0.042,0.055);
        col+=(1.0-smoothstep(0.010,0.022,abs(world.x)))*float3(0.08,0.16,0.22);
        col+=(1.0-smoothstep(0.010,0.022,abs(world.y)))*float3(0.08,0.16,0.22);
        float worldPerPixel=archPlanSpan().y/max(_Resolution.y*(1.0-ARCH_PLAN_TOP)*editor.view_zoom,1.0);
        [loop]for(uint i=0u;i<13u;++i){
            PNode n=PreviewNodes[i];float2 center=n.position.xz;
            float2 local=rotate2(world-center,-n.yaw);
            float d=box2(local,max(float2(n.width,n.depth)*0.5,0.035));
            float edge=1.0-smoothstep(worldPerPixel*0.65,worldPerPixel*1.75,abs(d));
            float fill=smoothstep(worldPerPixel*1.3,-worldPerPixel*0.55,d);
            float3 tint=kindColor(n.kind_id);float shellOnly=n.kind_id<3.5?1.0:0.0;
            col=lerp(col,tint*0.27,fill*(shellOnly*0.08+(1.0-shellOnly)*0.32));
            col+=edge*tint*0.76;
            float centerDot=1.0-smoothstep(worldPerPixel*1.0,worldPerPixel*2.0,length(world-center));
            float2 arrowEnd=center+normalize(n.dir+1e-5)*0.34;
            float arrow=1.0-smoothstep(worldPerPixel*0.65,worldPerPixel*1.75,segment2(world,center,arrowEnd));
            col+=centerDot*0.72+arrow*tint*0.70;
        }
    }

    SuiContext c=suiContext(px,_Resolution.xy);
    suiComposite(col,float3(0.78,0.91,1.0),suiLabelText(c,float2(0.022,0.026),suiBodyStyle(),UI_LABEL_TITLE));
    float2 legend=float2(0.022,0.108);uint labels[5]={UI_LABEL_SHELL,UI_LABEL_ENTRY,UI_LABEL_FLOOR,UI_LABEL_ART,UI_LABEL_LIGHTS};
    float3 colors[5]={float3(0.25,0.68,0.82),float3(0.96,0.48,0.20),float3(0.78,0.30,0.20),float3(0.88,0.34,0.58),float3(0.96,0.72,0.24)};
    [unroll]for(uint i=0u;i<5u;++i){float2 origin=legend+float2(i*0.18,0);float swatch=step(origin.x,uv.x)*step(origin.y,uv.y)*step(uv.x,origin.x+0.012)*step(uv.y,origin.y+0.026);col=lerp(col,colors[i],swatch);suiComposite(col,float3(0.68,0.75,0.84),suiLabelText(c,origin+float2(0.018,0.002),suiBodyStyle(),labels[i]));}
    if(_Resolution.x>760.0)suiComposite(col,float3(0.42,0.50,0.60),suiLabelText(c,float2(0.63,0.026),suiBodyStyle(),UI_LABEL_NAV));
    OutputUAV[px]=float4(saturate(col),1.0);
}
