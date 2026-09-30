// One working mapping, always bank 0 of the points buffer (the buffer keeps its three-bank size
// so saved projects and presets stay valid; see update.hlsl for the one-time migration).
#ifndef BANK
#define BANK 0
#endif
#include "quad.hlsli"
RWStructuredBuffer<float4> OutputBuffer:register(u0);
StructuredBuffer<float4> C:register(t0);
// A fresh or reset mapping is a small square at the centre of the field (0.12 of the editor's
// 0.1..0.9 span, about 15% of the scanner's reach), never the full field: a reset must not sweep
// the beam over the whole room. Zoom in on it and drag it out to the surface from there.
float2 regular(int i){return .44+.12*float2(i%5,i/5)/4;}
bool isCorner(int i){return i==0||i==4||i==20||i==24;}
[numthreads(1,1,1)]
void main(uint3 id:SV_DispatchThreadID){
 [unroll]for(int bank=0;bank<3;bank++)if(OutputBuffer[bank*52+51].w!=4126){
 [unroll]for(int j=0;j<25;j++){OutputBuffer[bank*52+j]=float4(regular(j),0,j+1);OutputBuffer[bank*52+25+j]=OutputBuffer[bank*52+j];}
 OutputBuffer[bank*52+50]=0;OutputBuffer[bank*52+51]=float4(0,0,0,4126);}
 // reset_grid is a `button`, and a button uniform can latch high and never
 // clear: the StateTree reads 0 while the shader still sees 1. Held that way,
 // this branch re-flattened the mapping on every cook, so any drag snapped
 // straight back. Fire on the RISING EDGE only, exactly as fit_view and
 // select_all already do against C[7]. Reset has no hotkey on purpose: it moves the beam,
 // so it takes a deliberate press of the Properties button.
 // OutputBuffer[BANK+51] = (previous reset_grid, 0, 0, cookie).
 // One-time migration from the three-slot editor: the slot that was selected becomes the one
 // working mapping in bank 0. OutputBuffer[51].y is the layout version (1 = single mapping).
 if(OutputBuffer[51].y<.5){
  int s=clamp((int)slot,0,2);
  if(s>0){[unroll]for(int j=0;j<51;j++)OutputBuffer[j]=OutputBuffer[s*52+j];}
  OutputBuffer[51]=float4(OutputBuffer[51].x,1,0,4126);
 }
 bool fresh=OutputBuffer[BANK+51].w!=4126;
 bool buttonEdge=reset_grid>.5&&OutputBuffer[BANK+51].x<.5;
 if(fresh||buttonEdge){
  [unroll]for(int i=0;i<25;i++){OutputBuffer[BANK+i]=float4(regular(i),0,i+1);OutputBuffer[BANK+25+i]=OutputBuffer[BANK+i];}
  OutputBuffer[BANK+50]=0;OutputBuffer[BANK+51]=float4(0,1,0,4126);
 }
 OutputBuffer[BANK+51].x=reset_grid>.5?1:0;
 if(C[3].x>.5){[unroll]for(int k=0;k<25;k++)OutputBuffer[BANK+25+k]=OutputBuffer[BANK+k];}
 if(C[3].y>.5){
  int k=(int)C[2].z;float2 delta=C[1].zw-C[1].xy;
  if(C[4].x==1&&isCorner(k)){
   float2 a=OutputBuffer[BANK+25].xy,b=OutputBuffer[BANK+29].xy,c=OutputBuffer[BANK+49].xy,d=OutputBuffer[BANK+45].xy;
   float3x3 old=quadMatrix(a,b,c,d);float2 target=OutputBuffer[BANK+25+k].xy+delta;
   if(k==0)a=target;if(k==4)b=target;if(k==24)c=target;if(k==20)d=target;
   if(convex(a,b,c,d)){
    float3x3 change=mul(quadMatrix(a,b,c,d),inv3(old));
    [unroll]for(int j=0;j<25;j++){float4 v=OutputBuffer[BANK+25+j];v.xy=applyQuad(change,v.xy);OutputBuffer[BANK+j]=v;}
   }
  }else{
   [unroll]for(int j=0;j<25;j++)if(C[8+j].x>.5){float4 v=OutputBuffer[BANK+25+j];v.xy+=delta;OutputBuffer[BANK+j]=v;}
  }
 }
 if(C[3].z>.5){[unroll]for(int k=0;k<25;k++)OutputBuffer[BANK+k]=OutputBuffer[BANK+25+k];}
 // Arrow-key nudge from canvas.hlsl: applied to the committed points and committed at once,
 // so it composes with drags. A lone corner moves the grid projectively, as a corner drag does.
 float2 nudge=C[33].xy;
 if(any(nudge!=0)&&C[2].x!=1){
  int lone=-1;[unroll]for(int j=0;j<25;j++)if(C[8+j].x>.5)lone=(C[4].x==1)?j:lone;
  if(lone>=0&&isCorner(lone)){
   float2 a=OutputBuffer[BANK].xy,b=OutputBuffer[BANK+4].xy,c=OutputBuffer[BANK+24].xy,d=OutputBuffer[BANK+20].xy;
   float3x3 old=quadMatrix(a,b,c,d);float2 target=OutputBuffer[BANK+lone].xy+nudge;
   if(lone==0)a=target;if(lone==4)b=target;if(lone==24)c=target;if(lone==20)d=target;
   if(convex(a,b,c,d)){float3x3 change=mul(quadMatrix(a,b,c,d),inv3(old));
    [unroll]for(int j=0;j<25;j++){float4 v=OutputBuffer[BANK+j];v.xy=applyQuad(change,v.xy);OutputBuffer[BANK+j]=v;}}
  }else{[unroll]for(int j=0;j<25;j++)if(C[8+j].x>.5)OutputBuffer[BANK+j].xy+=nudge;}
  [unroll]for(int k=0;k<25;k++)OutputBuffer[BANK+25+k]=OutputBuffer[BANK+k];
 }
 OutputBuffer[BANK+50]=0;
}
