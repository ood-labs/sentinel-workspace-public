// The club's drawing geometry shared by the build, crowd, marks and preview passes: plan over long section on one z
// axis (stage left, audience right), fitted and centred left of the readout column. Call venueView(R) before planPx /
// sectPx. The room runs from stage_depth behind the stage's centre (z = 0) to hall_length in front of that.
#ifndef SS_VENUE_VIEW
#define SS_VENUE_VIEW
#include "../_shared/ss_stage.hlsli"
#include "../_shared/ss_venue.hlsli"
#define SIDE 300.0
// The crowd: a jittered grid from the barrier back (crowd.hlsl writes it, the preview reads it by cell).
#define CROWD_NX 36
#define CROWD_NZ 40
#define CROWD_PITCH .62
#define CROWD_X0 (-.5*(CROWD_NX-1)*CROWD_PITCH)
#define CROWD_BARRIER (SS_FRONT.y+1.6)   // 1.6 m in front of the deck's edge
#define CROWD_Z0 (CROWD_BARRIER+.5)
float roomZ(){return hall_length*.5-stage_depth;}   // the room's centre along z
static float gS,gHW,gHL,gSB,gPB,gX0,gZC;
void venueView(float2 R){gHW=hall_width*.5;gHL=hall_length*.5;gZC=roomZ();
 gS=min((R.x-SIDE-40)/(hall_length*1.02),(R.y-34-50)/((hall_width+hall_height*1.05)*1.02+4));
 gX0=max(20,.5*(R.x-SIDE-hall_length*gS));
 gPB=46+hall_width*gS;gSB=gPB+40+hall_height*1.05*gS;}   // a 40 px gap holds the section's caption
float2 planPx(float3 p){return float2(gX0+(p.z-gZC+gHL)*gS,46+(gHW-p.x)*gS);}
float2 sectPx(float3 p){return float2(gX0+(p.z-gZC+gHL)*gS,gSB-(p.y-floor_level)*gS);}
// And back: the room z under pixel column px, the room x under plan row py.
float venueZ(float px){return (px-gX0)/gS-gHL+gZC;}
float venueX(float py){return gHW-(py-46)/gS;}
// The room's walls in each view; their plates (drawing and layout) sit 8 px outside them.
float4 venuePlanRect(){return float4(gX0,46,gX0+hall_length*gS,gPB);}
float4 venueSectRect(){return float4(gX0,gSB-hall_height*1.05*gS,gX0+hall_length*gS,gSB);}
// The ceiling steel's underside.
float steelY(){return floor_level+hall_height-.4;}
// Marks: plan boxes (clip 1), plan lines (clip 2: the stage outline, live pixel-run emitters), section boxes (clip 3),
// section lines (clip 4), then the counts record (people, lit runs, runs).
#define VM_PLANBOX 0
#define VM_SECTBOX 256
#define VM_SIL 512
#define VM_EMIT 640
#define VM_MARKS (VM_EMIT+PV_EMITTERS)
#define VM_REC VM_MARKS
#define VM_TOTAL (VM_MARKS+1)
#endif
