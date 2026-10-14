// The club in plan over a long section, sharing one z axis (stage left, audience right). The plan shows
// the stage, the PA, the barrier, the crowd, the front-of-house riser, the bar and the live pixel runs in their own
// colour. The section shows the rig against the ceiling steel, and the clearance over its highest head. Plan: page up = +x (house right). Section: seen from house left. Boxes,
// silhouette and emitters arrive as marks (marks.hlsl) drawn through tile bins; counts as a record.
// The type, the view frames and the readout column are recorded by layout.hlsl and drawn over this
// by the shared UI kit (ui.hlsl).
#include "venue_view.hlsli"
struct Architecture{float4 center,extent,surface,rotation;};StructuredBuffer<Architecture>A:register(t0);
struct Person{float4 p;float4 look;};StructuredBuffer<Person> C:register(t1);
struct Emitter{float4 a,b,radiance;};StructuredBuffer<Emitter> E:register(t2);
StructuredBuffer<float4> Sil:register(t3);
RWTexture2D<float4>OutputUAV:register(u0);
#include "../_shared/ui/il_core.hlsli"
#include "../_shared/ss_marks.hlsli"
StructuredBuffer<SsMark> Marks:register(t4);
StructuredBuffer<uint> Bins:register(t5);
#define SSM_MARKS_BUF Marks
#define SSM_BINS_BUF Bins
#define SSM_MARKS VM_MARKS
#include "../_shared/ss_marks.hlsli"
void over(inout float3 c,float3 k,float a){c=lerp(c,k,saturate(a));}
float ink(float d,float w){return saturate(w*.5+.5-d);}
[numthreads(8,8,1)]void main(uint3 id:SV_DispatchThreadID){uint W,H;OutputUAV.GetDimensions(W,H);if(id.x>=W||id.y>=H)return;
 float2 P=id.xy+.5;float3 c=IL_FIELD;
 float2 RS=float2(W,H);venueView(RS);float planBottom=gPB;
 bool design=Sil[0].w==260932;float z=venueZ(P.x);
 if(P.y<34||P.x>=W-SIDE){OutputUAV[id.xy]=float4(c,1);return;}   // header and readout column: the kit draws them
 if(P.y<planBottom+15){
  // ---- plan
  float4 pr=venuePlanRect();over(c,IL_PANEL,ilFill(ilSdBox(P,ilInset(pr,-8),IL_RADIUS)));
  float x=venueX(P.y);float2 q=float2(x,z);
  if(abs(x)<=gHW&&abs(z-gZC)<=gHL){
   ssmDrawTile(c,P,RS,1);
   int gx=(int)round((x-CROWD_X0)/CROWD_PITCH),gz=(int)round((z-CROWD_Z0)/CROWD_PITCH);
   [loop]for(int dz=-1;dz<=1;dz++)[loop]for(int dx=-1;dx<=1;dx++){int cx=gx+dx,cz=gz+dz;if(cx<0||cx>=CROWD_NX||cz<0||cz>=CROWD_NZ)continue;Person p=C[cz*CROWD_NX+cx];if(p.p.w<.1)continue;
    float d=length(q-p.p.xz)*gS;if(d<2.4)over(c,p.look.y+p.look.z>.1?PT_MID:PT_DIM,2.4-d);}
  }
  ssmDrawTile(c,P,RS,2);
  over(c,IL_RULE,ilBorder(ilSdBox(P,pr,0),1));   // the hall walls
 }else{
  // ---- long section
  float4 sr=venueSectRect();over(c,IL_PANEL,ilFill(ilSdBox(P,ilInset(sr,-8),IL_RADIUS)));
  float y=(gSB-P.y)/gS+floor_level;
  if(abs(z-gZC)<=gHL&&y>=floor_level-.4&&y<=floor_level+hall_height+.4){
   ssmDrawTile(c,P,RS,3);
   if(y<floor_level+2.1){int gz=(int)round((z-CROWD_Z0)/CROWD_PITCH);float cover=0;
    [loop]for(int dz=-1;dz<=1;dz++){int cz=gz+dz;if(cz<0||cz>=CROWD_NZ)continue;
     [loop]for(uint cx=0;cx<CROWD_NX;cx++){Person p=C[cz*CROWD_NX+cx];if(p.p.w<.1)continue;float hz=abs(z-p.p.z);float top=floor_level+p.p.w;
      bool head=length(float2(hz,max(0,y-(top-.12))))<.12;if((hz<.19&&y<top-.2)||head)cover=1;}}
    over(c,PT_DIM*.8,cover);}
  }
  if(design){
   // the ceiling steel, the rig's highest head, and the clearance between them
   ssmDrawTile(c,P,RS,4);
   float yMax=Sil[0].y,ySteel=steelY(),cl=ySteel-yMax;bool low=cl<1.0;float4 cap=Sil[1];
   float yS=sectPx(float3(0,ySteel,0)).y,yM=sectPx(float3(0,yMax,0)).y,cx=sectPx(float3(0,0,0)).x,span=(2*cap.y+2)*gS;
   if(fmod(P.x,10)<6&&P.x>gX0&&P.x<gX0+hall_length*gS)over(c,IL_RULE,ink(abs(P.y-yS),1));
   if(abs(P.x-cx)<span&&fmod(P.x,6)<3)over(c,low?IL_ALARM:IL_DIM,ink(abs(P.y-yM),1));
   float dx=cx+(cap.y+1.2)*gS;float3 dim=low?IL_ALARM:IL_INK;
   over(c,dim,ink(ilSdSeg(P,float2(dx,yS),float2(dx,yM)),1));
   over(c,dim,ink(ilSdSeg(P,float2(dx-4,yS),float2(dx+4,yS)),1));over(c,dim,ink(ilSdSeg(P,float2(dx-4,yM),float2(dx+4,yM)),1));}
  over(c,IL_RULE,ilBorder(ilSdBox(P,sr,0),1));   // the hall walls
 }
 OutputUAV[id.xy]=float4(c,1);}
