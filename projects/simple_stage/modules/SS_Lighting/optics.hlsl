// Optics: per mover one beam and 24 ring pixels (SS_OPT_PER records), then 48 strobe records written
// in the SsStrobe layout (ssStrobeOf in ss_fixture.hlsli reads them back). Levels already include
// master, chases, held strobe, highlight/solo and blackout.
// Strobe LOOK: 0 PULSE (lane pulse, or steady with no lane), 1 STROBE (flashes at the show strobe rate
// while the lane pulse is up), 2 SPARKLE (random tubes on each strobe tick), 3 BLINDER (warm hit with
// a squared decay per lane cycle), 4 GLOW (plate follows the lane, tube dark), 5 OFF,
// 16-47 mover FX codes (repeats / RND gate) like PULSE.
// Layered programming (SS_Program `layered`): a mover's beam reads its BEAM row and its halo its HALO row; a
// strobe's tube reads its TUBE row and its plates their PLATES row, each with its own look, lane and chase.
#include "lighting.hlsli"
StructuredBuffer<SsMoverPose> Poses:register(t0);
StructuredBuffer<float4> Sel:register(t1);
StructuredBuffer<float4> Show:register(t2);
StructuredBuffer<SsProgram> Program:register(t3);
StructuredBuffer<SsMount> Mounts:register(t4);
RWStructuredBuffer<SsOptical> Optics:register(u0);
SsOptical opticalOfStrobe(SsStrobe s){SsOptical o;o.position=s.position;o.fixture_id=s.fixture_id;o.normal=s.fwd;o.local_id=s.tube;o.colour=s.up;o.intensity=s.plate;
 o.beam_tangent=s.tube_colour.x;o.field_tangent=s.tube_colour.y;o.reach=s.tube_colour.z;o.active=s.length;o.frost=s.plate_colour.x;o.padding=float3(s.plate_colour.yz,s.active);return o;}
bool programmer(){return _Data2_Count>=SS_SLOTS&&_Data1_Count>=SS_SHOW_COUNT&&Show[2].x>.5;}
bool layered(){return _Data2_Count>=SS_ROWS&&Program[0].extra.y>.5;}
float3 palette(uint k){return Show[8+min(2u,k)].rgb;}
float3 colourLane(SsProgram pr,uint pal,float3 colour,float rank){uint cl=ssLaneIndex(pr.movement.x);if(cl==0)return colour;float4 l=Show[2+cl];
 return lerp(colour,palette((pal+1)%3),l.y*(.5+.5*sin((l.x+pr.timing.y-rank*pr.movement.w)*6.2831853)));}
