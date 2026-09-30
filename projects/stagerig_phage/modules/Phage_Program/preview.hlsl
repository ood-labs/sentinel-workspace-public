// Programmer sheet: every committed program row as one column (movers, strobes, bars, kinetic axes),
// every attribute as one row. Value -> grey ramp over the attribute's range; the two colour
// attributes show which palette (A/B/C) a slot uses as identity hues. Hand-written, not generated.
#include "../_shared/phage_show.hlsli"
StructuredBuffer<PhProgram>R:register(t0);
RWTexture2D<float4>OutputUAV:register(u0);
#include "../_shared/plan_theme.hlsli"
#include "../_shared/ui/sui3_core.hlsli"
#include "../_shared/ui/sui3_text.hlsli"
#include "labels.hlsli"
static const float2 RANGE[17]={float2(-270,270),float2(-135,135),float2(0,1),float2(0,1),float2(0,2),float2(0,2),float2(0,5),float2(0,5),
 float2(0,5),float2(-180,180),float2(-90,90),float2(0,.95),float2(0,1),float2(-1,1),float2(0,1),float2(0,51),float2(0,7)};
float attr(PhProgram r,uint a){float4 v=a<4?r.aim:a<8?r.routing:a<12?r.movement:a<16?r.timing:r.extra;uint k=a%4;if(a>=16)k=0;return k==0?v.x:k==1?v.y:k==2?v.z:v.w;}
void over(inout float3 c,float3 k,float a){c=lerp(c,k,saturate(a));}
#include "../_shared/ph_textq.hlsli"
#define X0 130.0
#define GAP 10.0
float slotX(uint i){return X0+i*4.4+(i>=128?GAP:0)+(i>=176?GAP:0)+(i>=240?GAP:0);}
[numthreads(8,8,1)]void main(uint3 id:SV_DispatchThreadID){uint W,H;OutputUAV.GetDimensions(W,H);if(id.x>=W||id.y>=H)return;
 float2 P=id.xy+.5;float3 c=PT_FIELD;gTN=0;gTP=P;bool ok=R[0].meta.w==260933;
 float rowH=(H-80.0)/17;float y0=70;
 if(P.y<34){txt(float2(14,10),2,0,PT_INK);
  if(ok){float x=W-470;txt(float2(x,15),1,22,PT_DIM);num(float2(x+56,15),1,fmod(R[0].meta.x,10000000),PT_INK,7);
   txt(float2(x+150,15),1,23,PT_DIM);num(float2(x+206,15),1,R[0].meta.y,PT_INK,-1);
   txt(float2(x+290,15),1,24,PT_DIM);num(float2(x+340,15),1,R[0].meta.z,PT_INK,-1);}}
 else{
  // family captions
  if(P.y<y0){txt(float2(slotX(0),48),1,18,PT_DIM);txt(float2(slotX(128),48),1,19,PT_DIM);txt(float2(slotX(176),48),1,20,PT_DIM);txt(float2(slotX(240),48),1,21,PT_DIM);}
  uint a=(uint)floor((P.y-y0)/rowH);
  if(P.y>=y0&&a<17){
   float ry=y0+a*rowH;txt(float2(14,ry+rowH*.5-4),1,1+a,PT_DIM);
   if(ok&&P.x>=X0){uint fam=P.x<slotX(128)?0:P.x<slotX(176)?1:P.x<slotX(240)?2:3;uint base=fam==0?0:fam==1?128:fam==2?176:240;
    float fx=P.x-slotX(base);uint i=base+(uint)floor(fx/4.4);uint lim=fam==0?128:fam==1?176:fam==2?240:248;
    if(i<lim&&fx>=0&&frac(fx/4.4)*4.4<3.6&&P.y>ry+2&&P.y<ry+rowH-2){float v=attr(R[i],a);float2 rg=RANGE[a];float t=saturate((v-rg.x)/(rg.y-rg.x));
     c=(a==4||a==5)?ptId((int)round(v)):ptRamp(t);}}
   over(c,PT_GRID,sui3Hair(abs(P.y-(ry+rowH))));
  }
 }
 phDrawText(c);
 OutputUAV[id.xy]=float4(c,1);}
