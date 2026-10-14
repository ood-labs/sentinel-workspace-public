// Motion-control monitor, the drawing: live plan and live front elevation, the rest pose ghosted
// underneath. Legs and members arrive as projected marks (marks.hlsl) drawn through tile bins. The
// type and the axis meters (one row per axis: position, target, velocity) are recorded by layout.hlsl
// and drawn over this by the shared UI kit (ui.hlsl).
StructuredBuffer<float4> DesignIn:register(t0);
StructuredBuffer<float4> A:register(t1);
float4 phD(uint i){return DesignIn[i];}
#include "../_shared/phage_anatomy.hlsli"
#include "kin_common.hlsli"
StructuredBuffer<PhMember> Mem:register(t2);
RWTexture2D<float4> OutputUAV:register(u0);
#include "../_shared/ui/il_core.hlsli"
#include "../_shared/ph_marks.hlsli"
#include "kin_view.hlsli"
StructuredBuffer<PhMark> Marks:register(t3);
StructuredBuffer<uint> Bins:register(t4);
#define PHM_MARKS_BUF Marks
#define PHM_BINS_BUF Bins
#define PHM_MARKS KM_MARKS
#include "../_shared/ph_marks.hlsli"
float ink(float d,float w){return saturate(w*.5+.5-d);}
void over(inout float3 c,float3 k,float a){c=lerp(c,k,saturate(a));}
// A view's plate: the panel colour inside its rounded rect (the kit draws the edge and caption).
bool plate(inout float3 c,float2 P,float4 r,float s){float d=ilSdBox(P,r,IL_RADIUS*s);over(c,IL_PANEL,ilFill(d));return d<=0;}

[numthreads(8,8,1)]void main(uint3 id:SV_DispatchThreadID){
 uint W,H;OutputUAV.GetDimensions(W,H);if(id.x>=W||id.y>=H)return;float2 P=id.xy+.5;float3 c=IL_FIELD;
 bool ok=_Data0_Count>=17&&DesignIn[16].w==260929;
 if(!ok){OutputUAV[id.xy]=float4(c,1);return;}
 float2 RS=float2(W,H);float s=ilCtx(RS).s;float4 pr=kvPlanRect(RS),er=kvElevRect(RS);
 if(plate(c,P,pr,s)){
  float ps=kvPlanScale(RS);float2 o=kvPlanOrigin(RS);
  float2 q=(P-o)/ps,G=abs(frac(q/5+.5)-.5)*5*ps;c+=PT_GRID*ink(min(G.x,G.y),1)*.8;
  phmDrawTile(c,P,RS,1);
 }
 if(plate(c,P,er,s)){
  float es=kvElevScale(RS);float2 o=kvElevOrigin(RS);
  over(c,PT_MID,ink(abs(P.y-o.y),1.4));
  float2 q=(P-o)/es,G=abs(frac(q/5+.5)-.5)*5*es;c+=PT_GRID*ink(min(G.x,G.y),1)*.8;
  phmDrawTile(c,P,RS,2);
 }
 OutputUAV[id.xy]=float4(c,1);
}