// A strobe's tube and plate levels and colours from one program row (its TUBE row, or with layers its PLATES row for
// the plate).
void strobeRow(SsProgram pr,SsMount m,uint s,uint slot,float gate,inout float tube,inout float plate,inout float3 tubeCol,inout float3 plateCol){
 float rank=ssRank(m.rest,m.extra.z,pr.extra.x,pr.timing.z);uint look=(uint)round(pr.timing.w);
 uint lane=ssLaneIndex(pr.routing.w);float4 l=lane>0?Show[2+lane]:float4(0,1,0,1);float env=lane>0?ssChase(pr,l,rank,slot):1;
 uint pal=(uint)round(pr.routing.x);plateCol=colourLane(pr,pal,palette(pal),rank);float v;
 if(look==1)v=gate*saturate(env*4);
 else if(look==2){float tick=floor(Show[2].y*Show[12].x);v=(ssHash(float3(s,tick,3))<.2?gate:0)*(lane>0?l.y:1);}
 else if(look==3){v=lane>0?l.y*(1-l.x)*(1-l.x):1;tubeCol=float3(1,.55,.22);}
 else v=env;
 tube=pr.aim.z*v*pr.meta.y;plate=pr.aim.w*(look==1||look==2?saturate(env):v)*pr.meta.y;
 if(look==4)tube=0;if(look==5){tube=0;plate=0;}
}
[numthreads(64,1,1)]void main(uint3 tid:SV_DispatchThreadID){uint i=tid.x;if(i>=SS_OPT_COUNT)return;
 bool showOk=_Data1_Count>=SS_SHOW_COUNT;bool prog=programmer();float4 s11=showOk?Show[11]:0;bool held=s11.x>.5,black=s11.z>.5;float gate=s11.y;
 if(i<SS_OPT_STROBE0){uint parent=i/SS_OPT_PER,k=i%SS_OPT_PER;SsMoverPose r=Poses[parent];SsOptical o=(SsOptical)0;
  if(r.active>.5&&showOk){bool ring=k>0;SsMount m=Mounts[parent];float sel=Sel[SEL_SLOT0+parent].x;float3 colour;float level;
   if(prog){SsProgram pr=Program[layered()?(ring?SS_LAYER2:SS_BEAM0)+parent:parent];float rank=ssRank(m.rest,m.extra.z,pr.extra.x,pr.timing.z);uint pal=(uint)round(ring?pr.routing.y:pr.routing.x);
    uint lane=ssLaneIndex(pr.routing.w);float chase=lane>0?ssChase(pr,Show[2+lane],rank,parent):1;
    colour=colourLane(pr,pal,palette(pal),rank);level=(ring?pr.aim.w:pr.aim.z)*chase*pr.meta.y;}
   else{float rank=ssRank(m.rest,m.extra.z,0,Show[1].y);colour=palette(ring?1:0);level=Show[0].y*(ring?.6:1)*ssPulse(Show[0].x,rank,Show[0].z,Show[0].w);}
   if(held){colour=1;level=gate;}
   if(highlight&&sel>.5){colour=1;level=1;}
   if(solo_selected&&sel<.5)level=0;
   if(black)level=0;
   o.colour=colour;o.intensity=level*dimmer*exp2(boost)*(ring?ring_master*.2:main_master*8);
   o.padding.y=saturate(level*dimmer*(ring?ring_master:main_master));   // the desk level DMX carries (no render gain)
   float a=(k-1.0)*6.2831853/24;float3 local=ring?float3(sin(a)*.086,cos(a)*.086,-.074):float3(0,0,-.07);
   o.position=ssHeadPoint(r,local);o.normal=ssHeadNormal(r,float3(0,0,-1));o.fixture_id=parent;o.local_id=ring?k-1:0;o.active=1;
   o.beam_tangent=tan(radians(ring?55:beam_angle*.5));o.field_tangent=tan(radians(ring?80:beam_angle*.75));o.reach=reach;o.padding.x=ring?1:0;}
  Optics[i]=o;return;}
 uint s=i-SS_OPT_STROBE0,slot=SS_STROBE0+s;SsStrobe st=(SsStrobe)0;
 if(slot<_Data0_Count&&showOk){SsMount m=Mounts[slot];
  if(m.active>.5&&m.kind==1){float sel=Sel[SEL_SLOT0+slot].x;float tube=0,plate=0;float3 tubeCol=float3(1,.96,.9),plateCol=palette(0);
   if(prog){float3 unusedCol;float unused;
    strobeRow(Program[slot],m,s,slot,gate,tube,unused,tubeCol,plateCol);
    if(layered())strobeRow(Program[SS_LAYER2+slot],m,s,slot,gate,unused,plate,unusedCol,plateCol);
    else strobeRow(Program[slot],m,s,slot,gate,unused,plate,unusedCol,plateCol);}
   else{float rank=ssRank(m.rest,m.extra.z,0,Show[1].y);plate=.5*Show[0].y*ssPulse(Show[0].x,rank,Show[0].z,Show[0].w);}
   if(held){tube=gate;plate=gate*.6;tubeCol=1;plateCol=1;}
   if(highlight&&sel>.5){tube=.35;plate=1;plateCol=1;}
   if(solo_selected&&sel<.5){tube=0;plate=0;}
   if(black){tube=0;plate=0;}
   st.position=m.position;st.fixture_id=slot;st.fwd=m.fwd;st.up=m.up;st.tube=tube*strobe_master*dimmer;st.plate=plate*strobe_master*dimmer;
   st.tube_colour=tubeCol;st.plate_colour=plateCol;st.length=SS_STROBE_LENGTH;st.active=1;}}
 Optics[i]=opticalOfStrobe(st);}
