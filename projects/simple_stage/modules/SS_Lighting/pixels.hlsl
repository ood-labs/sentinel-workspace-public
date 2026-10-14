// SS_Lighting / pixels - pixel-bar content, one texture row per bar (rows 0-63), u along the whole bar. The renderer and the
// Venue sample this texture; rows past 63 stay black. Levels include master, held strobe and blackout.
// Layered programming (SS_Program `layered`): the bar's CHASE row (slot + 376) shapes the content with its own
// lane and look, as deep as its LEVEL; a CHASE row with no lane leaves it as it is (x1).
// PIXEL FX speed: content codes 0-15 run once per lane cycle, 16-31 twice, 32-47 four and 48-63 eight times (the
// content is code % 16), so a pass along a leg can take two beats of a 16-beat phrase.
#include "../_shared/ss_slots.hlsli"
#include "../_shared/ss_show.hlsli"
StructuredBuffer<float4> Show:register(t0);
StructuredBuffer<SsProgram> Program:register(t1);
StructuredBuffer<SsMount> Mounts:register(t2);
struct SsPiece{float4 a;float4 b;float4 n;float4 w;};StructuredBuffer<SsPiece> Q:register(t3);
RWTexture2D<float4> OutputUAV:register(u0);
#include "led_patterns.hlsli"
float3 barPoint(uint b,float u){[loop]for(uint k=0;k<SS_BAR_SEGS;k++){SsPiece q=Q[b*SS_BAR_SEGS+k];if(q.w.z<.5)break;
  if(u<=q.b.w||k==SS_BAR_SEGS-1)return lerp(q.a.xyz,q.b.xyz,saturate((u-q.a.w)/max(1e-4,q.b.w-q.a.w)));}
 return Q[b*SS_BAR_SEGS].a.xyz;}
float3 palette(uint k){return Show[8+min(2u,k)].rgb;}
// The CHASE envelope of a bar: PULSE (lane pulse, with the mover FX repeats and RND gate on codes 16-23),
// 1 STROBE (flashes at the show strobe rate while the pulse is up), 3 BLINDER (a squared decay per lane cycle),
// 24-27 HOLD x1-x8: the content shows for WIDTH of each lane cycle (x repeats) from OFFSET, rippling through the
// group by rank x SPREAD, and is dark the rest of the time, so CHASE pads can hand the light from group to group.
// HOLD at its narrowest WIDTH (0.01) never opens: the group stays dark.
float chaseEnvelope(SsProgram pr,SsMount m,uint slot,float gate){
 uint lane=ssLaneIndex(pr.routing.w);if(lane==0)return 1;
 float4 l=Show[2+lane];float rank=ssRank(m.rest,m.extra.z,pr.extra.x,pr.timing.z);uint look=(uint)round(pr.timing.w);
 float env=ssChase(pr,l,rank,slot);     // PULSE and HOLD (ss_show.hlsli)
 if(look==1)env=gate*saturate(env*4);else if(look==3)env=l.y*(1-l.x)*(1-l.x);
 return lerp(1,env,saturate(pr.aim.z));
}
[numthreads(8,8,1)]void main(uint3 id:SV_DispatchThreadID){uint W,H;OutputUAV.GetDimensions(W,H);if(id.x>=W||id.y>=H)return;
 uint b=id.y;float u=(id.x+.5)/W;float3 c=0;
 if(b<SS_BARS&&_Data0_Count>=SS_SLOTS&&_Data1_Count>=SS_SHOW_COUNT&&_Data3_Count>=SS_BARS*SS_BAR_SEGS){uint slot=SS_BAR0+b;SsMount m=Mounts[slot];
  if(m.active>.5){float beat=Show[2].y;float4 s11=Show[11];float gate=s11.y;
   if(_Data2_Count>=SS_SLOTS&&Show[2].x>.5){SsProgram pr=Program[slot];float rank=ssRank(m.rest,m.extra.z,pr.extra.x,pr.timing.z);
    uint lane=ssLaneIndex(pr.routing.w);float4 l=lane>0?Show[2+lane]:float4(frac(beat*.25),1,floor(beat*.25),1);
    uint code=(uint)round(pr.timing.w);l.x=frac(l.x*exp2((float)min(code/16u,3u)));SsProgram pc=pr;pc.timing.w=(float)(code%16u);
    uint pal=(uint)round(pr.routing.x),pal2=(uint)round(pr.routing.y);float3 base=palette(pal),accent=palette(pal2);
    uint cl=ssLaneIndex(pr.movement.x);if(cl>0){float4 lc=Show[2+cl];float k=lc.y*(.5-.5*cos((lc.x+pr.timing.y-rank*pr.movement.w)*TAU));
     base=lerp(base,palette((pal+1)%3),k);accent=lerp(accent,palette((pal2+1)%3),k);}
    c=ledPattern(code%16u,b,u,l,lane,pc,rank,base,accent,barPoint(b,u),beat,gate,Show[12].x)*pr.aim.z*pr.meta.y;
    if(_Data2_Count>=SS_ROWS&&Program[0].extra.y>.5)c*=chaseEnvelope(Program[SS_LAYER2+slot],m,slot,gate);}
   else{float rank=ssRank(m.rest,m.extra.z,0,Show[1].y);float v=Show[0].y*ssPulse(Show[0].x,rank,Show[0].z,Show[0].w);
    c=lerp(palette(0),palette(1),u)*(.12+.88*v);}
   if(s11.x>.5)c=gate;
   if(s11.z>.5)c=0;
   c*=Show[1].z*bar_level;}}
 OutputUAV[id.xy]=float4(c,1);}
