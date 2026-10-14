// LR_Lighting / preview - the plan drawing: the live Architecture (mid grey) and Furnishings (dim
// grey) records over a 1 m grid on the plan plate, and the six emitted light records as rings in
// their own colour (cool daylight and fill, warm lamps; through ptSampleColour), brighter with
// intensity, with a ray for the directional ones. The type, the control pane, the inspector and
// the legend are recorded by layout.hlsl and drawn over this by the shared UI kit (ui.hlsl).
#include "../_shared/ui/il_core.hlsli"
#include "desk.hlsli"

RWTexture2D<float4> OutputUAV : register(u0);
StructuredBuffer<LightRecord> Lights : register(t0);

float box2(float2 p, float2 b) {
    float2 q = abs(p) - b;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0);
}
float2 rotate2(float2 p, float a) {
    float s=sin(a), c=cos(a); return float2(c*p.x-s*p.y,s*p.x+c*p.y);
}
float pnodeEdge(float2 world,float2 center,float yaw,float width,float depth,float wpp) {
    float d=box2(rotate2(world-center,-yaw),max(float2(width,depth)*0.5,0.025));
    return 1.0-smoothstep(wpp*0.55,wpp*1.45,abs(d));
}

[numthreads(8,8,1)]
void main(uint3 tid:SV_DispatchThreadID) {
    if(tid.x>=(uint)_Resolution.x||tid.y>=(uint)_Resolution.y)return;
    float2 R=_Resolution.xy;
    float2 P=(float2)tid.xy+0.5;
    float s=ldUiScale(R);
    float3 col=IL_FIELD;

    float4 plan=ldPlan(R);
    float dp=ilSdBox(P,plan,IL_RADIUS*s);
    if(dp<1.0){
        ilOver(col,IL_PANEL,ilFill(dp));
        if(dp<=0.0){
            float2 world=ldWorld(P,plan);
            float wpp=1.0/ldPpw(plan);
            float2 grid=abs(frac(world+0.5)-0.5);
            ilOver(col,IL_GRID,1.0-smoothstep(wpp*0.55,wpp*1.35,min(grid.x,grid.y)));
            ilOver(col,IL_RULE,(1.0-smoothstep(wpp*0.55,wpp*1.35,abs(world.x)))+
                               (1.0-smoothstep(wpp*0.55,wpp*1.35,abs(world.y))));

            [loop]for(uint i=0u;i<min(_Data0_Count,13u);++i){
                float e=pnodeEdge(world,float2(_Data0[i].position[0],_Data0[i].position[2]),
                                  _Data0[i].yaw,_Data0[i].width,_Data0[i].depth,wpp);
                ilOver(col,IL_MID,e*0.85);
            }
            [loop]for(uint j=0u;j<min(_Data1_Count,23u);++j){
                float e=pnodeEdge(world,float2(_Data1[j].position[0],_Data1[j].position[2]),
                                  _Data1[j].yaw,_Data1[j].width,_Data1[j].depth,wpp);
                ilOver(col,IL_DIM,e*0.9);
            }
            [loop]for(uint q=0u;q<6u;++q){
                LightRecord L=Lights[q]; if(L.enabled<0.5)continue;
                float2 center=L.position.xz;
                bool practical=ldPractical(L.type_id);
                float d=length(world-center);
                float ring=1.0-smoothstep(wpp*0.55,wpp*1.55,abs(d-ldRing(L.type_id)));
                float core=1.0-smoothstep(wpp*1.0,wpp*3.2,d);
                ilOver(col,ptSampleColour(L.color),(ring*0.78+core)*saturate(0.35+L.intensity*0.22));
                float2 dir=normalize(L.direction.xz+1e-4);
                float ray=1.0-smoothstep(wpp*0.55,wpp*1.55,ilSdSeg(world,center,center+dir*0.62));
                if(!practical)ilOver(col,IL_MID,ray*0.60);
            }
        }
    }
    OutputUAV[tid.xy]=float4(saturate(col),1.0);
}
