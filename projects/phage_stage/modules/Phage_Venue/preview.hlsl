// Arena plan over a long section, sharing one z axis (stage left, audience right). The plan shows
// seating, columns, the crowd parted round the feet and the live pixel bars in their own colour. The
// section shows the phage at rest against the roof steel, the height its kinetics can reach, and the
// clearance that leaves. Plan: page up = +x (house right). Section: seen from house left. Boxes,
// silhouette and emitters arrive as marks (marks.hlsl) drawn through tile bins; counts as a record.
#include "../_shared/phage_venue.hlsli"
struct Architecture{float4 center,extent,surface,rotation;};StructuredBuffer<Architecture>A:register(t0);
struct Person{float4 p;float4 look;};StructuredBuffer<Person> C:register(t1);
struct Emitter{float4 a,b,radiance;};StructuredBuffer<Emitter> E:register(t2);
StructuredBuffer<float4> Sil:register(t3);
RWTexture2D<float4>OutputUAV:register(u0);
#include "../_shared/plan_theme.hlsli"
#include "../_shared/ui/sui3_core.hlsli"
#include "../_shared/ui/sui3_text.hlsli"
#include "labels.hlsli"
#include "../_shared/ph_marks.hlsli"
#include "venue_view.hlsli"
StructuredBuffer<PhMark> Marks:register(t4);
StructuredBuffer<uint> Bins:register(t5);
#define PHM_MARKS_BUF Marks
#define PHM_BINS_BUF Bins
#define PHM_MARKS VM_MARKS
#include "../_shared/ph_marks.hlsli"
void over(inout float3 c,float3 k,float a){c=lerp(c,k,saturate(a));}
float ink(float d,float w){return saturate(w*.5+.5-d);}
// Text is queued and drawn by one loop at the end: one inlined copy of each glyph routine keeps
// the compile fast (every call site of phLabel / sui3Fixed would otherwise be inlined separately).
#include "../_shared/ph_textq.hlsli"
float steelY(){return floor_level+hall_height-2.69;}
[numthreads(8,8,1)]void main(uint3 id:SV_DispatchThreadID){uint W,H;OutputUAV.GetDimensions(W,H);if(id.x>=W||id.y>=H)return;
 float2 P=id.xy+.5;float3 c=PT_FIELD;gTN=0;gTP=P;
 float2 RS=float2(W,H);venueView(RS);float planBottom=gPB;
 bool design=Sil[0].w==260932;float z=(P.x-20)/gS-gHL;
 if(P.y<34)txt(float2(14,9),2,0,PT_INK);
 else if(P.x<W-SIDE){
  if(P.y<planBottom+8){
   // ---- plan
   float x=gHW-(P.y-46)/gS;float2 q=float2(x,z);
   if(abs(x)<=gHW&&abs(z)<=gHL){
    phmDrawTile(c,P,RS,1);
    int gx=(int)round((x+29.4)/1.05),gz=(int)round((z+16)/1.05);
    [loop]for(int dz=-1;dz<=1;dz++)[loop]for(int dx=-1;dx<=1;dx++){int cx=gx+dx,cz=gz+dz;if(cx<0||cx>=56||cz<0||cz>=55)continue;Person p=C[cz*56+cx];if(p.p.w<.1)continue;
     float d=length(q-p.p.xz)*gS;if(d<2.4)over(c,p.look.y+p.look.z>.1?PT_MID:PT_DIM,2.4-d);}
   }
   phmDrawTile(c,P,RS,2);
   over(c,PT_RULE,sui3Frame(P,float4(20,46,20+hall_length*gS,planBottom)));
   txt(float2(26,50),1,1,PT_DIM);
   txt(float2(26,planBottom-14),1,10,PT_DIM);
   txt(float2(20+hall_length*gS-6-phLabelWidth(3,1),planBottom-14),1,3,PT_DIM);
  }else{
   // ---- long section
   float y=(gSB-P.y)/gS+floor_level;
   if(abs(z)<=gHL&&y>=floor_level-.4&&y<=floor_level+hall_height+.4){
    phmDrawTile(c,P,RS,3);
    if(y<floor_level+2.1){int gz=(int)round((z+16)/1.05);float cover=0;
     [loop]for(int dz=-1;dz<=1;dz++){int cz=gz+dz;if(cz<0||cz>=55)continue;
      [loop]for(uint cx=0;cx<56;cx++){Person p=C[cz*56+cx];if(p.p.w<.1)continue;float hz=abs(z-p.p.z);float top=floor_level+p.p.w;
       bool head=length(float2(hz,max(0,y-(top-.12))))<.12;if((hz<.19&&y<top-.2)||head)cover=1;}}
     over(c,PT_DIM*.8,cover);}
   }
   if(design){
    phmDrawTile(c,P,RS,4);
    float yMax=Sil[0].y,ySteel=steelY(),cl=ySteel-yMax;bool low=cl<1.0;float4 cap=Sil[1];
    float yS=sectPx(float3(0,ySteel,0)).y,yM=sectPx(float3(0,yMax,0)).y,cx=sectPx(float3(0,0,0)).x,span=(2*cap.y+2)*gS;
    if(fmod(P.x,10)<6&&P.x>20&&P.x<20+hall_length*gS)over(c,PT_RULE,ink(abs(P.y-yS),1));
    if(abs(P.x-cx)<span&&fmod(P.x,6)<3)over(c,low?PT_ALARM:PT_DIM,ink(abs(P.y-yM),1));
    float dx=cx+(cap.y+1.2)*gS;float3 dim=low?PT_ALARM:PT_INK;
    over(c,dim,ink(sui3SegDist(P,float2(dx,yS),float2(dx,yM)),1));
    over(c,dim,ink(sui3SegDist(P,float2(dx-4,yS),float2(dx+4,yS)),1));over(c,dim,ink(sui3SegDist(P,float2(dx-4,yM),float2(dx+4,yM)),1));
    float2 at=float2(dx+8,(yS+yM)*.5-4);num(at,1,cl,dim,-1);txt(at+float2(sui3FixedWidth(1,1)+4,0),1,6,PT_DIM);
    txt(float2(26,yS-14),1,12,PT_DIM);
    txt(float2(cx-span,yM-14),1,8,low?PT_ALARM:PT_DIM);}
   over(c,PT_RULE,sui3Frame(P,float4(20,gSB-hall_height*1.05*gS,20+hall_length*gS,gSB)));
   txt(float2(26,gSB-hall_height*1.05*gS+4),1,2,PT_DIM);
  }
 }else{
  // ---- readouts
  float x0=W-SIDE+16,y0=58;float2 row=float2(x0,y0);
  over(c,PT_RULE,ink(abs(P.x-(W-SIDE)),1));
  txt(row,1,4,PT_DIM);
  num(row+float2(0,16),2,Marks[VM_REC].fill.x,PT_INK,4);
  row.y+=62;txt(row,1,5,PT_DIM);
  float2 t=row+float2(0,16);num(t,1,round(hall_width),PT_INK,hall_width>=99.5?3:2);t.x+=sui3TextWidth(hall_width>=99.5?3:2,1)+6;txt(t,1,11,PT_DIM);t.x+=phLabelWidth(11,1)+6;
  num(t,1,round(hall_length),PT_INK,hall_length>=99.5?3:2);t.x+=sui3TextWidth(hall_length>=99.5?3:2,1)+6;txt(t,1,11,PT_DIM);t.x+=phLabelWidth(11,1)+6;
  num(t,1,round(hall_height),PT_INK,2);t.x+=sui3TextWidth(2,1)+6;txt(t,1,6,PT_DIM);
  row.y+=48;txt(row,1,9,PT_DIM);
  num(row+float2(0,16),2,Marks[VM_REC].fill.y,PT_INK,2);txt(row+float2(sui3TextWidth(2,2)+8,24),1,15,PT_DIM);
  if(design){float cl=steelY()-Sil[0].y;bool low=cl<1.0;
   row.y+=62;txt(row,1,13,PT_DIM);num(row+float2(0,16),1,Sil[0].x-floor_level,PT_INK,-1);txt(row+float2(sui3FixedWidth(1,1)+4,16),1,6,PT_DIM);
   row.y+=48;txt(row,1,7,low?PT_ALARM:PT_DIM);
   num(row+float2(0,16),2,cl,low?PT_ALARM:PT_INK,-1);txt(row+float2(sui3FixedWidth(2,1)+8,24),1,6,PT_DIM);
   if(low)txt(row+float2(0,40),1,14,PT_ALARM);}
 }
 phDrawText(c);
 OutputUAV[id.xy]=float4(c,1);}
