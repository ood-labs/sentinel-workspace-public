// Laser_Fixture / preview - the Plan and Elevation canvas, the DRAWING only: the room from above
// and from the side on one z axis and one scale (lf_view.hlsli), its metre grid, the wall face and
// the floor, each aperture with its aim (dashed), and the beams as they leave the fixture, each in
// its own colour and stopping where it lands on the wall. The words, rulers, readouts, the
// inspector and the verb are recorded by layout.hlsl and drawn over this by the shared UI kit
// (ui.hlsl). Pixels outside the two drawings skip the beam loop.
#include "../_shared/ui/il_core.hlsli"
struct Beam { float4 origin; float4 direction0; float4 direction1; float4 color0; float4 color1; float4 timing; float4 meta; };
StructuredBuffer<Beam> Beams:register(t0);
RWTexture2D<float4> OutputUAV:register(u0);
#include "pose.hlsli"
#include "lf_view.hlsli"

[numthreads(8,8,1)]
void main(uint3 id:SV_DispatchThreadID){
 uint W,H;OutputUAV.GetDimensions(W,H);
 if(id.x>=W||id.y>=H)return;
 float2 P=(float2)id.xy+0.5;
 LFLayout L=lfLayout(float2(W,H));
 float s=L.s,k=L.k;
 // the plates (layout.hlsl draws their edges and captions, and the readout panes)
 float3 col=IL_FIELD;
 ilOver(col,IL_PANEL,ilFill(ilSdBox(P,L.plan,IL_RADIUS*s)));
 ilOver(col,IL_PANEL,ilFill(ilSdBox(P,L.elev,IL_RADIUS*s)));
 bool elev=ilIn(P,L.elevD);
 if(!elev&&!ilIn(P,L.planD)){OutputUAV[id.xy]=float4(col,1);return;}
 col=IL_WELL;
 // the metre grid from the wall face and from the centre line (plan) or the floor (elevation)
 float wallX=lfZPx(L,0),zeroY=lfPx(L,float3(0,0,0),elev).y;
 ilOver(col,IL_GRID,max(ilGridLine(P.x-wallX,k,1),ilGridLine(P.y-zeroY,k,1)));
 if(!elev)ilOver(col,IL_EDGE,ilStroke(P.y-zeroY,1));
 // behind the wall face and under the floor: hatched; then the floor and the wall face
 float hatch=ilGridLine(P.x+P.y,7*s,1)*0.8;
 if(P.x<wallX)ilOver(col,IL_EDGE,hatch);
 if(elev&&P.y>zeroY)ilOver(col,IL_EDGE,hatch);
 if(elev)ilOver(col,IL_MID,ilStroke(P.y-zeroY,1.5));
 ilOver(col,IL_MID,ilStroke(P.x-wallX,2));
 // each aperture's aim: its forward axis to where it meets the wall, dashed
 uint nf=(uint)clamp(projector_count,1,4);
 [loop]for(uint f=0;f<nf;f++){
  float3 o=apertureFor(f),d=orientFixture(float3(0,0,1),f);
  float2 a=lfPx(L,o,elev),b=lfPx(L,o+d*lfReach(o,d,throw_distance),elev);
  float t=dot(P-a,b-a)/max(length(b-a),1e-3);
  ilOver(col,IL_DIM,ilStroke(ilSdSeg(P,a,b),1)*ilDash(t,5*s,4*s)*0.8);
 }
 // the beams, from their aperture along their start direction to where they land (or their range).
 // Each in its own colour; a dwell (no sweep) strong, every 16th piece medium, the rest faint, so
 // the density of the scan reads at any count.
 uint n=min((uint)max(Beams[0].origin.x,0),4095u);
 float inv=1/max(power,0.001);
 [loop]for(uint i=1;i<=n;i++){
  Beam b=Beams[i];if(b.timing.w>0.5||b.timing.y<=0)continue;
  float3 o=b.origin.xyz,d=b.direction0.xyz;
  float2 a=lfPx(L,o,elev),e=lfPx(L,o+d*lfReach(o,d,b.direction1.w),elev);
  float c=1-smoothstep(1,2,ilSdSeg(P,a,e));
  if(c<=0)continue;
  float strength=length(b.direction1.xyz-d)<1e-5?0.4:((i%16==0)?0.28:0.028);
  col+=ptSampleColour(b.color0.rgb*inv)*c*strength;
 }
 // the apertures, ink on a dark halo
 [loop]for(uint g=0;g<nf;g++){
  float r=length(P-lfPx(L,apertureFor(g),elev));
  ilOver(col,IL_FIELD,ilFill(r-4.5*s));
  ilOver(col,IL_INK,ilFill(r-3*s));
 }
 OutputUAV[id.xy]=float4(min(col,1),1);
}
