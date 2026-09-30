// Arena drawing geometry shared by the marks pass and the preview: plan over long section on one z
// axis, fitted left of the readout column. Call venueView(R) before planPx / sectPx.
#define SIDE 300.0
static float gS,gHW,gHL,gSB,gPB;
void venueView(float2 R){gHW=hall_width*.5;gHL=hall_length*.5;
 gS=min((R.x-SIDE-40)/(hall_length*1.02),(R.y-34-40)/((hall_width+hall_height*1.05)*1.02+4));
 gPB=46+hall_width*gS;gSB=gPB+30+hall_height*1.05*gS;}
float2 planPx(float3 p){return float2(20+(p.z+gHL)*gS,46+(gHW-p.x)*gS);}
float2 sectPx(float3 p){return float2(20+(p.z+gHL)*gS,gSB-(p.y-floor_level)*gS);}
// Marks: plan boxes (clip 1), plan lines (clip 2: silhouette plan view, live bar emitters),
// section boxes (clip 3), section lines (clip 4), then the counts record (people, lit bars).
#define VM_PLANBOX 0
#define VM_SECTBOX 256
#define VM_SIL 512
#define VM_EMIT 640
#define VM_MARKS 736
#define VM_REC 736
#define VM_TOTAL 737
