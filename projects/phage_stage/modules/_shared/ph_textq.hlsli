// Caption queue for the PHAGE canvases. txt() / num() queue a caption only for pixels inside its box,
// so the queue is nearly always empty and costs nothing; phDrawText() then draws what was queued
// through one call site each of phLabel, sui3Digits and sui3Fixed, which keeps compiles short.
// At the top of main set gTN=0 and gTP=P. num(): digits > 0 draws an integer of that many digits,
// digits < 0 a signed fixed value with one decimal. Include after labels.hlsli and sui3_text.hlsli.
#ifndef PH_TEXTQ_HLSLI
#define PH_TEXTQ_HLSLI
#define PH_TEXTQ 4
static float4 gT[PH_TEXTQ];static float4 gTC[PH_TEXTQ];static uint gTN;static float2 gTP;
bool phTextMiss(float2 at,float s,float glyphs){return gTP.y<at.y||gTP.y>=at.y+12*s||gTP.x<at.x||gTP.x>=at.x+(glyphs*SUI3_ADVANCE+9)*s;}
void txt(float2 at,float s,uint id,float3 col){if(gTN<PH_TEXTQ&&!phTextMiss(at,s,(float)PH_LBL_RANGE[id].y)){gT[gTN]=float4(at,s,id);gTC[gTN]=float4(col,0);gTN++;}}
void num(float2 at,float s,float v,float3 col,float digits){if(gTN<PH_TEXTQ&&!phTextMiss(at,s,digits<0?5:digits)){gT[gTN]=float4(at,s,v);gTC[gTN]=float4(col,digits);gTN++;}}
void phDrawText(inout float3 c){[loop]for(uint k=0;k<gTN;k++){float4 t=gT[k],tc=gTC[k];float cov;
  if(tc.w==0)cov=phLabel(gTP,t.xy,t.z,(uint)t.w);else if(tc.w<0)cov=sui3Fixed(gTP,t.xy,t.z,t.w,1);else cov=sui3Digits(gTP,t.xy,t.z,(int)round(t.w),(int)tc.w);
  c=lerp(c,tc.rgb,saturate(cov));}}
#endif
