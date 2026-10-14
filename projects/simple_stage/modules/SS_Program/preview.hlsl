// Programmer sheet, the drawing: every committed program row as one column, grouped by layer (the Halo
// Beams' MOVE, BEAM, HALO; the Linear Strobes' TUBE, PLATES; the Pixel Battens' PIXELS, CHASE),
// every attribute as one row. Value -> grey ramp over the attribute's range; the two
// colour attributes show which palette (A/B/C) a row uses as identity hues; a cell whose layer does
// not read that attribute is an empty well. Hand-written, not generated. The type, the hover
// crosshair and the inspector are recorded by layout.hlsl and drawn over this by the shared UI kit
// (ui.hlsl); the geometry is sheet.hlsli's, a function of the live panel extent.
#include "../_shared/ss_show.hlsli"
StructuredBuffer<SsProgram>R:register(t0);
RWTexture2D<float4>OutputUAV:register(u0);
#include "../_shared/ui/il_core.hlsli"
#include "sheet.hlsli"
[numthreads(8,8,1)]void main(uint3 id:SV_DispatchThreadID){uint W,H;OutputUAV.GetDimensions(W,H);if(id.x>=W||id.y>=H)return;
 float2 P=id.xy+.5;float3 c=IL_FIELD;uint n,st;R.GetDimensions(n,st);bool ok=n>=SHEET_COLS&&R[0].meta.w==260933;Sheet g=sheetOf(float2(W,H));
 float d=ilSdBox(P,g.pane,IL_RADIUS*g.s);ilOver(c,IL_PANEL,ilFill(d));
 ilOver(c,IL_PANEL,ilFill(ilSdBox(P,g.strip,IL_RADIUS*g.s)));
 uint a=(uint)floor((P.y-g.grid.y)/g.rowH);
 if(d<=0&&P.y>=g.grid.y&&a<SHEET_ROWS){
  float ry=g.grid.y+a*g.rowH;uint i=colAt(g,P.x);
  if(ok&&i!=SHEET_NONE&&P.x-colX(g,i)<g.cell&&P.y>ry+2&&P.y<ry+g.rowH-2){
   if((SHEET_READS[sheetGroup(i)]>>a)&1u){float v=sheetAttr(R[sheetRow(i)],a);float2 rg=SHEET_RANGE[a];float t=saturate((v-rg.x)/(rg.y-rg.x));
    c=(a==4||a==5)?ptId((int)round(v)):ptRamp(t);}
   else c=IL_WELL;}
  if(a+1<SHEET_ROWS)ilOver(c,IL_GRID,ilStroke(P.y-(ry+g.rowH),1));
 }
 OutputUAV[id.xy]=float4(c,1);}
