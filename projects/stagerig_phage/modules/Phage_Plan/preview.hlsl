// Draughtsman's plan over a radial section. Monochrome instrument palette; hue only for the
// selection (accent), a broken leg (alarm) and the three fixture types (identity). Every anatomy
// stroke arrives as a precomputed mark (marks.hlsl), and each pixel visits only its tile's marks.
StructuredBuffer<float4> E:register(t0);
RWTexture2D<float4> OutputUAV:register(u0);
#include "../_shared/plan_theme.hlsli"
#include "../_shared/ui/sui3_core.hlsli"
#include "../_shared/ui/sui3_text.hlsli"
#include "labels.hlsli"
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

[numthreads(8,8,1)]void main(uint3 id:SV_DispatchThreadID){
 uint W,H;OutputUAV.GetDimensions(W,H);if(id.x>=W||id.y>=H)return;
 float2 P=id.xy+.5,RS=float2(W,H);
 int sel=(int)E[0].x-1;bool sym=E[3].x>.5;
 float3 c=PT_FIELD;float4 pr=planRect(),sr=sectRect();
 // ---------------- header / footer ----------------
 if(P.y<PL_HEAD){
  over(c,PT_INK,phLabel(P,float2(14,8),2,0));
  float x=W-14-phLabelWidth(sym?5:6,1)-4;over(c,sym?PT_INK:PT_DIM,phLabel(P,float2(x,14),1,sym?5:6));
  x-=phLabelWidth(14+(uint)stance,1)+22;over(c,PT_INK,phLabel(P,float2(x,14),1,14+(uint)stance));
  x-=phLabelWidth(13,1)+8;over(c,PT_DIM,phLabel(P,float2(x,14),1,13));
  c+=PT_RULE*sui3HairAt(P.y,PL_HEAD-4)*.6;
 }
 if(P.y>H-PL_FOOT){
  over(c,PT_DIM,phLabel(P,float2(14,H-PL_FOOT+9),1,4));
  float x=W-14;float4 counts=Marks[PM_REC].fill;
  if(P.x>W-360){[loop]for(int t=2;t>=0;t--){x-=sui3TextWidth(3,1);over(c,ptId(t),sui3Digits(P,float2(x,H-PL_FOOT+9),1,(int)counts[t],3));
    x-=phLabelWidth(18+(uint)t,1)+6;over(c,PT_DIM,phLabel(P,float2(x,H-PL_FOOT+9),1,18+(uint)t));x-=18;}}
 }
 // ---------------- PLAN (top view, audience down) ----------------
 if(inRect(P,pr)){
  float s=planScale();float2 q=(P-planCenter())/s;
  float2 g=abs(frac(q+.5)-.5)*s,G=abs(frac(q/5+.5)-.5)*5*s;
  c+=PT_GRID*ink(min(g.x,g.y),1)*.55+PT_GRID*ink(min(G.x,G.y),1)*.9;
  c+=PT_RULE*sui3Frame(P,sui3SnapRect(pr))*.8;
  over(c,PT_DIM,phLabel(P,pr.xy+float2(8,6),1,1));
  // audience edge and label
  float lip=Marks[PM_REC+2].fill.x;float2 la=planPx(float3(-20,0,lip)),lb=planPx(float3(20,0,lip));
  over(c,PT_RULE,dashed(P,la,lb,1,9));
  over(c,PT_DIM,phLabel(P,planPx(float3(0,0,lip+17))-float2(phLabelWidth(3,1)*.5,0),1,3));
  // riser, booth, plate, collar, capsid, fixtures (identity), legs: marks
  phmDrawTile(c,P,RS,1);
  over(c,PT_DIM,phLabel(P,planPx(float3(0,0,.2))-float2(7,5),1,25));
 }
 // ---------------- SECTION through the selected leg ----------------
 if(inRect(P,sr)){
  uint li=(uint)Marks[PM_REC+2].fill.y;float s=sectScale();
  float2 o=sectOrigin();float2 q=(P-o)/s;q.y=-q.y;
  float2 g=abs(frac(q+.5)-.5)*s,G=abs(frac(q/5+.5)-.5)*5*s;
  c+=PT_GRID*ink(min(g.x,g.y),1)*.55+PT_GRID*ink(min(G.x,G.y),1)*.9;
  c+=PT_RULE*sui3Frame(P,sui3SnapRect(sr))*.8;
  over(c,PT_DIM,phLabel(P,sr.xy+float2(8,6),1,2));
  over(c,sel>=0?PT_ACCENT:PT_INK,sui3Digits(P,sr.xy+float2(8+phLabelWidth(2,1)+7,6),1,(int)li+1,1));
  // floor and audience head plane
  over(c,PT_MID,ink(abs(P.y-o.y),1.6)*step(sr.x,P.x));
  over(c,PT_DIM,dashed(P,float2(sr.x,o.y-2*s),float2(sr.z,o.y-2*s),1,7));
  over(c,PT_DIM,phLabel(P,float2(sr.z-phLabelWidth(22,1)-8,o.y-2*s-14),1,22));
  // riser, DJ, booth, plate, sheath, collar, capsid, the two legs in this plane: marks
  phmDrawTile(c,P,RS,2);
  // readouts: upper / lower length, reach
  float4 L=Marks[PM_REC+1].fill;bool badR=L.w>.5;
  float2 ra=sr.xy+float2(8,22);float x=ra.x;
  over(c,PT_DIM,phLabel(P,float2(x,ra.y),1,7));x+=phLabelWidth(7,1)+6;over(c,PT_INK,sui3Fixed(P,float2(x,ra.y),1,L.x,1));x+=sui3FixedWidth(1,1)+18;
  over(c,PT_DIM,phLabel(P,float2(x,ra.y),1,8));x+=phLabelWidth(8,1)+6;over(c,PT_INK,sui3Fixed(P,float2(x,ra.y),1,L.y,1));x+=sui3FixedWidth(1,1)+18;
  over(c,PT_DIM,phLabel(P,float2(x,ra.y),1,9));x+=phLabelWidth(9,1)+6;
  over(c,badR?PT_ALARM:PT_INK,sui3Digits(P,float2(x,ra.y),1,(int)L.z,3));x+=sui3TextWidth(3,1)+2;over(c,PT_DIM,phLabel(P,float2(x,ra.y),1,24));
  if(badR)over(c,PT_ALARM,phLabel(P,float2(x+22,ra.y),1,10));
 }
 OutputUAV[id.xy]=float4(c,1);
}
