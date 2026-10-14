// Fixture canvas, the drawing: every live fixture in a front elevation and a plan, drawn where it is
// right now. Movers are rings filled with their live beam colour, strobes short tubes in their plate
// colour, pixel runs their real pieces. The selection is the only accent.
// Fixtures arrive as projected marks (marks.hlsl), and each pixel visits only its tile's marks
// (bins.hlsl). The type and chrome (group buttons, view titles, footer) are recorded by layout.hlsl
// and drawn over this by the shared UI kit (ui.hlsl).
#include "lighting.hlsli"
StructuredBuffer<float4> Sel:register(t2);
RWTexture2D<float4>OutputUAV:register(u0);
#include "../_shared/ui/il_core.hlsli"
#include "../_shared/ss_marks.hlsli"
StructuredBuffer<SsMark> Marks:register(t0);
StructuredBuffer<uint> Bins:register(t1);
#define SSM_MARKS_BUF Marks
#define SSM_BINS_BUF Bins
#define SSM_MARKS (2*(SS_BARS*SS_BAR_SEGS+SS_SLOTS))
#include "../_shared/ss_marks.hlsli"
void over(inout float3 c,float3 k,float a){c=lerp(c,k,saturate(a));}
float ink(float d,float w){return saturate(w*.5+.5-d);}
float seg(float2 p,float2 a,float2 b){float2 d=b-a;return length(p-a-d*saturate(dot(p-a,d)/max(dot(d,d),1e-5)));}
// The structure, quietly, under the fixtures: the trusses, the hoists, the deck and the booth in elevation and in plan,
// from the outline tools/ss_stage.py generates (ss_stage.hlsli SS_OUTLINE: view 0 front elevation, 1 plan).
float boxDist(uint v,float2 P,float2 R){float d=1e9;
 [loop]for(uint k=0;k<(uint)SS_OUTLINE_N;k++){float4 a=SS_OUTLINE[2*k],b=SS_OUTLINE[2*k+1];
  if((uint)round(b.w)==v)d=min(d,seg(P,toView(v,a.xyz,R),toView(v,b.xyz,R)));}
 return d;}
[numthreads(8,8,1)]void main(uint3 id:SV_DispatchThreadID){uint W,H;OutputUAV.GetDimensions(W,H);if(id.x>=W||id.y>=H)return;
 float2 P=id.xy+.5,R=float2(W,H);float3 c=IL_FIELD;float s=ilCtx(R).s;
 bool ok=_Data0_Count>=SS_SLOTS&&Sel[0].w==SEL_MAGIC;
 [loop]for(uint v=0;v<2;v++){float4 vr=viewRect(v,R);float d=ilSdBox(P,vr,IL_RADIUS*s);if(d>1)continue;
  over(c,IL_PANEL,ilFill(d));if(!ok||d>0)continue;float vs=viewScale(v,R);
  if(v==0)over(c,PT_RULE,ink(abs(P.y-toView(0,float3(0,0,0),R).y),1));
  else{float2 o=toView(1,float3(0,0,0),R);float2 g=abs(frac((P-o)/vs+.5)-.5)*vs;over(c,PT_GRID,ink(min(g.x,g.y),1));}
  over(c,PT_RULE*.75,ink(boxDist(v,P,R),1));
  ssmDrawTile(c,P,R,v+1);
  if(Sel[0].x>.5&&(uint)Sel[0].z==v&&length(Sel[1].xy-Sel[1].zw)>3){float4 dr=float4(min(Sel[1].xy,Sel[1].zw),max(Sel[1].xy,Sel[1].zw));
   over(c,IL_ACCENT,ilBorder(ilSdBox(P,dr,0),1));if(ilIn(P,dr))c=lerp(c,IL_ACCENT,.06);}}
 OutputUAV[id.xy]=float4(c,1);}
