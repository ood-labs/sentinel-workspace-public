// Draughtsman's plan over a radial section, the drawing. Monochrome instrument palette; hue only for
// the selection (accent), a broken leg (alarm) and the three fixture types (identity). Every anatomy
// stroke arrives as a precomputed mark (marks.hlsl), and each pixel visits only its tile's marks.
// The type (title, view captions, readouts, footer) is recorded by layout.hlsl and drawn over this by
// the shared UI kit (ui.hlsl).
StructuredBuffer<float4> E:register(t0);
RWTexture2D<float4> OutputUAV:register(u0);
#include "../_shared/ui/il_core.hlsli"
#include "layout.hlsli"
#include "../_shared/ph_marks.hlsli"
#include "plan_marks.hlsli"
StructuredBuffer<PhMark> Marks:register(t1);
StructuredBuffer<uint> Bins:register(t2);
#define PHM_MARKS_BUF Marks
#define PHM_BINS_BUF Bins
#define PHM_MARKS PM_MARKS
#include "../_shared/ph_marks.hlsli"

float ink(float d,float w){return saturate(w*.5+.5-d);}
float dashed(float2 p,float2 a,float2 b,float w,float period){float2 d=b-a;float t=dot(p-a,d)/max(dot(d,d),1e-5);
 return ink(segDist(p,a,b),w)*step(frac(t*length(d)/period),.55);}
void over(inout float3 c,float3 k,float a){c=lerp(c,k,saturate(a));}
// A view's plate: the panel colour inside its rounded rect (the kit draws the edge and caption).
bool plate(inout float3 c,float2 P,float4 r,float s){float d=ilSdBox(P,r,IL_RADIUS*s);over(c,IL_PANEL,ilFill(d));return d<=0;}

[numthreads(8,8,1)]void main(uint3 id:SV_DispatchThreadID){
 uint W,H;OutputUAV.GetDimensions(W,H);if(id.x>=W||id.y>=H)return;
 float2 P=id.xy+.5,RS=float2(W,H);float s=ilCtx(RS).s;
 float3 c=IL_FIELD;float4 pr=planRect(),sr=sectRect();
 // ---------------- PLAN (top view, audience down) ----------------
 if(plate(c,P,pr,s)){
  float ps=planScale();float2 q=(P-planCenter())/ps;
  float2 g=abs(frac(q+.5)-.5)*ps,G=abs(frac(q/5+.5)-.5)*5*ps;
  c+=PT_GRID*ink(min(g.x,g.y),1)*.55+PT_GRID*ink(min(G.x,G.y),1)*.9;
  // audience edge
  float lip=Marks[PM_REC+2].fill.x;float2 la=planPx(float3(-20,0,lip)),lb=planPx(float3(20,0,lip));
  over(c,PT_RULE,dashed(P,la,lb,1,9));
  // riser, booth, plate, collar, capsid, fixtures (identity), legs: marks
  phmDrawTile(c,P,RS,1);
 }
 // ---------------- SECTION through the selected leg ----------------
 if(plate(c,P,sr,s)){
  float ss=sectScale();float2 o=sectOrigin();float2 q=(P-o)/ss;q.y=-q.y;
  float2 g=abs(frac(q+.5)-.5)*ss,G=abs(frac(q/5+.5)-.5)*5*ss;
  c+=PT_GRID*ink(min(g.x,g.y),1)*.55+PT_GRID*ink(min(G.x,G.y),1)*.9;
  // floor and the audience head plane, 2 m up
  over(c,PT_MID,ink(abs(P.y-o.y),1.6)*step(sr.x,P.x));
  over(c,PT_DIM,dashed(P,float2(sr.x,o.y-2*ss),float2(sr.z,o.y-2*ss),1,7));
  // riser, DJ, booth, plate, sheath, collar, capsid, the two legs in this plane: marks
  phmDrawTile(c,P,RS,2);
 }
 OutputUAV[id.xy]=float4(c,1);
}
