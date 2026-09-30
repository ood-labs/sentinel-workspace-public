// Pixel-bar content, one texture row per bar (rows 0-63), u along the whole bar. The renderer and the
// Venue sample this texture; rows past 63 stay black. Levels include master, held strobe and blackout.
#include "../_shared/phage_slots.hlsli"
#include "../_shared/phage_show.hlsli"
StructuredBuffer<float4> Show:register(t0);
StructuredBuffer<PhProgram> Program:register(t1);
StructuredBuffer<PhMount> Mounts:register(t2);
struct PhPiece{float4 a;float4 b;float4 n;float4 w;};StructuredBuffer<PhPiece> Q:register(t3);
RWTexture2D<float4> OutputUAV:register(u0);
#include "led_patterns.hlsli"
float3 barPoint(uint b,float u){[loop]for(uint k=0;k<PH_BAR_SEGS;k++){PhPiece q=Q[b*PH_BAR_SEGS+k];if(q.w.z<.5)break;
  if(u<=q.b.w||k==PH_BAR_SEGS-1)return lerp(q.a.xyz,q.b.xyz,saturate((u-q.a.w)/max(1e-4,q.b.w-q.a.w)));}
 return Q[b*PH_BAR_SEGS].a.xyz;}
float3 palette(uint k){return Show[8+min(2u,k)].rgb;}
[numthreads(8,8,1)]void main(uint3 id:SV_DispatchThreadID){uint W,H;OutputUAV.GetDimensions(W,H);if(id.x>=W||id.y>=H)return;
 uint b=id.y;float u=(id.x+.5)/W;float3 c=0;
 if(b<PH_BARS&&_Data2_Count>=PH_SLOTS&&_Data0_Count>=PH_SHOW_COUNT&&_Data3_Count>=PH_BARS*PH_BAR_SEGS){uint slot=PH_BAR0+b;PhMount m=Mounts[slot];
  if(m.active>.5){float beat=Show[2].y;float4 s11=Show[11];float gate=s11.y;
   if(_Data1_Count>=PH_SLOTS&&Show[2].x>.5){PhProgram pr=Program[slot];float rank=phRank(m.rest,m.extra.z,pr.extra.x,pr.timing.z);
    uint lane=phLaneIndex(pr.routing.w);float4 l=lane>0?Show[2+lane]:float4(frac(beat*.25),1,floor(beat*.25),1);
    uint pal=(uint)round(pr.routing.x),pal2=(uint)round(pr.routing.y);float3 base=palette(pal),accent=palette(pal2);
    uint cl=phLaneIndex(pr.movement.x);if(cl>0){float4 lc=Show[2+cl];float k=lc.y*(.5-.5*cos((lc.x+pr.timing.y-rank*pr.movement.w)*TAU));
     base=lerp(base,palette((pal+1)%3),k);accent=lerp(accent,palette((pal2+1)%3),k);}
    c=ledPattern(min(15u,(uint)round(pr.timing.w)),b,u,l,lane,pr,rank,base,accent,barPoint(b,u),beat,gate,Show[12].x)*pr.aim.z*pr.meta.y;}
   else{float rank=phRank(m.rest,m.extra.z,0,Show[1].y);float v=Show[0].y*phPulse(Show[0].x,rank,Show[0].z,Show[0].w);
    c=lerp(palette(0),palette(1),u)*(.12+.88*v);}
   if(s11.x>.5)c=gate;
   if(s11.z>.5)c=0;
   c*=Show[1].z*level;}}
 OutputUAV[id.xy]=float4(c,1);}
